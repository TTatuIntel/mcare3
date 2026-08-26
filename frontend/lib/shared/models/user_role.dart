import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum UserRole {
  patient,
  doctor,
  admin,
  mcareAssistant,
  externalDoctor,
  guest;

  String get label => switch (this) {
    UserRole.patient => 'Patient',
    UserRole.doctor => 'Doctor',
    UserRole.admin => 'Admin',
    UserRole.mcareAssistant => 'mCare Assistant',
    UserRole.externalDoctor => 'External Doctor',
    UserRole.guest => 'Guest',
  };

  String get badge => switch (this) {
    UserRole.patient => 'PT',
    UserRole.doctor => 'DR',
    UserRole.admin => 'AD',
    UserRole.mcareAssistant => 'MA',
    UserRole.externalDoctor => 'EX',
    UserRole.guest => '··',
  };

  Color get accent => switch (this) {
    UserRole.patient => AppColors.brandIndigo,
    UserRole.doctor => AppColors.doctorGreen,
    UserRole.admin => AppColors.adminPurple,
    UserRole.mcareAssistant => AppColors.mcareAmber,
    UserRole.externalDoctor => AppColors.info,
    UserRole.guest => AppColors.textMutedAA,
  };
}
