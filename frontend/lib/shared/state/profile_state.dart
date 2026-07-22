import 'package:flutter/foundation.dart';

import '../models/patient_profile.dart';
import '../models/sos.dart';
import 'sos_state.dart';

class ProfileState extends ChangeNotifier {
  ProfileState._();
  static final ProfileState instance = ProfileState._();

  PatientHealthProfile? _health;
  List<EmergencyContact> _contacts = [];

  /// True only after the API confirmed `has_health_profile == false`.
  /// Prevents [PatientOnboardingGate] from treating "still loading" as
  /// "must onboard" and blanking profile / settings / SOS pages.
  bool _confirmedMissingProfile = false;

  PatientHealthProfile? get health => _health;
  List<EmergencyContact> get emergencyContacts => List.unmodifiable(_contacts);

  /// Patient must finish onboarding — confirmed by API, not just null health.
  bool get needsOnboarding => _health == null && _confirmedMissingProfile;

  void seed({
    required PatientHealthProfile health,
    required List<EmergencyContact> contacts,
  }) {
    _health = health;
    _contacts = List.from(contacts);
    _confirmedMissingProfile = false;
    notifyListeners();
  }

  void updateHealth(PatientHealthProfile h) {
    _health = h;
    _confirmedMissingProfile = false;
    notifyListeners();
  }

  void setAllergies(List<String> items) {
    if (_health == null) return;
    _health!.allergies = items;
    notifyListeners();
  }

  void setConditions(List<String> items) {
    if (_health == null) return;
    _health!.chronicConditions = items;
    notifyListeners();
  }

  void setLocationConsent(bool value) {
    if (_health == null) return;
    _health!.locationConsent = value;
    notifyListeners();
  }

  /// Clears local profile data.
  ///
  /// Pass [confirmedMissing] when the API reported no health profile so
  /// onboarding can run. Soft clears (logout, sync glitch) leave the flag
  /// false so gated pages stay usable.
  void clear({bool confirmedMissing = false}) {
    _health = null;
    _contacts = [];
    _confirmedMissingProfile = confirmedMissing;
    notifyListeners();
  }

  void markNeedsOnboarding() {
    _health = null;
    _contacts = [];
    _confirmedMissingProfile = true;
    notifyListeners();
  }

  void addEmergencyContact(EmergencyContact c) {
    _contacts.add(c);
    SosState.instance.addContact(c);
    notifyListeners();
  }

  void removeEmergencyContact(String id) {
    _contacts.removeWhere((c) => c.id == id);
    SosState.instance.removeContact(id);
    notifyListeners();
  }
}
