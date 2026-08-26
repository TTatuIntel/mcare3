import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Tracks in-flight network work and, crucially, what *kind* it is.
///
/// Three categories, because they deserve three different UI treatments:
///
/// * **Background** — [SessionPoller]'s 30s sweep and any other unattended
///   refresh. Shows nothing at all. The user did not ask for it, so it must
///   never interrupt them.
/// * **Reads** — a GET the user triggered by opening a screen. Drives the slim
///   top bar only; the screen itself shows skeletons in the content area.
/// * **Mutations** — POST/PUT/PATCH/DELETE, i.e. the user pressed a button and
///   is waiting on the result. Drives the on-screen mCare indicator, because
///   this is the case where the app owes them a visible "working on it".
///
/// Lives in `core/` (foundation only, no widgets) so the API layer can depend
/// on it without importing the widget tree.
class AppBusy extends ChangeNotifier {
  AppBusy._();

  static final AppBusy instance = AppBusy._();

  /// Zone marker set by [runBackground].
  static const Object _backgroundKey = #mcareBackgroundWork;

  int _reads = 0;
  int _mutations = 0;

  /// Any attended request is in flight — drives the top bar.
  bool get isBusy => _reads > 0 || _mutations > 0;

  /// A user-initiated write is in flight — drives the on-screen indicator.
  bool get isMutating => _mutations > 0;

  int get readCount => _reads;
  int get mutationCount => _mutations;

  /// True while running inside [runBackground].
  static bool get isBackgroundWork => Zone.current[_backgroundKey] == true;

  /// Runs [body] as unattended work: nothing it does will surface in the UI.
  ///
  /// Zone-scoped, so every request the body awaits inherits the marking no
  /// matter how deep the call stack goes.
  static Future<T> runBackground<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_backgroundKey: true});

  /// Marks one operation as started. Always pair with [end].
  void begin({bool mutation = false}) {
    if (isBackgroundWork) return;
    final wasBusy = isBusy;
    final wasMutating = isMutating;
    if (mutation) {
      _mutations++;
    } else {
      _reads++;
    }
    if (wasBusy != isBusy || wasMutating != isMutating) _safeNotify();
  }

  /// Marks one operation as finished.
  void end({bool mutation = false}) {
    if (isBackgroundWork) return;
    if (mutation ? _mutations == 0 : _reads == 0) return;
    final wasBusy = isBusy;
    final wasMutating = isMutating;
    if (mutation) {
      _mutations--;
    } else {
      _reads--;
    }
    if (wasBusy != isBusy || wasMutating != isMutating) _safeNotify();
  }

  /// Runs [operation] while counted. Returns its result and rethrows its error
  /// untouched — purely observational.
  Future<T> track<T>(Future<T> operation, {bool mutation = false}) {
    begin(mutation: mutation);
    return operation.whenComplete(() => end(mutation: mutation));
  }

  /// Resets the counters. Test/teardown only.
  @visibleForTesting
  void reset() {
    final wasBusy = isBusy;
    _reads = 0;
    _mutations = 0;
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
