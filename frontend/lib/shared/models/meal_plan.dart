import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/app_icons.dart';

enum MealType {
  breakfast,
  lunch,
  dinner,
  snack,
  general;

  String get label => switch (this) {
        MealType.breakfast => 'Breakfast',
        MealType.lunch => 'Lunch',
        MealType.dinner => 'Dinner',
        MealType.snack => 'Snack',
        MealType.general => 'General',
      };

  IconData get icon => switch (this) {
        MealType.breakfast => Icons.wb_sunny_rounded,
        MealType.lunch => AppIcons.meals,
        MealType.dinner => Icons.dinner_dining_rounded,
        MealType.snack => Icons.cookie_rounded,
        MealType.general => Icons.food_bank_rounded,
      };

  Color get color => switch (this) {
        MealType.breakfast => const Color(0xFFFF9800),
        MealType.lunch => AppColors.success,
        MealType.dinner => AppColors.adminPurple,
        MealType.snack => AppColors.info,
        MealType.general => AppColors.textMutedAA,
      };
}

class StaffMealPlan {
  StaffMealPlan({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.title,
    required this.mealType,
    required this.assignedAt,
    required this.assignedBy,
    this.description,
    this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.notes,
  });

  final String id;
  final String patientId;
  final String patientName;
  final String title;
  final MealType mealType;
  final String? description;
  final int? calories;
  final String? protein;
  final String? carbs;
  final String? fat;
  final String? notes;
  final DateTime assignedAt;
  final String assignedBy;

  String get macroSummary {
    final parts = <String>[];
    if (calories != null) parts.add('$calories kcal');
    if (protein != null) parts.add('P $protein');
    if (carbs != null) parts.add('C $carbs');
    if (fat != null) parts.add('F $fat');
    return parts.join(' · ');
  }
}
