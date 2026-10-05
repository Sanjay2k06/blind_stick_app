import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../services/database_service.dart';
import '../../services/face_recognition_service.dart';
import '../../services/tts_service.dart';
import '../../models/person_model.dart';

class PeopleListScreen extends StatefulWidget {
  const PeopleListScreen({super.key});
  @override
  State<PeopleListScreen> createState() => _PeopleListScreenState();
}

class _PeopleListScreenState extends State<PeopleListScreen> {
  List<Person> _persons = [];
  // Pre-computed file existence so we don't call existsSync() inside build
  final Map<int, bool> _imageExists = {};
  bool _loading = true;
  final TtsService _tts = TtsService();

  @override
  void initState() {
    super.initState();
    _tts.init();
    _loadPersons();
  }

  Future<void> _loadPersons() async {
    final persons = await DatabaseService.instance.getAllPersons();
    // Pre-compute image file existence off the main thread build path
    final exists = <int, bool>{};
    for (final p in persons) {
      if (p.id != null && p.imagePath.isNotEmpty) {
        exists[p.id!] = File(p.imagePath).existsSync();
      }
    }
    _imageExists
      ..clear()
      ..addAll(exists);
    if (!mounted) return;
    setState(() { _persons = persons; _loading = false; });

    // Announce how many people are saved
    if (persons.isEmpty) {
      await _tts.speak('இன்னும் நபர்கள் சேர்க்கப்படவில்லை. புதிய நபரைச் சேர்க்க பொத்தானை அழுத்தவும்.');
    } else {
      final names = persons.map((p) => p.name).join(', ');
      await _tts.speak('${persons.length} நபர்கள் பதிவு செய்யப்பட்டுள்ளனர்: $names');
    }
  }

  Future<void> _deletePerson(int id, String name) async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Person', style: TextStyle(color: AppColors.white)),
        content: Text('Remove $name from Veyra?\nVeyra will no longer recognise them.',
          style: const TextStyle(color: AppColors.greyLight, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _loading = true);
      await FaceRecognitionService.instance.deletePersonProfile(id);
      if (!mounted) return;
      await _tts.speakNow('$name நீக்கப்பட்டது.');
      await _loadPersons();
    }
  }

  Future<void> _resetOrEnrollSample() async {
    setState(() => _loading = true);
    await _tts.speakNow('10 மாதிரி புகைப்படங்களுடன் சுயவிவரம் பதிவு செய்யப்படுகிறது.');
    await FaceRecognitionService.instance.resetSamplePersonProfile();
    if (!mounted) return;
    await _loadPersons();
    await _tts.speakNow('லோகி வெற்றிகரமாகப் பதிவு செய்யப்பட்டார்.');
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Known People${_persons.isNotEmpty ? " (${_persons.length})" : ""}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.greyLight),
            tooltip: 'Enroll / Reset Sample Profile',
            onPressed: _resetOrEnrollSample,
          ),
          IconButton(
            icon: const Icon(Icons.person_add, color: AppColors.yellow),
            tooltip: 'Add Person',
            onPressed: () async {
              await Navigator.pushNamed(context, AppRoutes.peopleCapture);
              _loadPersons();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.yellow))
          : _persons.isEmpty
              ? _buildEmpty()
              : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.people_outline, color: AppColors.grey, size: 72),
        const SizedBox(height: 20),
        const Text('No people saved yet',
          style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text(
          'Add people so Veyra can recognise\nand announce their name.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.grey, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: _resetOrEnrollSample,
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Enroll Sample Profile (Loki)', style: TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.yellow, foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            await Navigator.pushNamed(context, AppRoutes.peopleCapture);
            _loadPersons();
          },
          icon: const Icon(Icons.person_add, size: 18, color: AppColors.white),
          label: const Text('Capture New Person', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.white)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.grey),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ]),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _persons.length,
      itemBuilder: (_, i) {
        final p = _persons[i];
        final refCount = p.referenceImages.isNotEmpty
            ? p.referenceImages.length
            : (p.embedding.length ~/ 512);
        final locText = p.locationName != null && p.locationName!.isNotEmpty
            ? ' • ${p.locationName}'
            : '';
        final timeStr = '${p.createdAt.hour.toString().padLeft(2, '0')}:${p.createdAt.minute.toString().padLeft(2, '0')}';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            onTap: () {
              final locSpoken = p.locationName != null && p.locationName!.isNotEmpty
                  ? ', இடம் ${p.locationName}'
                  : '';
              _tts.speakNow('${p.name}, பதிவு செய்யப்பட்டவர்$locSpoken. $refCount புகைப்படங்கள் உள்ளன.');
            },
            leading: Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.greyDark, width: 1.5),
              ),
              child: ClipOval(
                child: p.imagePath.isNotEmpty && (_imageExists[p.id] ?? false)
                    ? Image.file(File(p.imagePath), fit: BoxFit.cover, width: 52, height: 52)
                    : Center(
                        child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: AppColors.yellow, fontSize: 22, fontWeight: FontWeight.w800)),
                      ),
              ),
            ),
            title: Text(p.name,
              style: const TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Registered ${p.createdAt.day} ${_month(p.createdAt.month)} ${p.createdAt.year}, $timeStr$locText',
                style: const TextStyle(color: AppColors.grey, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Row(children: [
                if (p.embedding.isNotEmpty) ...[
                  const Text('Face recognised ✓',
                    style: TextStyle(color: AppColors.green, fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text('($refCount photos)',
                    style: const TextStyle(color: AppColors.greyLight, fontSize: 11)),
                ] else
                  const Text('Face not yet processed',
                    style: TextStyle(color: AppColors.grey, fontSize: 11)),
              ]),
            ]),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 22),
              onPressed: p.id == null ? null : () => _deletePerson(p.id!, p.name),
            ),
          ),
        );
      },
    );
  }

  String _month(int m) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ][m];
}

