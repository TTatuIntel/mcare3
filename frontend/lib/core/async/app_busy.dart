import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Global count of in-flight network operations.
///
/// [ApiClient] wraps every request in [track], so anything that talks to the
/// Laravel API contributes automatically. The UI layer listens through
/// `AppBusyBar` and only surfaces an indicator once a request has outlived
/// `AppMotion.loaderDelay` — fast calls stay invisible.
///
/// Lives in `core/` (foundation only, no widgets) so the API layer can depend
/// on it without importing the widget tree.
class AppBusy extends ChangeNotifier {
  AppBusy._();

  static final AppBusy instance = AppBusy._();

  int _count = 0;

  /// Number of operations currently in flight.
  int get count => _count;

  bool get isBusy => _count > 0;

  /// Marks one operation as started. Always pair with [end].
  void begin() {
    _count++;
    if (_count == 1) _safeNotify();
  }

  /// Marks one operation as finished.
  void end() {
    if (_count == 0) return;
    _count--;
    if (_count == 0) _safeNotify();
  }

  /// Runs [operation] while counted as busy. Returns the original future's
  /// result and rethrows its error untouched — purely observational.
  Future<T> track<T>(Future<T> operation) {
    begin();
    return operation.whenComplete(end);
  }

  /// Resets the counter. Test/teardown only.
  @visibleForTesting
  void reset() {
    final wasBusy = _count > 0;
    _count = 0;
    if (wasBusy) _safeNotify();
  }

  /// A request can start during a build (a view kicking off a fetch from
  /// `initState`/`build`). Notifying listeners in that phase would trip
  /// "markNeedsBuild called during build", so defer to the next microtask
  /// when we are mid-frame.
  void _safeNotify() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    final midFrame = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.transientCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (midFrame) {
      scheduleMicrotask(() {
        if (hasListeners) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }
}
