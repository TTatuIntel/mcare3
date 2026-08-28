import 'package:flutter/material.dart';

/// Single icon registry. Every screen references these tokens — never raw
/// `Icons.*` for a shared concept. A heart means heart-rate everywhere.
class AppIcons {
  AppIcons._();

  // Navigation / chrome
  static const IconData home = Icons.dashboard_rounded;
  static const IconData records = Icons.folder_open_rounded;
  static const IconData careTeam = Icons.medical_services_rounded;
  static const IconData profile = Icons.person_rounded;
  static const IconData settings = Icons.settings_rounded;
  static const IconData bell = Icons.notifications_rounded;
  static const IconData notifications = bell;
  static const IconData back = Icons.arrow_back_rounded;
  static const IconData backIos = Icons.arrow_back_ios_new_rounded;
  static const IconData refresh = Icons.refresh_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData more = Icons.more_horiz_rounded;
  static const IconData chevronRight = Icons.chevron_right_rounded;
  static const IconData chevronLeft = Icons.chevron_left_rounded;
  static const IconData expandMore = Icons.expand_more_rounded;
  static const IconData expandLess = Icons.expand_less_rounded;
  static const IconData search = Icons.search_rounded;
  static const IconData language = Icons.translate_rounded;
  static const IconData filter = Icons.tune_rounded;

  // Clinical domains
  static const IconData vitals = Icons.monitor_heart_rounded;
  static const IconData heartRate = Icons.favorite_rounded;
  static const IconData bloodPressure = Icons.water_drop_rounded;
  static const IconData spo2 = Icons.bubble_chart_rounded;
  static const IconData temperature = Icons.thermostat_rounded;
  static const IconData glucose = Icons.bloodtype_rounded;
  static const IconData respiratory = Icons.air_rounded;
  static const IconData weight = Icons.monitor_weight_rounded;

  // Care features
  static const IconData appointment = Icons.event_available_rounded;
  static const IconData medication = Icons.medication_rounded;
  static const IconData hydration = Icons.water_drop_outlined;
  static const IconData activity = Icons.directions_walk_rounded;
  static const IconData notes = Icons.sticky_note_2_outlined;
  static const IconData history = Icons.history_rounded;
  static const IconData document = Icons.description_rounded;
  static const IconData report = Icons.assignment_rounded;
  static const IconData chat = Icons.chat_bubble_rounded;
  static const IconData support = Icons.support_agent_rounded;
  static const IconData ticket = Icons.confirmation_number_rounded;
  static const IconData meals = Icons.restaurant_rounded;
  static const IconData sos = Icons.emergency_rounded;

  // Generic
  static const IconData add = Icons.add_rounded;
  static const IconData edit = Icons.edit_rounded;
  static const IconData delete = Icons.delete_outline_rounded;
  static const IconData alert = Icons.warning_amber_rounded;
  static const IconData check = Icons.check_circle_rounded;
  static const IconData checkMark = Icons.check_rounded;
  static const IconData acknowledge = Icons.pan_tool_alt_rounded;
  static const IconData trendUp = Icons.trending_up_rounded;
  static const IconData trendDown = Icons.trending_down_rounded;
  static const IconData trend = Icons.show_chart_rounded;
  static const IconData calendar = Icons.calendar_today_rounded;
  static const IconData time = Icons.schedule_rounded;
  static const IconData location = Icons.location_on_rounded;
  static const IconData info = Icons.info_outline_rounded;
  static const IconData visibility = Icons.visibility_rounded;
  static const IconData visibilityOff = Icons.visibility_off_rounded;
  static const IconData logout = Icons.logout_rounded;
  static const IconData google = Icons.g_mobiledata_rounded;
  static const IconData apple = Icons.apple_rounded;
  static const IconData phone = Icons.phone_rounded;
  static const IconData email = Icons.mail_outline_rounded;
  static const IconData lock = Icons.lock_outline_rounded;
  static const IconData user = Icons.person_outline_rounded;

  // Staff / clinical-ops domains
  static const IconData patients = Icons.groups_2_rounded;
  static const IconData chart = Icons.assignment_ind_rounded;
  static const IconData prescription = Icons.receipt_long_rounded;
  static const IconData assignments = Icons.assignment_turned_in_rounded;
  static const IconData approval = Icons.verified_user_rounded;
  static const IconData careRequest = Icons.handshake_rounded;
  static const IconData permissions = Icons.shield_rounded;
  static const IconData audit = Icons.history_rounded;
  static const IconData analytics = Icons.insights_rounded;
  static const IconData system = Icons.tune_rounded;
  static const IconData users = Icons.people_alt_rounded;
  static const IconData catalog = Icons.checklist_rounded;
  static const IconData download = Icons.download_rounded;
  static const IconData upload = Icons.upload_rounded;
  static const IconData send = Icons.send_rounded;
  static const IconData link = Icons.link_rounded;
  static const IconData lab = Icons.science_rounded;
  static const IconData nurse = Icons.local_hospital_rounded;
  static const IconData pharmacy = Icons.local_pharmacy_rounded;
  static const IconData announcements = Icons.campaign_rounded;
  static const IconData security = Icons.security_rounded;
  static const IconData notificationsActive =
      Icons.notifications_active_rounded;
  static const IconData error = Icons.error_outline_rounded;
  static const IconData map = Icons.map_rounded;
  static const IconData homeAddress = Icons.home_rounded;
  static const IconData image = Icons.image_rounded;
  static const IconData pdf = Icons.picture_as_pdf_rounded;
  static const IconData file = Icons.insert_drive_file_rounded;
  static const IconData storage = Icons.storage_rounded;
  static const IconData folder = Icons.folder_open_rounded;
  static const IconData copy = Icons.content_copy_rounded;
  static const IconData share = Icons.share_rounded;
  static const IconData star = Icons.star_rounded;
  static const IconData videocam = Icons.videocam_rounded;
  static const IconData photo = Icons.photo_camera_rounded;
  static const IconData mic = Icons.mic_rounded;
  static const IconData attach = Icons.attach_file_rounded;
}
