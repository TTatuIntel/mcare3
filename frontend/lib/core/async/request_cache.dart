import 'dart:async';

import 'package:flutter/foundation.dart';

/// In-memory response cache with in-flight de-duplication.
///
/// Two separate wins, both aimed at making a screen appear instantly:
///
/// * **De-duplication** — when several widgets ask for the same endpoint in
///   the same frame (a dashboard and its header both wanting the patient
///   list), only one HTTP request goes out and everyone awaits it.
/// * **TTL cache** — a repeat read inside the entry's time-to-live resolves
///   from memory with no network round trip, so navigating back to a screen
///   paints immediately instead of showing a loader again.
///
/// Deliberately opt-in per call. Clinical readings must not be served from a
/// stale cache without a considered TTL, so nothing is cached unless the
/// caller asks for it.
class RequestCache {
  RequestCache._();

  static final RequestCache instance = RequestCache._();

  final Map<String, _Entry> _entries = {};
  final Map<String, Future<dynamic>> _inFlight = {};

  /// Returns a cached value when one is live, joins an identical request that
  /// is already running, or performs [fetch] and caches its result.
  ///
  /// A failure is never cached — the next call retries.
  Future<T> read<T>(
    String key,
    Future<T> Function() fetch, {
    Duration ttl = const Duration(seconds: 30),
    bool forceRefresh = false,
  }) {
    if (!forceRefresh) {
      final entry = _entries[key];
      if (entry != null && !entry.isExpired) {
        return Future<T>.value(entry.value as T);
      }
      final pending = _inFlight[key];
      if (pending != null) return pending.then((v) => v as T);
    }

    final future = fetch().then((value) {
      _entries[key] = _Entry(value, DateTime.now().add(ttl));
      return value;
    }).whenComplete(() {
      _inFlight.remove(key);
    });

    _inFlight[key] = future;
    return future;
  }

  /// Last cached value for [key], or null when absent or expired.
  T? peek<T>(String key) {
    final entry = _entries[key];
    if (entry == null || entry.isExpired) return null;
    return entry.value as T?;
  }

  /// Drops one entry. Call after a write that invalidates it.
  void invalidate(String key) => _entries.remove(key);

  /// Drops every entry whose key starts with [prefix].
  void invalidatePrefix(String prefix) =>
      _entries.removeWhere((k, _) => k.startsWith(prefix));

  /// Drops everything. Wired to logout so one user's data can never be served
  /// to the next session.
  void clear() {
    _entries.clear();
    _inFlight.clear();
  }

  @visibleForTesting
  int get entryCount => _entries.length;

  @visibleForTesting
  int get inFlightCount => _inFlight.length;
}

class _Entry {
  _Entry(this.value, this.expiresAt);

  final dynamic value;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
