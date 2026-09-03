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

/// Who put a meal on the plan. A clinician's instruction and a meal the
/// patient added for themselves are both real plan entries, but only the
/// patient's own are theirs to edit or delete.
enum MealPlanSource {
  careTeam,
  patient;

  String get label => switch (this) {
        MealPlanSource.careTeam => 'Care team',
        MealPlanSource.patient => 'Added by you',
      };

  IconData get icon => switch (this) {
        MealPlanSource.careTeam => AppIcons.careTeam,
        MealPlanSource.patient => AppIcons.user,
      };

  String get apiValue => switch (this) {
        MealPlanSource.careTeam => 'care_team',
        MealPlanSource.patient => 'patient',
      };

  static MealPlanSource fromApi(String? raw) => switch (raw) {
        'patient' => MealPlanSource.patient,
        _ => MealPlanSource.careTeam,
      };
}

/// Whether the patient followed a planned meal. [pending] is the resting
/// state — nothing has been said yet — and is deliberately not "missed", so a
/// meal later in the day is never reported as a failure.
enum MealAdherence {
  pending,
  followed,
  partial,
  skipped;

  String get label => switch (this) {
        MealAdherence.pending => 'Not logged',
        MealAdherence.followed => 'Followed',
        MealAdherence.partial => 'Partly followed',
        MealAdherence.skipped => 'Skipped',
      };

  String get shortLabel => switch (this) {
        MealAdherence.pending => 'Log',
        MealAdherence.followed => 'Followed',
        MealAdherence.partial => 'Partly',
        MealAdherence.skipped => 'Skipped',
      };

  IconData get icon => switch (this) {
        MealAdherence.pending => AppIcons.time,
        MealAdherence.followed => AppIcons.check,
        MealAdherence.partial => Icons.remove_circle_outline_rounded,
        MealAdherence.skipped => Icons.cancel_rounded,
      };

  Color get color => switch (this) {
        MealAdherence.pending => AppColors.textMutedAA,
        MealAdherence.followed => AppColors.success,
        MealAdherence.partial => AppColors.warning,
        MealAdherence.skipped => AppColors.critical,
      };

  /// Counts toward the adherence rate. A skipped meal counts as answered but
  /// not as followed; a partly followed one counts as half.
  double get credit => switch (this) {
        MealAdherence.pending => 0,
        MealAdherence.followed => 1,
        MealAdherence.partial => 0.5,
        MealAdherence.skipped => 0,
      };

  bool get isLogged => this != MealAdherence.pending;

  static MealAdherence fromApi(String? raw) => MealAdherence.values.firstWhere(
        (a) => a.name == raw,
        orElse: () => MealAdherence.pending,
      );
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
    this.scheduledFor,
    this.serveTime,
    this.conditionTag,
    this.items = const [],
    this.source = MealPlanSource.careTeam,
    this.adherence = MealAdherence.pending,
    this.loggedAt,
    this.patientNote,
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

  /// The day the meal is meant to be eaten. Null on plans written before the
  /// timetable existed, which fall back to [assignedAt] through [planDate].
  final DateTime? scheduledFor;

  /// 24-hour serve time, `HH:mm`. Null when the plan is for the day at large.
  final String? serveTime;

  /// The condition the plan was prescribed for — "Type 2 diabetes",
  /// "Hypertension". Shown to the patient so the advice has a reason.
  final String? conditionTag;

  /// Individual foods making up the meal, for a checklist-style detail view.
  final List<String> items;

  final MealPlanSource source;
  final MealAdherence adherence;
  final DateTime? loggedAt;

  /// What the patient said when they logged the meal.
  final String? patientNote;

  /// The calendar day this plan belongs to, normalised to midnight.
  DateTime get planDate {
    final at = scheduledFor ?? assignedAt;
    return DateTime(at.year, at.month, at.day);
  }

  /// Sort key within a day: the serve time when one is set, otherwise the
  /// natural breakfast → lunch → dinner → snack order of the meal type.
  int get slotMinutes {
    final parts = serveTime?.split(':');
    if (parts != null && parts.length == 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) return h * 60 + m;
    }
    return switch (mealType) {
      MealType.breakfast => 7 * 60,
      MealType.lunch => 13 * 60,
      MealType.dinner => 19 * 60,
      MealType.snack => 16 * 60,
      MealType.general => 12 * 60,
    };
  }

  bool get isSelfAdded => source == MealPlanSource.patient;

  String? get serveLabel {
    final minutes = serveTime == null ? null : slotMinutes;
    if (minutes == null) return null;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final suffix = h < 12 ? 'AM' : 'PM';
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return '$hour12:${m.toString().padLeft(2, '0')} $suffix';
  }

  StaffMealPlan copyWith({
    String? title,
    MealType? mealType,
    String? description,
    int? calories,
    String? protein,
    String? carbs,
    String? fat,
    String? notes,
    DateTime? scheduledFor,
    String? serveTime,
    String? conditionTag,
    List<String>? items,
    MealPlanSource? source,
    MealAdherence? adherence,
    DateTime? loggedAt,
    String? patientNote,
    bool clearServeTime = false,
    bool clearLoggedAt = false,
  }) {
    return StaffMealPlan(
      id: id,
      patientId: patientId,
      patientName: patientName,
      title: title ?? this.title,
      mealType: mealType ?? this.mealType,
      description: description ?? this.description,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      notes: notes ?? this.notes,
      assignedAt: assignedAt,
      assignedBy: assignedBy,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      serveTime: clearServeTime ? null : (serveTime ?? this.serveTime),
      conditionTag: conditionTag ?? this.conditionTag,
      items: items ?? this.items,
      source: source ?? this.source,
      adherence: adherence ?? this.adherence,
      loggedAt: clearLoggedAt ? null : (loggedAt ?? this.loggedAt),
      patientNote: patientNote ?? this.patientNote,
    );
  }

  String get macroSummary {
    final parts = <String>[];
    if (calories != null) parts.add('$calories kcal');
    if (protein != null) parts.add('P $protein');
    if (carbs != null) parts.add('C $carbs');
    if (fat != null) parts.add('F $fat');
    return parts.join(' · ');
  }
}
