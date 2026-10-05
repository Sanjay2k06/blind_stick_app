import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';
import '../models/person_model.dart';
import 'database_service.dart';
import 'face_quality_service.dart';
import 'navigation_decision_engine.dart';

class FaceMatch {
  final int? personId;
  final String name;
  final String imagePath;
  final double confidence;
  final Rect? faceBoundingBox;
  final double faceCenterXRatio; // 0.0 - 1.0 (relative to frame width)
  final ObjectDirection direction;
  final bool isConfirmed;
  final int consecutiveFrames;

  const FaceMatch({
    this.personId,
    required this.name,
    required this.imagePath,
    required this.confidence,
    this.faceBoundingBox,
    required this.faceCenterXRatio,
    required this.direction,
    this.isConfirmed = false,
    this.consecutiveFrames = 1,
  });

  /// Computes horizontal direction strictly from face bounding box center:
  /// LEFT: face center < 35% of frame width (< 0.35)
  /// CENTER: 35%–65% (0.35 - 0.65)
  /// RIGHT: > 65% (> 0.65)
  static ObjectDirection calculateFaceDirection(double faceCenterXRatio) {
    if (faceCenterXRatio < 0.35) {
      return ObjectDirection.left;
    } else if (faceCenterXRatio > 0.65) {
      return ObjectDirection.right;
    } else {
      return ObjectDirection.center;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FaceRecognitionService — MobileFaceNet (ArcFace, WebFace600K) via ONNX
//
// Pipeline per frame:
//   ML Kit detects face on FULL frame → crop + eye-align → 112×112 → normalise
//   → ONNX inference → 512-dim embedding → compare with ALL reference embeddings
//   → multi-reference aggregate similarity → temporal confirmation across frames
//   → centralized VoiceAlertManager with directional audio
// ─────────────────────────────────────────────────────────────────────────────
class FaceRecognitionService {
  static final FaceRecognitionService instance = FaceRecognitionService._();
  FaceRecognitionService._();

  late FaceDetector _detector;
  OrtSession?       _session;
  List<Person>      _knownPeople  = [];
  bool              _initialized  = false;

  int?    _pendingMatchPersonId;
  String? _pendingMatchName;
  int     _pendingCount = 0;
  String? _tempFilePath;

  /// Configurable cosine similarity threshold.
  double similarityThreshold = 0.50;

  /// Ambiguity margin required between best match and runner-up.
  double ambiguityMargin = 0.08;

  /// Required consecutive stable frames before confirming identity.
  static const int _confirmFrames = 2;

  /// Embedding dimension produced by MobileFaceNet.
  static const int _embDim = 512;

  List<Person> get knownPeople => List.unmodifiable(_knownPeople);

  // ── Initialise ──────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) {
      await refreshKnownPeople();
      return;
    }
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks:      true,
        enableContours:       false,
        enableClassification: false,
        performanceMode:      FaceDetectorMode.accurate,
        minFaceSize:          0.07,
      ),
    );

    try {
      OrtEnv.instance.init();
      final modelData = await rootBundle.load('assets/models/mobilefacenet.onnx');
      final bytes = modelData.buffer.asUint8List(
          modelData.offsetInBytes, modelData.lengthInBytes);
      final opts = OrtSessionOptions()
        ..setInterOpNumThreads(1)
        ..setIntraOpNumThreads(2);
      _session = OrtSession.fromBuffer(bytes, opts);
      debugPrint('FaceNet: MobileFaceNet ONNX loaded');
    } catch (e) {
      debugPrint('FaceNet: ONNX load failed — $e');
    }

    _initialized = true;
    await refreshKnownPeople();

    // Automatically enroll sample profile if database has no enrolled people
    if (_knownPeople.isEmpty) {
      try {
        await enrollSamplePersonProfile();
      } catch (e) {
        debugPrint('Sample enrollment init note: $e');
      }
    }
  }

  Future<void> refreshKnownPeople() async {
    final all = await DatabaseService.instance.getAllPersons();
    _knownPeople = all.where((p) => p.embedding.isNotEmpty).toList();
    debugPrint('FaceNet DB: ${_knownPeople.length} people with embeddings');
  }

  // ── Extract embedding from a saved photo (called once on registration) ──────
  Future<List<double>?> extractEmbeddingFromFile(String imagePath) async {
    if (!_initialized) await init();
    if (_session == null) {
      debugPrint('FaceNet: ONNX session not ready');
      return null;
    }
    try {
      final bytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(Uint8List.fromList(bytes));
      if (image == null) return null;

      try {
        final inputImage = InputImage.fromFilePath(imagePath);
        final faces = await _detector.processImage(inputImage);
        if (faces.isNotEmpty) {
          final emb = _computeEmbedding(image, faces.first);
          if (emb != null) return emb;
        }
      } catch (_) {
        // Fallback for environments where native ML Kit is unavailable
      }

      // Center crop fallback if detector was unavailable
      return computeEmbeddingFromImage(image);
    } catch (e) {
      debugPrint('FaceEmbed error: $e');
      return null;
    }
  }

  /// Extracts embedding directly from an image crop (used during testing or fallback).
  List<double>? computeEmbeddingFromImage(img.Image image) {
    if (_session == null) return null;
    try {
      final resized = img.copyResize(image, width: 112, height: 112,
          interpolation: img.Interpolation.linear);
      final input = _toNCHW(resized);
      final emb = _runOnnx(input);
      if (emb.isEmpty) return null;
      return _l2Normalize(emb);
    } catch (e) {
      return null;
    }
  }

  // ── Recognise faces in a live camera frame ──────────────────────────────────
  Future<FaceMatch?> recogniseInFrame(
    img.Image fullFrame, {
    double pxMin = 0.0, double pyMin = 0.0,
    double pxMax = 1.0, double pyMax = 1.0,
  }) async {
    if (!_initialized || _knownPeople.isEmpty || _session == null) return null;
    try {
      _tempFilePath ??=
          '${(await getTemporaryDirectory()).path}/nav_face_live.jpg';
      final tempFile = File(_tempFilePath!);
      await tempFile.writeAsBytes(img.encodeJpg(fullFrame, quality: 85));

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final faces = await _detector.processImage(inputImage);
      if (faces.isEmpty) {
        debugPrint('FaceMatch: no face in frame');
        _decayPendingMatch();
        return null;
      }

      final fw = fullFrame.width.toDouble();
      final fh = fullFrame.height.toDouble();
      final candidates = faces.where((f) {
        final cx = (f.boundingBox.left + f.boundingBox.width  / 2) / fw;
        final cy = (f.boundingBox.top  + f.boundingBox.height / 2) / fh;
        return cx >= pxMin && cx <= pxMax && cy >= pyMin && cy <= pyMax;
      }).toList();

      final Face face;
      if (candidates.isEmpty) {
        face = faces.reduce((a, b) =>
            (a.boundingBox.width * a.boundingBox.height) >
            (b.boundingBox.width * b.boundingBox.height)
                ? a : b);
      } else {
        face = candidates.reduce((a, b) =>
            (a.boundingBox.width * a.boundingBox.height) >
            (b.boundingBox.width * b.boundingBox.height)
                ? a : b);
      }

      // Face-size guard (must be >= 0.8% of frame)
      final facePx = face.boundingBox.width * face.boundingBox.height;
      final imgPx  = fullFrame.width * fullFrame.height;
      final frac   = imgPx > 0 ? facePx / imgPx : 0.0;
      if (frac < 0.008) {
        debugPrint('FaceMatch: face too small (${(frac * 100).toStringAsFixed(1)}%)');
        _decayPendingMatch();
        return null;
      }

      // Direction strictly from face bounding box center
      final faceCenterX = face.boundingBox.left + (face.boundingBox.width / 2.0);
      final faceCenterXRatio = fw > 0 ? (faceCenterX / fw).clamp(0.0, 1.0) : 0.5;
      final direction = FaceMatch.calculateFaceDirection(faceCenterXRatio);

      final embedding = _computeEmbedding(fullFrame, face);
      if (embedding == null) {
        _decayPendingMatch();
        return null;
      }

      final rawMatch = _findBestMatch(
        embedding,
        faceCenterXRatio: faceCenterXRatio,
        faceBox: face.boundingBox,
      );

      FaceMatch? result;
      if (rawMatch != null) {
        if (rawMatch.name == _pendingMatchName && rawMatch.personId == _pendingMatchPersonId) {
          _pendingCount++;
        } else {
          _pendingMatchName = rawMatch.name;
          _pendingMatchPersonId = rawMatch.personId;
          _pendingCount = 1;
        }

        final isConfirmed = _pendingCount >= _confirmFrames;
        result = FaceMatch(
          personId: rawMatch.personId,
          name: rawMatch.name,
          imagePath: rawMatch.imagePath,
          confidence: rawMatch.confidence,
          faceBoundingBox: face.boundingBox,
          faceCenterXRatio: faceCenterXRatio,
          direction: direction,
          isConfirmed: isConfirmed,
          consecutiveFrames: _pendingCount,
        );

        if (isConfirmed) {
          debugPrint('FaceMatch CONFIRMED: ${rawMatch.name} '
              '(${(rawMatch.confidence * 100).toStringAsFixed(1)}%) in direction ${direction.displayName}');
        } else {
          debugPrint('FaceMatch pending: ${rawMatch.name} '
              '($_pendingCount/$_confirmFrames)');
        }
      } else {
        _decayPendingMatch();
      }
      return result;
    } catch (e) {
      debugPrint('FaceRecognise error: $e');
      return null;
    }
  }

  void _decayPendingMatch() {
    if (_pendingCount > 0) {
      _pendingCount--;
    }
    if (_pendingCount == 0) {
      _pendingMatchName = null;
      _pendingMatchPersonId = null;
    }
  }

  // ── Multi-reference scoring against ALL reference embeddings ──────────────
  // Compares live query embedding against ALL reference embeddings stored for person.
  // 1. Cosine similarity against each 512-d chunk
  // 2. Centroid similarity across all chunks
  // 3. Top-K average (K = min(3, count))
  // 4. Combined 50% centroid + 50% top-K
  double _scoreAgainstPerson(List<double> query, List<double> stored) {
    if (stored.length < _embDim) return 0.0;
    if (stored.length == _embDim) return _cosineSimilarity(query, stored);

    final count = stored.length ~/ _embDim;
    final allEmbeddings = <List<double>>[];
    final scores = <double>[];

    for (int i = 0; i < count; i++) {
      final chunk = stored.sublist(i * _embDim, (i + 1) * _embDim);
      allEmbeddings.add(chunk);
      scores.add(_cosineSimilarity(query, chunk));
    }

    final centroid = List<double>.filled(_embDim, 0.0);
    for (final emb in allEmbeddings) {
      for (int d = 0; d < _embDim; d++) {
        centroid[d] += emb[d];
      }
    }
    final centroidNormalized = _l2Normalize(centroid);
    final centroidScore = _cosineSimilarity(query, centroidNormalized);

    scores.sort((a, b) => b.compareTo(a));
    final k = count >= 3 ? 3 : (count >= 2 ? 2 : 1);
    final topKScores = scores.take(k);
    final topKAvg = topKScores.reduce((a, b) => a + b) / k;

    return (0.5 * centroidScore + 0.5 * topKAvg).clamp(0.0, 1.0);
  }

  Person? findClosestLocalMatch(List<double> embedding) {
    if (_knownPeople.isEmpty) return null;
    double bestScore = 0.0;
    Person? bestPerson;
    for (final person in _knownPeople) {
      if (person.embedding.length < _embDim) continue;
      final score = _scoreAgainstPerson(embedding, person.embedding);
      if (score > bestScore) {
        bestScore = score;
        bestPerson = person;
      }
    }
    if (bestPerson != null && bestScore >= similarityThreshold) {
      return bestPerson;
    }
    return null;
  }

  Future<FaceQualityResult?> evaluateFaceQualityFromFile(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(Uint8List.fromList(bytes));
      if (image == null) return null;
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _detector.processImage(inputImage);
      if (faces.isEmpty) return null;
      final face = faces.first;
      final faceAreaPx = face.boundingBox.width * face.boundingBox.height;
      final imageAreaPx = image.width * image.height;
      final faceSizeRatio = imageAreaPx > 0 ? faceAreaPx / imageAreaPx : 0.0;
      final brightness = FaceQualityService.estimateBrightness(image, face.boundingBox);
      final sharpness = FaceQualityService.estimateSharpness(image, face.boundingBox);
      final frontalness = FaceQualityService.estimateFrontalness(face);
      final occlusion = FaceQualityService.estimateOcclusion(face);
      return FaceQualityService().evaluateCandidate(
        detectionConfidence: face.trackingId != null ? 0.9 : 0.8,
        faceSizeRatio: faceSizeRatio,
        brightness: brightness,
        sharpness: sharpness,
        temporalStability: 0.76,
        frontalness: frontalness,
        occlusion: occlusion,
        observations: 3,
      );
    } catch (e) {
      debugPrint('Face quality evaluation failed: $e');
      return null;
    }
  }

  FaceMatch? _findBestMatch(
    List<double> embedding, {
    required double faceCenterXRatio,
    Rect? faceBox,
  }) {
    double bestScore   = 0.0;
    double secondScore = 0.0;
    Person? bestPerson;

    for (final person in _knownPeople) {
      if (person.embedding.length < _embDim) continue;
      final score = _scoreAgainstPerson(embedding, person.embedding);
      debugPrint('  vs ${person.name}: ${(score * 100).toStringAsFixed(1)}%');
      if (score > bestScore) {
        secondScore = bestScore;
        bestScore   = score;
        bestPerson  = person;
      } else if (score > secondScore) {
        secondScore = score;
      }
    }

    final effectiveSecond = _knownPeople.length == 1 ? 0.30 : secondScore;
    final margin   = bestScore - effectiveSecond;
    final okMargin = margin >= ambiguityMargin;

    if (bestScore >= similarityThreshold && okMargin && bestPerson != null) {
      return FaceMatch(
        personId: bestPerson.id,
        name: bestPerson.name,
        imagePath: bestPerson.imagePath,
        confidence: bestScore,
        faceBoundingBox: faceBox,
        faceCenterXRatio: faceCenterXRatio,
        direction: FaceMatch.calculateFaceDirection(faceCenterXRatio),
      );
    }
    debugPrint('FaceMatch: rejected — '
        'score=${bestScore.toStringAsFixed(3)} margin=${margin.toStringAsFixed(3)}');
    return null;
  }

  // ── Explicit Enrollment for 10 Reference Photos ───────────────────────────
  Future<Person?> enrollSamplePersonProfile({bool force = false}) async {
    if (!_initialized) await init();

    final existing = await DatabaseService.instance.getPersonByName('Loki');
    if (existing != null && existing.embedding.isNotEmpty && !force) {
      debugPrint('Enrollment: Loki already registered with ${existing.embedding.length ~/ _embDim} embeddings');
      await refreshKnownPeople();
      return existing;
    }

    final secureDocsDir = await getApplicationDocumentsDirectory();
    final secureDir = Directory('${secureDocsDir.path}/known_people');
    if (!secureDir.existsSync()) {
      secureDir.createSync(recursive: true);
    }

    final localImagePaths = <String>[];

    // Source 1: Check bundled assets in assets/images/loki_ref_*.jpeg (guaranteed in APK)
    for (int i = 1; i <= 10; i++) {
      try {
        final data = await rootBundle.load('assets/images/loki_ref_$i.jpeg');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        final dest = File('${secureDir.path}/loki_ref_$i.jpeg');
        await dest.writeAsBytes(bytes, flush: true);
        localImagePaths.add(dest.path);
      } catch (_) {}
    }

    // Source 2: Check local filesystem candidateDirs (for desktop dev & unit tests)
    if (localImagePaths.isEmpty) {
      final candidateDirs = [
        'person-image',
        'c:/Users/sanjay/OneDrive/Desktop/blinded-git/naveye/naveye/person-image',
        '../person-image',
        'assets/images',
      ];

      List<File> imageFiles = [];
      for (final dirPath in candidateDirs) {
        final dir = Directory(dirPath);
        if (dir.existsSync()) {
          final list = dir.listSync().whereType<File>().where((f) {
            final ext = f.path.toLowerCase();
            final name = f.uri.pathSegments.last;
            return (ext.endsWith('.jpeg') || ext.endsWith('.jpg') || ext.endsWith('.png')) &&
                (name.startsWith('WhatsApp') || name.startsWith('loki_ref_'));
          }).toList();
          if (list.isNotEmpty) {
            imageFiles = list;
            break;
          }
        }
      }

      if (imageFiles.isNotEmpty) {
        imageFiles.sort((a, b) => a.path.compareTo(b.path));
        for (int i = 0; i < imageFiles.length; i++) {
          final src = imageFiles[i];
          final dest = File('${secureDir.path}/loki_ref_${i + 1}.jpeg');
          await src.copy(dest.path);
          localImagePaths.add(dest.path);
        }
      }
    }

    // Source 3: Check person-image/ via modern AssetManifest API or explicit fallback
    if (localImagePaths.isEmpty) {
      try {
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        final assetPaths = manifest.listAssets().where((k) => k.startsWith('person-image/')).toList()..sort();
        for (int i = 0; i < assetPaths.length; i++) {
          final asset = assetPaths[i];
          final data = await rootBundle.load(asset);
          final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          final dest = File('${secureDir.path}/loki_ref_${i + 1}.jpeg');
          await dest.writeAsBytes(bytes, flush: true);
          localImagePaths.add(dest.path);
        }
      } catch (e) {
        debugPrint('AssetManifest person-image note: $e');
      }
    }

    if (localImagePaths.isEmpty) {
      debugPrint('Enrollment error: No reference images found for Loki');
      return null;
    }

    // Extract embeddings from all reference images
    final embeddings = <List<double>>[];
    for (final p in localImagePaths) {
      final emb = await extractEmbeddingFromFile(p);
      if (emb != null && emb.isNotEmpty) {
        embeddings.add(emb);
      }
    }

    if (embeddings.isEmpty) {
      debugPrint('Enrollment error: No face embeddings extracted from reference photos');
      return null;
    }

    final flatEmbedding = <double>[];
    for (final e in embeddings) {
      flatEmbedding.addAll(e);
    }

    final registrationDate = DateTime(2026, 9, 28, 10, 30);
    final primaryPath = localImagePaths.first;

    final person = Person(
      id: existing?.id,
      name: 'Loki',
      imagePath: primaryPath,
      createdAt: registrationDate,
      lastSeenAt: registrationDate,
      lastSeenLatitude: 13.0524,
      lastSeenLongitude: 80.2207,
      locationName: 'Kodambakkam, Chennai',
      referenceImages: localImagePaths,
      embedding: flatEmbedding,
      consentStatus: 'granted',
      consentTimestamp: registrationDate,
    );

    final Person saved;
    if (existing != null) {
      await DatabaseService.instance.updatePerson(person);
      saved = person;
    } else {
      saved = await DatabaseService.instance.insertPerson(person);
    }

    if (saved.id != null) {
      await DatabaseService.instance.logEncounter(
        personId: saved.id!,
        timestamp: registrationDate,
        latitude: 13.0524,
        longitude: 80.2207,
        confidence: 0.98,
        source: 'registration',
      );
    }

    await refreshKnownPeople();
    debugPrint('Enrollment: Enrolled Loki with ${embeddings.length} reference photos');
    return saved;
  }

  Future<void> deletePersonProfile(int personId) async {
    await DatabaseService.instance.deletePerson(personId);
    await refreshKnownPeople();
  }

  Future<void> resetSamplePersonProfile() async {
    final existing = await DatabaseService.instance.getPersonByName('Loki');
    if (existing?.id != null) {
      await DatabaseService.instance.deletePerson(existing!.id!);
    }
    await enrollSamplePersonProfile(force: true);
  }

  // ── Compute 512-dim MobileFaceNet embedding ─────────────────────────────────
  //
  // Pipeline:
  //   1. Crop face bounding box with 30% padding
  //   2. Eye-landmark alignment (rotate so eyes are horizontal)
  //   3. Resize to 112×112 RGB
  //   4. Normalise: (pixel / 255.0 − 0.5) / 0.5  →  [-1, 1]
  //   5. NCHW Float32List  [1, 3, 112, 112]
  //   6. ONNX inference → [1, 512]
  //   7. L2 normalise output
  List<double>? _computeEmbedding(img.Image image, Face face) {
    try {
      final box = face.boundingBox;

      // 1. Crop with generous padding
      final padW = box.width  * 0.30;
      final padH = box.height * 0.30;
      final x = (box.left   - padW).toInt().clamp(0, image.width  - 1);
      final y = (box.top    - padH).toInt().clamp(0, image.height - 1);
      final w = (box.width  + 2 * padW).toInt().clamp(1, image.width  - x);
      final h = (box.height + 2 * padH).toInt().clamp(1, image.height - y);
      var crop = img.copyCrop(image, x: x, y: y, width: w, height: h);

      // 2. Eye-alignment
      final le = face.landmarks[FaceLandmarkType.leftEye];
      final re = face.landmarks[FaceLandmarkType.rightEye];
      if (le != null && re != null) {
        final leX = le.position.x.toDouble() - x;
        final leY = le.position.y.toDouble() - y;
        final reX = re.position.x.toDouble() - x;
        final reY = re.position.y.toDouble() - y;
        final angle = atan2(reY - leY, reX - leX) * 180 / pi;
        if (angle.abs() > 1 && angle.abs() < 45) {
          crop = img.copyRotate(crop, angle: angle);
        }
      }

      // 3. Resize to 112×112 RGB (keep colour — neural net uses colour)
      final resized = img.copyResize(crop, width: 112, height: 112,
          interpolation: img.Interpolation.linear);

      // 4 + 5. Normalise + NCHW layout
      final input = _toNCHW(resized);

      // 6. ONNX inference
      final emb = _runOnnx(input);
      if (emb.isEmpty) return null;

      // 7. L2 normalise
      return _l2Normalize(emb);
    } catch (e) {
      debugPrint('FaceEmbed compute error: $e');
      return null;
    }
  }

  // ── Build NCHW Float32List for model input ──────────────────────────────────
  Float32List _toNCHW(img.Image image) {
    const S   = 112;
    final data = Float32List(3 * S * S);
    final rOff = 0 * S * S;
    final gOff = 1 * S * S;
    final bOff = 2 * S * S;
    for (int iy = 0; iy < S; iy++) {
      for (int ix = 0; ix < S; ix++) {
        final p   = image.getPixel(ix, iy);
        final idx = iy * S + ix;
        // (pixel/255 - 0.5) / 0.5  maps [0,255] → [-1, 1]
        data[rOff + idx] = (p.r.toDouble() / 255.0 - 0.5) / 0.5;
        data[gOff + idx] = (p.g.toDouble() / 255.0 - 0.5) / 0.5;
        data[bOff + idx] = (p.b.toDouble() / 255.0 - 0.5) / 0.5;
      }
    }
    return data;
  }

  // ── Run ONNX session → 512-dim embedding ────────────────────────────────────
  List<double> _runOnnx(Float32List input) {
    if (_session == null) return [];
    try {
      final tensor = OrtValueTensor.createTensorWithDataList(
          input, [1, 3, 112, 112]);
      final runOpts = OrtRunOptions();
      final outputs = _session!.run(runOpts, {_session!.inputNames.first: tensor});
      tensor.release();
      runOpts.release();

      if (outputs.isEmpty || outputs[0] == null) return [];
      final outTensor = outputs[0]!;
      final raw       = outTensor.value as List;
      outTensor.release();

      // Output shape [1, 512] → raw[0] is the 512-element list
      final batch = raw[0] as List;
      return batch.map((v) => (v as num).toDouble()).toList();
    } catch (e) {
      debugPrint('FaceNet ONNX run error: $e');
      return [];
    }
  }

  List<double> _l2Normalize(List<double> v) {
    final norm = sqrt(v.map((x) => x * x).reduce((a, b) => a + b));
    if (norm < 1e-10) return v;
    return v.map((x) => x / norm).toList();
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0, na = 0, nb = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na  += a[i] * a[i];
      nb  += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0.0;
    return dot / (sqrt(na) * sqrt(nb));
  }

  void dispose() {
    if (_initialized) {
      _detector.close();
      _session?.release();
      _session      = null;
      _initialized  = false;
    }
    _knownPeople      = [];
    _pendingMatchName = null;
    _pendingCount     = 0;
    // BUG-5 FIX: delete the cached temp JPEG so it doesn't accumulate storage.
    if (_tempFilePath != null) {
      try { File(_tempFilePath!).deleteSync(); } catch (_) {}
      _tempFilePath = null;
    }
  }
}
