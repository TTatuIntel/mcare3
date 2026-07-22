import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/app_icons.dart';

enum RiskLevel {
  normal,
  warning,
  critical,
  unknown;

  Color get color => switch (this) {
        RiskLevel.normal => AppColors.success,
        RiskLevel.warning => AppColors.warning,
        RiskLevel.critical => AppColors.critical,
        RiskLevel.unknown => AppColors.textMutedAA,
      };

  /// Theme-aware soft background for status chips.
  Color softBg(BuildContext context) => switch (this) {
        RiskLevel.normal => AppPalette.successSoft(context),
        RiskLevel.warning => AppPalette.warningSoft(context),
        RiskLevel.critical => AppPalette.criticalSoft(context),
        RiskLevel.unknown => AppPalette.surfaceMuted(context),
      };

  /// Theme-aware label color for status chips.
  Color labelColor(BuildContext context) => switch (this) {
        RiskLevel.unknown => AppPalette.textMuted(context),
        _ => color,
      };

  Color get soft => switch (this) {
        RiskLevel.normal => AppColors.successSoft,
        RiskLevel.warning => AppColors.warningSoft,
        RiskLevel.critical => AppColors.criticalSoft,
        RiskLevel.unknown => AppColors.surfaceMuted,
      };

  String get label => switch (this) {
        RiskLevel.normal => 'Normal',
        RiskLevel.warning => 'Watch',
        RiskLevel.critical => 'Critical',
        RiskLevel.unknown => 'No data',
      };
}

enum VitalKey {
  bloodPressure,
  heartRate,
  bloodOxygen,
  temperature,
  bloodGlucose,
  respiratoryRate,
  weight;

  String get label => switch (this) {
        VitalKey.bloodPressure => 'Blood Pressure',
        VitalKey.heartRate => 'Heart Rate',
        VitalKey.bloodOxygen => 'Blood Oxygen',
        VitalKey.temperature => 'Temperature',
        VitalKey.bloodGlucose => 'Blood Glucose',
        VitalKey.respiratoryRate => 'Respiratory Rate',
        VitalKey.weight => 'Weight',
      };

  String get shortLabel => switch (this) {
        VitalKey.bloodPressure => 'BP',
        VitalKey.heartRate => 'HR',
        VitalKey.bloodOxygen => 'SpO₂',
        VitalKey.temperature => 'Temp',
        VitalKey.bloodGlucose => 'Glucose',
        VitalKey.respiratoryRate => 'Resp',
        VitalKey.weight => 'Weight',
      };

  String get unit => switch (this) {
        VitalKey.bloodPressure => 'mmHg',
        VitalKey.heartRate => 'bpm',
        VitalKey.bloodOxygen => '%',
        VitalKey.temperature => '°C',
        VitalKey.bloodGlucose => 'mg/dL',
        VitalKey.respiratoryRate => '/min',
        VitalKey.weight => 'kg',
      };

  IconData get icon => switch (this) {
        VitalKey.bloodPressure => AppIcons.bloodPressure,
        VitalKey.heartRate => AppIcons.heartRate,
        VitalKey.bloodOxygen => AppIcons.spo2,
        VitalKey.temperature => AppIcons.temperature,
        VitalKey.bloodGlucose => AppIcons.glucose,
        VitalKey.respiratoryRate => AppIcons.respiratory,
        VitalKey.weight => AppIcons.weight,
      };

  Color get accent => switch (this) {
        VitalKey.bloodPressure => AppColors.bpPurple,
        VitalKey.heartRate => AppColors.heartRed,
        VitalKey.bloodOxygen => AppColors.spo2Blue,
        VitalKey.temperature => AppColors.tempTeal,
        VitalKey.bloodGlucose => AppColors.glucoseAmber,
        VitalKey.respiratoryRate => AppColors.respGreen,
        VitalKey.weight => AppColors.weightSlate,
      };

  bool get hasSecondaryValue => this == VitalKey.bloodPressure;
}

class VitalReading {
  const VitalReading({
    required this.id,
    required this.vital,
    required this.value,
    this.secondaryValue,
    required this.recordedAt,
    required this.risk,
    this.note,
  });

  final String id;
  final VitalKey vital;
  final double value;
  final double? secondaryValue;
  final DateTime recordedAt;
  final RiskLevel risk;
  final String? note;

  String formatValue() {
    if (vital.hasSecondaryValue && secondaryValue != null) {
      return '${value.toStringAsFixed(0)}/${secondaryValue!.toStringAsFixed(0)}';
    }
    if (vital == VitalKey.temperature || vital == VitalKey.weight) {
      return value.toStringAsFixed(1);
    }
    return value.toStringAsFixed(0);
  }
}

class VitalRiskRange {
  const VitalRiskRange({
    required this.normalMin,
    required this.normalMax,
    required this.warningLow,
    required this.warningHigh,
    required this.criticalLow,
    required this.criticalHigh,
  });

  final double normalMin;
  final double normalMax;
  final double warningLow;
  final double warningHigh;
  final double criticalLow;
  final double criticalHigh;

  RiskLevel assess(double v) {
    if (v < criticalLow || v > criticalHigh) return RiskLevel.critical;
    if (v < warningLow || v > warningHigh) return RiskLevel.warning;
    if (v < normalMin || v > normalMax) return RiskLevel.warning;
    return RiskLevel.normal;
  }
}

/// Default product-wide risk ranges (matches section 10.4 of the spec).
class VitalRanges {
  VitalRanges._();
  static const Map<VitalKey, VitalRiskRange> defaults = {
    VitalKey.bloodPressure: VitalRiskRange(
      normalMin: 90,
      normalMax: 120,
      warningLow: 80,
      warningHigh: 140,
      criticalLow: 70,
      criticalHigh: 160,
    ),
    VitalKey.heartRate: VitalRiskRange(
      normalMin: 60,
      normalMax: 100,
      warningLow: 50,
      warningHigh: 120,
      criticalLow: 40,
      criticalHigh: 140,
    ),
    VitalKey.bloodOxygen: VitalRiskRange(
      normalMin: 95,
      normalMax: 100,
      warningLow: 90,
      warningHigh: 100,
      criticalLow: 85,
      criticalHigh: 100,
    ),
    VitalKey.temperature: VitalRiskRange(
      normalMin: 36.1,
      normalMax: 37.2,
      warningLow: 35.5,
      warningHigh: 38.0,
      criticalLow: 35.0,
      criticalHigh: 39.0,
    ),
    VitalKey.bloodGlucose: VitalRiskRange(
      normalMin: 70,
      normalMax: 100,
      warningLow: 54,
      warningHigh: 126,
      criticalLow: 50,
      criticalHigh: 180,
    ),
    VitalKey.respiratoryRate: VitalRiskRange(
      normalMin: 12,
      normalMax: 20,
      warningLow: 10,
      warningHigh: 24,
      criticalLow: 8,
      criticalHigh: 28,
    ),
    VitalKey.weight: VitalRiskRange(
      normalMin: 0,
      normalMax: 500,
      warningLow: 0,
      warningHigh: 500,
      criticalLow: 0,
      criticalHigh: 500,
    ),
  };
}

/// Per-vital alert notification settings. Stored on VitalCatalogEntry so every
/// vital can have independent escalation and notification behaviour.
class VitalAlertConfig {
  const VitalAlertConfig({
    this.enableWarningAlerts = true,
    this.enableCriticalAlerts = true,
    this.autoResolveOnNormal = true,
    this.escalationEnabled = false,
    this.escalationDelayMinutes = 60,
    this.criticalAlertTitle,
    this.warningAlertTitle,
  });

  /// Fire an in-app notification when a warning reading is recorded.
  final bool enableWarningAlerts;

  /// Fire an in-app notification when a critical reading is recorded.
  final bool enableCriticalAlerts;

  /// Automatically resolve the active alert when the next reading is normal.
  final bool autoResolveOnNormal;

  /// After [escalationDelayMinutes] of an unresolved alert, escalate to the
  /// next responder tier (doctor → assistant → admin).
  final bool escalationEnabled;
  final int escalationDelayMinutes;

  /// Custom alert title templates. When null the default template is used:
  ///   critical → "<Label> is critical"
  ///   warning  → "<Label> is outside range"
  final String? criticalAlertTitle;
  final String? warningAlertTitle;

  static const VitalAlertConfig defaults = VitalAlertConfig();

  VitalAlertConfig copyWith({
    bool? enableWarningAlerts,
    bool? enableCriticalAlerts,
    bool? autoResolveOnNormal,
    bool? escalationEnabled,
    int? escalationDelayMinutes,
    String? criticalAlertTitle,
    String? warningAlertTitle,
  }) =>
      VitalAlertConfig(
        enableWarningAlerts: enableWarningAlerts ?? this.enableWarningAlerts,
        enableCriticalAlerts: enableCriticalAlerts ?? this.enableCriticalAlerts,
        autoResolveOnNormal: autoResolveOnNormal ?? this.autoResolveOnNormal,
        escalationEnabled: escalationEnabled ?? this.escalationEnabled,
        escalationDelayMinutes:
            escalationDelayMinutes ?? this.escalationDelayMinutes,
        criticalAlertTitle: criticalAlertTitle ?? this.criticalAlertTitle,
        warningAlertTitle: warningAlertTitle ?? this.warningAlertTitle,
      );
}
