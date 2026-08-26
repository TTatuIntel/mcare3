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
  final List<String?> _blockingOperations = <String?>[];

  /// Any attended request is in flight — drives the top bar.
  bool get isBusy => _reads > 0 || _mutations > 0 || isBlocking;

  /// A user-initiated write is in flight — drives the on-screen indicator.
  bool get isMutating => _mutations > 0;

  /// Critical work that temporarily requires the whole experience to wait.
  bool get isBlocking => _blockingOperations.isNotEmpty;

  /// The newest meaningful description wins when critical work is nested.
  String? get blockingMessage {
    for (var i = _blockingOperations.length - 1; i >= 0; i--) {
      final message = _blockingOperations[i];
      if (message != null && message.trim().isNotEmpty) return message;
    }
    return null;
  }

  int get readCount => _reads;
  int get mutationCount => _mutations;
  int get blockingCount => _blockingOperations.length;

  /// True while running inside [runBackground].
  static bool get isBackgroundWork => Zone.current[_backgroundKey] == true;

  /// Runs [body] as unattended work: nothing it does will surface in the UI.
  ///
  /// Zone-scoped, so every request the body awaits inherits the marking no
  /// matter how deep the call stack goes.
  static Future<T> runBackground<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_backgroundKey: true});

  /// Marks one operation as started. Always pair with [end].
  void begin({bool mutation = false, bool blocking = false, String? message}) {
    if (isBackgroundWork) return;
    final wasBusy = isBusy;
    final wasMutating = isMutating;
    final wasBlocking = isBlocking;
    final previousMessage = blockingMessage;
    if (mutation) {
      _mutations++;
    } else {
      _reads++;
    }
    if (blocking) _blockingOperations.add(message);
    if (wasBusy != isBusy ||
        wasMutating != isMutating ||
        wasBlocking != isBlocking ||
        previousMessage != blockingMessage) {
      _safeNotify();
    }
  }

  /// Marks one operation as finished.
  void end({bool mutation = false, bool blocking = false}) {
    if (isBackgroundWork) return;
    final wasBusy = isBusy;
    final wasMutating = isMutating;
    final wasBlocking = isBlocking;
    final previousMessage = blockingMessage;
    if (mutation && _mutations > 0) {
      _mutations--;
    } else if (!mutation && _reads > 0) {
      _reads--;
    }
    if (blocking && _blockingOperations.isNotEmpty) {
      _blockingOperations.removeLast();
    }
    if (wasBusy != isBusy ||
        wasMutating != isMutating ||
        wasBlocking != isBlocking ||
        previousMessage != blockingMessage) {
      _safeNotify();
    }
  }

  /// Runs [operation] while counted. Returns its result and rethrows its error
  /// untouched — purely observational.
  Future<T> track<T>(
    Future<T> operation, {
    bool mutation = false,
    bool blocking = false,
    String? message,
  }) {
    begin(mutation: mutation, blocking: blocking, message: message);
    return operation.whenComplete(
      () => end(mutation: mutation, blocking: blocking),
    );
  }

  /// Starts the loading state before [operation] is invoked and releases it on
  /// every exit, including synchronous throws and failed futures.
  Future<T> run<T>(
    Future<T> Function() operation, {
    bool mutation = false,
    bool blocking = false,
    String? message,
  }) async {
    begin(mutation: mutation, blocking: blocking, message: message);
    try {
      return await operation();
    } finally {
      end(mutation: mutation, blocking: blocking);
    }
  }

  /// Resets the counters. Test/teardown only.
  @visibleForTesting
  void reset() {
    final wasBusy = isBusy;
    _reads = 0;
    _mutations = 0;
    _blockingOperations.clear();
    if (wasBusy) _safeNotify();
  }

  /// A request can start during a build (a view kicking off a fetch from
  /// `initState`/`build`). Notifying listeners in that phase would trip
  /// "markNeedsBuild called during build", so defer to the next microtask
  /// when we are mid-frame.
  void _safeNotify() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    final midFrame =
        phase == SchedulerPhase.persistentCallbacks ||
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
