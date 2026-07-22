/// Unified vital domain — catalog, alerts, and caseload summaries.
///
/// Import this module anywhere vitals need consistent behavior across
/// patient, doctor, and admin surfaces.
library;

export '../models/vital.dart';
export 'vital_alert_parse.dart';
export 'vital_alert_helpers.dart';
