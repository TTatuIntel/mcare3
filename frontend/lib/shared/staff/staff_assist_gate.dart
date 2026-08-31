import '../auth/auth_state.dart';
import '../models/user_role.dart';

/// Who may act on a patient's record on their behalf.
///
/// Doctors and admin staff both qualify. The distinction that matters is not
/// seniority but caseload: admin and mCare assistants are not on one, so the
/// doctor endpoints reject them outright and the API has to pick the route
/// from the role. Keeping the test in one place stops a new staff surface from
/// inventing its own answer.
///
/// A patient never qualifies. The clinical chart is also how a patient's own
/// record renders, and offering "log a vital for this patient" to the patient
/// themselves would be nonsense.
class StaffAssistGate {
  StaffAssistGate._();

  static bool canAssist() {
    final role = AuthState.instance.user?.role;

    return role == UserRole.doctor ||
        role == UserRole.admin ||
        role == UserRole.mcareAssistant;
  }
}
