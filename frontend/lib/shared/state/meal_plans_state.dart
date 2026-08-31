import 'package:flutter/foundation.dart';

import '../models/meal_plan.dart';

/// Nutrition a clinician assigned to the signed-in patient.
///
/// Staff read meal plans per patient through [StaffState]; this store is the
/// patient's own copy, seeded from `GET /patient/session` (`meal_plans`).
class MealPlansState extends ChangeNotifier {
  MealPlansState._();
  static final MealPlansState instance = MealPlansState._();

  final List<StaffMealPlan> _items = [];

  /// Newest assignment first.
  List<StaffMealPlan> get all => List.unmodifiable(_items);

  /// Plans assigned today, ordered breakfast → lunch → dinner → snack.
  List<StaffMealPlan> get assignedToday {
    final now = DateTime.now();
    final today = _items
        .where(
          (m) =>
              m.assignedAt.year == now.year &&
              m.assignedAt.month == now.month &&
              m.assignedAt.day == now.day,
        )
        .toList();
    today.sort((a, b) => a.mealType.index.compareTo(b.mealType.index));
    return List.unmodifiable(today);
  }

  /// The most recent plan, whenever it was assigned. Used when nothing was
  /// assigned today but the patient still has standing guidance.
  StaffMealPlan? get latest => _items.isEmpty ? null : _items.first;

  void seed(List<StaffMealPlan> items) {
    _items
      ..clear()
      ..addAll(items)
      ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));
    notifyListeners();
  }
}
