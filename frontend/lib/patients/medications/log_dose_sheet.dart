import 'package:flutter/material.dart';

import '../../shared/models/medication.dart';
import 'dose_detail_sheet.dart';

/// Backward-compatible alias — opens the full dose detail popup.
class LogDoseSheet {
  LogDoseSheet._();

  static Future<void> show(BuildContext context, MedicationDose dose) {
    return DoseDetailSheet.show(context, dose);
  }
}
