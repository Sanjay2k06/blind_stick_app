import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Manages startup background music (BGM).
///
/// Section 3 of MASTER PROMPT:
/// - Calm, soft, non-aggressive, low volume (0.15–0.25, default 0.20)
/// - Completely separate audio system from navigation TTS
/// - Immediately stops/disposes when user taps Start
class StartupAudioManager {
  static const double defaultBgmVolume = 0.20;
  static const String bgmAssetPath = 'audio/sahara.mp3';

  AudioPlayer? _player;
  bool _isPlaying = false;
  bool _isDisposed = false;
  double _volume = defaultBgmVolume;

  StartupAudioManager({double volume = defaultBgmVolume}) {
    _volume = volume.clamp(0.0, 1.0);
  }

  bool get isPlaying => _isPlaying;
  double get volume => _volume;

  /// Starts playback of the startup BGM (sahara.mp3) at the configured volume.
  Future<void> startBgm({double? volume}) async {
    if (_isDisposed) return;
    if (_isPlaying) return;

    if (volume != null) {
      _volume = volume.clamp(0.0, 1.0);
    }

    try {
      _player ??= AudioPlayer();
      await _player!.setVolume(_volume);
      await _player!.setReleaseMode(ReleaseMode.stop);
      await _player!.play(AssetSource(bgmAssetPath));
      _isPlaying = true;
      debugPrint('StartupAudioManager: Sahara BGM started at volume $_volume');
    } catch (e) {
      debugPrint('StartupAudioManager: Failed to play Sahara BGM: $e');
      _isPlaying = false;
    }
  }

  /// Immediately stops playback. BGM must never overlap with speech.
  Future<void> stopBgm() async {
    _isPlaying = false;
    if (_player != null) {
      try {
        await _player!.stop();
        debugPrint('StartupAudioManager: BGM stopped');
      } catch (e) {
        debugPrint('StartupAudioManager: Error stopping BGM: $e');
      }
    }
  }

  /// Pauses playback (e.g. when app moves to background before Start).
  Future<void> pauseBgm() async {
    if (_player != null && _isPlaying) {
      try {
        await _player!.pause();
        debugPrint('StartupAudioManager: BGM paused');
      } catch (e) {
        debugPrint('StartupAudioManager: Error pausing BGM: $e');
      }
    }
  }

  /// Resumes playback (e.g. when app returns from background before Start).
  Future<void> resumeBgm() async {
    if (_player != null && _isPlaying && !_isDisposed) {
      try {
        await _player!.resume();
        debugPrint('StartupAudioManager: BGM resumed');
      } catch (e) {
        debugPrint('StartupAudioManager: Error resuming BGM: $e');
      }
    }
  }

  /// Releases resources.
  Future<void> dispose() async {
    _isDisposed = true;
    _isPlaying = false;
    if (_player != null) {
      try {
        await _player!.stop();
        await _player!.dispose();
      } catch (e) {
        debugPrint('StartupAudioManager: Error disposing BGM player: $e');
      }
      _player = null;
    }
  }
}
