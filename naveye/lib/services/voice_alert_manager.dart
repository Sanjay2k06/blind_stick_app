import 'dart:async';
import 'package:flutter/foundation.dart';
import 'navigation_decision_engine.dart';
import 'tts_service.dart';

/// Voice state machine lifecycle states:
/// DETECTED -> STABILIZING -> STABLE -> ANNOUNCED -> MONITORING SILENTLY -> STATE CHANGED
enum VoiceLifecycleState {
  detected,
  stabilizing,
  stable,
  announced,
  monitoringSilently,
  stateChanged;

  String get displayName {
    switch (this) {
      case VoiceLifecycleState.detected:
        return 'DETECTED';
      case VoiceLifecycleState.stabilizing:
        return 'STABILIZING';
      case VoiceLifecycleState.stable:
        return 'STABLE';
      case VoiceLifecycleState.announced:
        return 'ANNOUNCED';
      case VoiceLifecycleState.monitoringSilently:
        return 'MONITORING SILENTLY';
      case VoiceLifecycleState.stateChanged:
        return 'STATE CHANGED';
    }
  }
}

/// Snapshot of the current navigation and alert state for developer debug overlay.
class VoiceDebugInfo {
  final String objectName;
  final double confidence;
  final String position;
  final String proximity;
  final String announcement;
  final String voiceState;
  final bool cooldownActive;
  final int cooldownRemainingMs;
  final String priority;
  final DateTime updatedAt;

  const VoiceDebugInfo({
    required this.objectName,
    required this.confidence,
    required this.position,
    required this.proximity,
    required this.announcement,
    required this.voiceState,
    required this.cooldownActive,
    required this.cooldownRemainingMs,
    required this.priority,
    required this.updatedAt,
  });

  static VoiceDebugInfo initial() => VoiceDebugInfo(
    objectName: 'None',
    confidence: 0.0,
    position: 'IDLE',
    proximity: 'NONE',
    announcement: 'None',
    voiceState: VoiceLifecycleState.monitoringSilently.displayName,
    cooldownActive: false,
    cooldownRemainingMs: 0,
    priority: 'IDLE',
    updatedAt: DateTime.now(),
  );
}

/// Maintained state for every detected object:
/// - object class (rawLabel)
/// - direction
/// - tracking identity (trackingId)
/// - last announced state (lastAnnouncedDirection)
/// - last announcement time (lastAnnouncedTime)
class ObjectVoiceRecord {
  final int trackingId;
  final String rawLabel;
  final String label;
  ObjectDirection currentDirection;
  ObjectDirection? lastAnnouncedDirection;
  DateTime? lastAnnouncedTime;
  VoiceLifecycleState voiceState;
  DateTime lastSeen;

  ObjectVoiceRecord({
    required this.trackingId,
    required this.rawLabel,
    required this.label,
    required this.currentDirection,
    this.lastAnnouncedDirection,
    this.lastAnnouncedTime,
    this.voiceState = VoiceLifecycleState.detected,
    required this.lastSeen,
  });

  bool isExpired(DateTime now, {int gracePeriodMs = 2000}) {
    return now.difference(lastSeen).inMilliseconds > gracePeriodMs;
  }
}

/// Centralized Voice Alert Manager.
/// Enforces:
/// 1. Exactly ONE active TTS output at a time (never overlapping).
/// 2. Zero voice queue (no accumulation of backlog messages).
/// 3. Navigation Voice State Machine with MONITORING SILENTLY:
///    - Continuous detection running constantly without stopping camera/ML.
///    - Speaks ONLY when the navigation instruction changes (Action Guidance).
///    - After speaking, continues detecting silently (MONITORING SILENTLY).
/// 4. 2-second grace period for momentary object disappearances.
/// 5. Strict priority preemption (1. STOP > 2. GO LEFT / GO RIGHT > 3. Informational).
class VoiceAlertManager {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final VoiceAlertManager _instance = VoiceAlertManager._internal();
  factory VoiceAlertManager({TtsService? tts}) {
    if (tts != null) {
      _instance._tts = tts;
    }
    return _instance;
  }
  VoiceAlertManager._internal();

  TtsService _tts = TtsService();

  // Object tracking states with grace period
  final Map<int, ObjectVoiceRecord> _recordsByTrackId = {};
  final Map<String, ObjectVoiceRecord> _recordsByClass = {};

  bool _isPaused = false;
  bool get isPaused => _isPaused;

  /// Immediately pauses navigation and obstacle voice alerts.
  void pause() {
    _isPaused = true;
    _currentSpeakingPriority = null;
    _tts.stop();
  }

  /// Resumes navigation and obstacle voice alerts.
  void resume() {
    _isPaused = false;
  }

  // Global Navigation State Memory
  NavigationAction? _lastAnnouncedAction;
  String? _lastAnnouncedSpokenText;
  AlertPriority? _currentSpeakingPriority;
  DateTime? _lastSpeechTime;
  String? _activeFocusKey;

  /// Configurable heartbeat interval for continuous clear-path confirmation (Section 13).
  int clearPathReminderIntervalMs = 10000;
  DateTime? _lastClearPathHeartbeat;

  // Observable debug info for developer UI
  VoiceDebugInfo _debugInfo = VoiceDebugInfo.initial();
  final ValueNotifier<VoiceDebugInfo> debugNotifier = ValueNotifier<VoiceDebugInfo>(VoiceDebugInfo.initial());

  VoiceDebugInfo get currentDebugInfo => _debugInfo;

  bool _isTtsActive(DateTime now) {
    if (!_tts.isSpeaking) return false;
    // Auto-clear speech state after 1.8s watchdog so subsequent announcements are never blocked
    if (_lastSpeechTime != null && now.difference(_lastSpeechTime!).inMilliseconds > 1800) {
      return false;
    }
    return true;
  }

  /// Submits a navigation alert to the centralized manager.
  /// Strictly enforces:
  /// - Only ONE voice at a time.
  /// - Continuous detection, zero voice repetition for unchanged navigation states (MONITORING SILENTLY).
  /// - Voice triggered ONLY on meaningful navigation state changes (e.g. Go left -> Go right -> Stop).
  /// - Priority preemption: STOP immediately preempts GO LEFT or GO RIGHT or CLEAR PATH.
  /// - Continuous clear-path periodic heartbeat (8-12 seconds).
  Future<void> processAlert(NavigationAlert? alert, {bool isTamil = true, DateTime? timestamp}) async {
    if (_isPaused) return;
    final now = timestamp ?? DateTime.now();

    // 1. Clean up stale records genuinely gone for > 2000 ms grace period (preserve active alert)
    _recordsByTrackId.removeWhere((id, r) => id != alert?.trackingId && r.isExpired(now, gracePeriodMs: 2000));
    _recordsByClass.removeWhere((label, r) => label != alert?.rawLabel && r.isExpired(now, gracePeriodMs: 2000));

    if (alert == null) {
      return;
    }

    // Always prioritize Tamil navigation voice (Section 9: Zero English navigation voice)
    final phrase = alert.spokenTextTa.isNotEmpty ? alert.spokenTextTa : alert.spokenTextEn;
    final bool isEmergencyStop = alert.priority == AlertPriority.criticalObstacle || alert.action == NavigationAction.stop;
    final bool isClearState = alert.navState == NavigationState.clear || alert.action == NavigationAction.clear;

    // ── 2. Continuous Clear-Path Guidance & Heartbeat (Sections 2 & 13) ──
    if (isClearState) {
      final bool isFirstClear = _lastAnnouncedAction != NavigationAction.clear;
      final bool isHeartbeatDue = _lastClearPathHeartbeat != null &&
          now.difference(_lastClearPathHeartbeat!).inMilliseconds >= clearPathReminderIntervalMs;

      if (!isFirstClear && !isHeartbeatDue) {
        // Path remains clear: silent monitoring, zero repetitive speech
        _updateDebugSnapshot(
          objectName: 'None',
          confidence: alert.confidence,
          position: 'CLEAR',
          proximity: 'CLEAR',
          announcement: phrase,
          voiceState: VoiceLifecycleState.monitoringSilently.displayName,
          cooldownActive: true,
          cooldownRemainingMs: 0,
          priority: alert.priority.name,
          now: now,
        );
        return;
      }

      // If TTS is already speaking something, do not disrupt
      if (_isTtsActive(now)) {
        return;
      }

      _currentSpeakingPriority = AlertPriority.clearPath;
      _activeFocusKey = 'clear';
      _lastAnnouncedAction = NavigationAction.clear;
      _lastAnnouncedSpokenText = phrase;
      _lastClearPathHeartbeat = now;

      _updateDebugSnapshot(
        objectName: 'None',
        confidence: alert.confidence,
        position: 'CLEAR',
        proximity: 'CLEAR',
        announcement: phrase,
        voiceState: VoiceLifecycleState.announced.displayName,
        cooldownActive: false,
        cooldownRemainingMs: 0,
        priority: alert.priority.name,
        now: now,
      );

      _lastSpeechTime = now;
      await _executeSpeech(alert, phrase, now);
      return;
    }

    // ── 3. Obstacle Present: Reset Clear-Path Heartbeat ──
    _lastClearPathHeartbeat = null;

    // Retrieve or initialize ObjectVoiceRecord for this object
    var record = _recordsByTrackId[alert.trackingId] ?? _recordsByClass[alert.rawLabel];

    if (record == null) {
      record = ObjectVoiceRecord(
        trackingId: alert.trackingId,
        rawLabel: alert.rawLabel,
        label: alert.label,
        currentDirection: alert.direction,
        voiceState: VoiceLifecycleState.stable,
        lastSeen: now,
      );
      _recordsByTrackId[alert.trackingId] = record;
      _recordsByClass[alert.rawLabel] = record;
    } else {
      record.lastSeen = now;
      record.currentDirection = alert.direction;
    }

    // ── 4. Meaningful Navigation State Change Check ──
    final bool isActionChange = _lastAnnouncedAction == null || _lastAnnouncedAction != alert.action;
    final bool isPhraseChange = _lastAnnouncedSpokenText == null || _lastAnnouncedSpokenText != phrase;
    final bool isStateChange = isActionChange || isPhraseChange;

    // ── 5. Duplicate Suppression / MONITORING SILENTLY rule ──
    // If navigation state remains unchanged:
    // Speak once for that stable state. Do NOT speak every camera frame.
    if (!isStateChange) {
      record.voiceState = VoiceLifecycleState.monitoringSilently;
      _updateDebugSnapshot(
        objectName: alert.label,
        confidence: alert.confidence,
        position: alert.direction.displayName,
        proximity: alert.proximity.displayName,
        announcement: phrase,
        voiceState: VoiceLifecycleState.monitoringSilently.displayName,
        cooldownActive: true,
        cooldownRemainingMs: 0,
        priority: alert.priority.name,
        now: now,
      );
      return; // SILENCE! Keep detection running constantly without repeating voice.
    }

    // ── 6. Multi-object scene focus lock ──
    if (_activeFocusKey != null && _activeFocusKey != alert.rawLabel && _activeFocusKey != 'clear' && !isEmergencyStop) {
      final activeRecord = _recordsByClass[_activeFocusKey];
      if (activeRecord != null && !activeRecord.isExpired(now)) {
        final activePriority = _currentSpeakingPriority ?? AlertPriority.normalObject;
        if (!alert.priority.isStrictlyHigher(activePriority)) {
          return; // Stay focused on primary instruction silently.
        }
      }
    }

    // ── 7. Refresh speaking priority if TTS has finished ──
    final bool ttsActive = _isTtsActive(now);
    if (!ttsActive) {
      _currentSpeakingPriority = null;
    }

    // ── 8. Priority Preemption & Single Voice Output ──
    // Priority: 1. STOP > 2. GO LEFT / GO RIGHT > 3. Informational > 4. CLEAR PATH
    if (ttsActive) {
      final activePriority = _currentSpeakingPriority ?? AlertPriority.normalObject;
      if (alert.priority.isStrictlyHigher(activePriority)) {
        // Critical event (e.g. STOP or obstacle interrupting CLEAR PATH) immediately preempts
        await _tts.stop();
        _currentSpeakingPriority = alert.priority;
        _activeFocusKey = alert.rawLabel;
        _lastAnnouncedAction = alert.action;
        _lastAnnouncedSpokenText = phrase;

        record.lastAnnouncedDirection = alert.direction;
        record.lastAnnouncedTime = now;
        record.voiceState = VoiceLifecycleState.monitoringSilently;

        _updateDebugSnapshot(
          objectName: alert.label,
          confidence: alert.confidence,
          position: alert.direction.displayName,
          proximity: alert.proximity.displayName,
          announcement: phrase,
          voiceState: VoiceLifecycleState.announced.displayName,
          cooldownActive: false,
          cooldownRemainingMs: 0,
          priority: alert.priority.name,
          now: now,
        );

        _lastSpeechTime = now;
        await _executeSpeech(alert, phrase, now);
        return;
      } else {
        // Equal or lower priority while another message is speaking:
        // NEVER QUEUE! Discard frame.
        return;
      }
    }

    // ── 9. Speak the Announcement! ──
    _currentSpeakingPriority = alert.priority;
    _activeFocusKey = alert.rawLabel;
    _lastAnnouncedAction = alert.action;
    _lastAnnouncedSpokenText = phrase;

    record.lastAnnouncedDirection = alert.direction;
    record.lastAnnouncedTime = now;
    record.voiceState = VoiceLifecycleState.monitoringSilently;

    _updateDebugSnapshot(
      objectName: alert.label,
      confidence: alert.confidence,
      position: alert.direction.displayName,
      proximity: alert.proximity.displayName,
      announcement: phrase,
      voiceState: VoiceLifecycleState.announced.displayName,
      cooldownActive: false,
      cooldownRemainingMs: 0,
      priority: alert.priority.name,
      now: now,
    );

    _lastSpeechTime = now;
    await _executeSpeech(alert, phrase, now);
  }

  Future<void> _executeSpeech(NavigationAlert alert, String phrase, DateTime now) async {
    try {
      await _tts.speakNow(phrase);
    } catch (e) {
      debugPrint('VoiceAlertManager speech error: $e');
    }
  }

  /// No-op stub maintained for compatibility — queues are eliminated to prevent backlog.
  Future<void> checkPendingQueue({bool isTamil = false}) async {}

  void _updateDebugSnapshot({
    required String objectName,
    required double confidence,
    required String position,
    required String proximity,
    required String announcement,
    required String voiceState,
    required bool cooldownActive,
    required int cooldownRemainingMs,
    required String priority,
    required DateTime now,
  }) {
    _debugInfo = VoiceDebugInfo(
      objectName: objectName,
      confidence: confidence,
      position: position,
      proximity: proximity,
      announcement: announcement,
      voiceState: voiceState,
      cooldownActive: cooldownActive,
      cooldownRemainingMs: cooldownRemainingMs,
      priority: priority,
      updatedAt: now,
    );
    debugNotifier.value = _debugInfo;
  }

  /// Announces navigation startup in Tamil (Section 16):
  /// "வழிகாட்டுதல் தொடங்கப்பட்டது. முன்னால் செல்லலாம்."
  Future<void> speakStartup() async {
    _currentSpeakingPriority = AlertPriority.obstacleAhead;
    await _tts.stop();
    await _tts.speakNow('வழிகாட்டுதல் தொடங்கப்பட்டது. முன்னால் செல்லலாம்.');
  }

  /// Announces navigation shutdown in Tamil (Section 16):
  /// "வழிகாட்டுதல் நிறுத்தப்பட்டது."
  Future<void> speakStop() async {
    _currentSpeakingPriority = AlertPriority.obstacleAhead;
    await _tts.stop();
    await _tts.speakNow('வழிகாட்டுதல் நிறுத்தப்பட்டது.');
  }

  /// Speaks an explicit directive (e.g. path guidance, warnings) with serialization.
  Future<void> speakDirective(String phrase, {bool isEmergency = false}) async {
    if (_isPaused) return;
    if (isEmergency) {
      _currentSpeakingPriority = AlertPriority.criticalObstacle;
      await _tts.stop();
      await _tts.speakNow(phrase);
    } else {
      if (!_tts.isSpeaking) {
        _currentSpeakingPriority = AlertPriority.normalObject;
        await _tts.speakNow(phrase);
      }
    }
  }

  /// Halts current speech.
  Future<void> stop() async {
    _currentSpeakingPriority = null;
    await _tts.stop();
  }

  /// Clears history and resets state.
  void reset() {
    _isPaused = false;
    _currentSpeakingPriority = null;
    _activeFocusKey = null;
    _lastSpeechTime = null;
    _lastAnnouncedAction = null;
    _lastAnnouncedSpokenText = null;
    _lastClearPathHeartbeat = null;
    _recordsByTrackId.clear();
    _recordsByClass.clear();
    _tts.stop();
    _debugInfo = VoiceDebugInfo.initial();
    debugNotifier.value = _debugInfo;
  }
}
