import 'dart:async';

import 'package:flutter/widgets.dart';

import 'realtime_channel.dart';

/// Adds domain-filtered, overlap-safe real-time refreshes to API-backed
/// screens whose data is not held in the role session stores.
mixin RealtimeRefreshMixin<T extends StatefulWidget> on State<T> {
  StreamSubscription<Set<String>>? _realtimeRefreshSubscription;
  bool _realtimeRefreshRunning = false;
  bool _realtimeRefreshPending = false;

  void watchRealtime(Set<String> domains, Future<void> Function() refresh) {
    _realtimeRefreshSubscription?.cancel();
    _realtimeRefreshSubscription = RealtimeChannel.instance.changes.listen((
      changed,
    ) {
      if (!changed.contains('*') && !changed.any(domains.contains)) return;
      unawaited(_runRealtimeRefresh(refresh));
    });
  }

  Future<void> _runRealtimeRefresh(Future<void> Function() refresh) async {
    if (!mounted) return;
    if (_realtimeRefreshRunning) {
      _realtimeRefreshPending = true;
      return;
    }

    _realtimeRefreshRunning = true;
    try {
      do {
        _realtimeRefreshPending = false;
        try {
          await refresh();
        } catch (_) {
          // A live refresh is background reconciliation. The page keeps its
          // last successful data and the next event/pulse/resume retries.
        }
      } while (mounted && _realtimeRefreshPending);
    } finally {
      _realtimeRefreshRunning = false;
    }
  }

  @override
  void dispose() {
    _realtimeRefreshSubscription?.cancel();
    super.dispose();
  }
}
