import 'package:flutter/foundation.dart';

import '../../core/api/meal_plans_api.dart';
import '../../core/env/app_env.dart';
import '../models/meal_plan.dart';

/// The signed-in patient's nutrition timetable.
///
/// Holds two kinds of entry side by side: plans a clinician assigned (staff
/// read the same rows per patient through `StaffState`) and meals the patient
/// added for themselves. Both are seeded from `GET /patient/session`
/// (`meal_plans`); the patient's own writes go through [MealPlansApi] and fall
/// back to local-only when the backend is disabled, mirroring `VitalsState`.
class MealPlansState extends ChangeNotifier {
  MealPlansState._();
  static final MealPlansState instance = MealPlansState._();

  final List<StaffMealPlan> _items = [];

  /// Newest scheduled day first, and within a day earliest serve time first.
  List<StaffMealPlan> get all => List.unmodifiable(_items);

  static DateTime dayOf(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// Plans for [date], ordered breakfast → lunch → dinner → snack (or by the
  /// serve time when one was set).
  List<StaffMealPlan> plansForDate(DateTime date) {
    final day = dayOf(date);
    final list = _items.where((m) => m.planDate == day).toList()..sort(_bySlot);
    return List.unmodifiable(list);
  }

  /// Plans assigned for today, ordered breakfast → lunch → dinner → snack.
  List<StaffMealPlan> get assignedToday => plansForDate(DateTime.now());

  /// Every day that has at least one plan — what the day strip dots read.
  Set<DateTime> get datesWithPlans => _items.map((m) => m.planDate).toSet();

  bool hasPlansOn(DateTime date) => _items.any((m) => m.planDate == dayOf(date));

  /// The most recent plan, whenever it was assigned. Used when nothing was
  /// assigned today but the patient still has standing guidance.
  StaffMealPlan? get latest => _items.isEmpty ? null : _items.first;

  StaffMealPlan? byId(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// The next meal still waiting to be logged on [date], if any.
  StaffMealPlan? nextUnlogged(DateTime date) {
    for (final plan in plansForDate(date)) {
      if (!plan.adherence.isLogged) return plan;
    }
    return null;
  }

  /// Share of planned meals the patient followed over the last [days] days,
  /// as 0–1. Only meals up to today count — one planned for tomorrow is not a
  /// missed one. Returns null when there is nothing to measure yet.
  double? adherenceRate({int days = 21}) {
    final plans = _recentPlans(days);
    if (plans.isEmpty) return null;
    final credit = plans.fold<double>(0, (sum, p) => sum + p.adherence.credit);
    return (credit / plans.length).clamp(0.0, 1.0);
  }

  /// How many planned meals in the window are still unlogged.
  int unloggedCount({int days = 21}) =>
      _recentPlans(days).where((p) => !p.adherence.isLogged).length;

  /// Consecutive days ending today on which every planned meal was followed
  /// or partly followed. A day with no plans does not break the streak, it
  /// simply is not counted.
  int get followedStreak {
    final today = dayOf(DateTime.now());
    var streak = 0;
    for (var back = 0; back < 120; back++) {
      final day = today.subtract(Duration(days: back));
      final plans = plansForDate(day);
      if (plans.isEmpty) continue;
      final kept = plans.every(
        (p) =>
            p.adherence == MealAdherence.followed ||
            p.adherence == MealAdherence.partial,
      );
      if (!kept) break;
      streak++;
    }
    return streak;
  }

  void seed(List<StaffMealPlan> items) {
    _items
      ..clear()
      ..addAll(items)
      ..sort(_byDayThenSlot);
    notifyListeners();
  }

  /// Inserts or replaces a plan in place, keeping the list sorted.
  void upsert(StaffMealPlan plan) {
    final index = _items.indexWhere((m) => m.id == plan.id);
    if (index == -1) {
      _items.add(plan);
    } else {
      _items[index] = plan;
    }
    _items.sort(_byDayThenSlot);
    notifyListeners();
  }

  void removeLocal(String id) {
    _items.removeWhere((m) => m.id == id);
    notifyListeners();
  }

  /// Records whether the patient followed [plan]. Optimistic: the row flips
  /// immediately and rolls back if the API rejects it, so a tap always feels
  /// instant on a slow connection.
  Future<void> logAdherence(
    StaffMealPlan plan,
    MealAdherence adherence, {
    String? note,
  }) async {
    final before = plan;
    upsert(
      plan.copyWith(
        adherence: adherence,
        patientNote: note,
        loggedAt: adherence.isLogged ? DateTime.now() : null,
        clearLoggedAt: !adherence.isLogged,
      ),
    );
    if (!AppEnv.backendEnabled) return;
    try {
      final saved = await MealPlansApi.instance.log(
        planId: plan.id,
        adherence: adherence,
        note: note,
      );
      if (saved != null) upsert(saved);
    } catch (_) {
      upsert(before);
      rethrow;
    }
  }

  /// Adds a meal the patient planned for themselves. Returns the stored plan
  /// (server-canonical when the backend is on).
  Future<StaffMealPlan> addSelfPlan(StaffMealPlan draft) async {
    if (!AppEnv.backendEnabled) {
      upsert(draft);
      return draft;
    }
    final saved = await MealPlansApi.instance.create(draft);
    final canonical = saved ?? draft;
    upsert(canonical);
    return canonical;
  }

  /// Updates a meal the patient added themselves.
  Future<StaffMealPlan> updateSelfPlan(StaffMealPlan plan) async {
    if (!AppEnv.backendEnabled) {
      upsert(plan);
      return plan;
    }
    final saved = await MealPlansApi.instance.update(plan);
    final canonical = saved ?? plan;
    upsert(canonical);
    return canonical;
  }

  /// Removes a meal the patient added themselves. Optimistic with rollback.
  Future<void> removeSelfPlan(StaffMealPlan plan) async {
    removeLocal(plan.id);
    if (!AppEnv.backendEnabled) return;
    try {
      await MealPlansApi.instance.remove(plan.id);
    } catch (_) {
      upsert(plan);
      rethrow;
    }
  }

  /// Planned meals from the last [days] days up to and including today.
  List<StaffMealPlan> _recentPlans(int days) {
    final today = dayOf(DateTime.now());
    final cutoff = today.subtract(Duration(days: days - 1));
    return _items
        .where((m) => !m.planDate.isBefore(cutoff) && !m.planDate.isAfter(today))
        .toList();
  }

  static int _bySlot(StaffMealPlan a, StaffMealPlan b) {
    final bySlot = a.slotMinutes.compareTo(b.slotMinutes);
    if (bySlot != 0) return bySlot;
    return a.mealType.index.compareTo(b.mealType.index);
  }

  static int _byDayThenSlot(StaffMealPlan a, StaffMealPlan b) {
    final byDay = b.planDate.compareTo(a.planDate);
    if (byDay != 0) return byDay;
    return _bySlot(a, b);
  }
}
