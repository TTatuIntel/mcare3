import '../../core/api/doctor_api.dart';
import '../../core/env/app_env.dart';
import '../state/staff_state.dart';

/// Loads per-patient workspace detail from the API into `StaffState`.
class DoctorPatientDetailService {
  DoctorPatientDetailService._();
  static final DoctorPatientDetailService instance =
      DoctorPatientDetailService._();

  Future<bool> loadPatient(String patientId) async {
    if (!AppEnv.backendEnabled) return true;
    final data = await DoctorApi.instance.patientDetail(patientId);
    if (data == null) return false;
    StaffState.instance.mergePatientDetail(patientId, data);
    return true;
  }
}
