/// Web implementation of the browser-only platform facade.
/// Only compiled on web (see [web_platform.dart]).
import 'package:web/web.dart' as web;

void openWindow(String url, [String target = '_blank']) {
  web.window.open(url, target);
}

String? localStorageGet(String key) => web.window.localStorage.getItem(key);

void localStorageSet(String key, String value) =>
    web.window.localStorage.setItem(key, value);

void localStorageRemove(String key) => web.window.localStorage.removeItem(key);

web.AudioContext? _audioContext;
web.OscillatorNode? _oscillator;

void playSosWebTone() {
  _audioContext ??= web.AudioContext();
  stopSosWebTone();
  final ctx = _audioContext!;
  final osc = ctx.createOscillator();
  final gain = ctx.createGain();
  osc.type = 'sine';
  osc.frequency.value = 880;
  gain.gain.value = 0.22;
  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.start();
  _oscillator = osc;

  // Two-tone ring pattern.
  Future.delayed(const Duration(milliseconds: 200), () {
    if (_oscillator == osc) osc.frequency.value = 660;
  });
  Future.delayed(const Duration(milliseconds: 500), () {
    if (_oscillator == osc) {
      osc.stop();
      if (_oscillator == osc) _oscillator = null;
    }
  });
}

void stopSosWebTone() {
  try {
    _oscillator?.stop();
  } catch (_) {}
  _oscillator = null;
}
