import 'package:flutter/material.dart';

import '../../shared/widgets/app_icons.dart';

/// Patient-scoped tools — only shown inside a selected patient's workspace.
enum DoctorPatientSection {
  overview,
  vitals,
  documents,
  prescriptions,
  meals,
  medications,
  alerts,
  sos,
  appointments,
  messages,
  reports,
  timeline,
  trends,
}

extension DoctorPatientSectionX on DoctorPatientSection {
  String get label => switch (this) {
        DoctorPatientSection.overview => 'Overview',
        DoctorPatientSection.vitals => 'Vitals',
        DoctorPatientSection.documents => 'Documents',
        DoctorPatientSection.prescriptions => 'Prescriptions',
        DoctorPatientSection.meals => 'Meals',
        DoctorPatientSection.medications => 'Medications',
        DoctorPatientSection.alerts => 'Alerts',
        DoctorPatientSection.sos => 'SOS',
        DoctorPatientSection.appointments => 'Appointments',
        DoctorPatientSection.messages => 'Messages',
        DoctorPatientSection.reports => 'Reports',
        DoctorPatientSection.timeline => 'Timeline',
        DoctorPatientSection.trends => 'Trends',
      };

  IconData get icon => switch (this) {
        DoctorPatientSection.overview => AppIcons.chart,
        DoctorPatientSection.vitals => AppIcons.vitals,
        DoctorPatientSection.documents => AppIcons.document,
        DoctorPatientSection.prescriptions => AppIcons.prescription,
        DoctorPatientSection.meals => AppIcons.meals,
        DoctorPatientSection.medications => AppIcons.medication,
        DoctorPatientSection.alerts => AppIcons.alert,
        DoctorPatientSection.sos => AppIcons.sos,
        DoctorPatientSection.appointments => AppIcons.appointment,
        DoctorPatientSection.messages => AppIcons.chat,
        DoctorPatientSection.reports => AppIcons.report,
        DoctorPatientSection.timeline => AppIcons.audit,
        DoctorPatientSection.trends => AppIcons.trend,
      };
}
