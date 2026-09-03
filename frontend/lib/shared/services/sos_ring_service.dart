import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/web/web_platform.dart' as web_platform;

/// Loops an urgent alert tone + haptics until [stop] is called.
/// On web, uses the Web Audio API for a phone-like ring; elsewhere
/// falls back to system alert sounds.
class SosRingService {
  SosRingService._();
  static final SosRingService instance = SosRingService._();

  Timer? _timer;
  bool _playing = false;

  bool get isPlaying => _playing;

  void start() {
    if (_playing) return;
    _playing = true;
    _pulse();
    _timer = Timer.periodic(
      const Duration(milliseconds: 1600),
      (_) => _pulse(),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _stopWebTone();
    _playing = false;
  }

  void _pulse() {
    HapticFeedback.heavyImpact();
    if (kIsWeb) {
      _playWebTone();
    } else {
      SystemSound.play(SystemSoundType.alert);
    }
  }

  void _playWebTone() {
    try {
      web_platform.playSosWebTone();
    } catch (_) {
      SystemSound.play(SystemSoundType.alert);
    }
  }

  void _stopWebTone() {
    web_platform.stopSosWebTone();
  }
}
