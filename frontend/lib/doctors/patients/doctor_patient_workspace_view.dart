import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/patient_domain_mapper.dart';
import '../../core/api/documents_api.dart';
import '../../core/env/app_env.dart';
import '../../patients/documents/edit_document_sheet.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/appointment.dart';
import '../../shared/models/document.dart';
import '../../shared/models/meal_plan.dart';
import '../../shared/models/vital.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/services/doctor_patient_detail_service.dart';
import '../../shared/services/doctor_session_service.dart';
import '../../shared/sos/sos_respond_context.dart';
import '../../shared/state/messages_state.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_motion.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/medical_document_viewer_body.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/risk_badge.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';
import '../../shared/widgets/staff_patient_profile_sheet.dart';
import '../alerts/doctor_alert_resolve_sheet.dart';
import '../appointments/doctor_appointment_flows.dart';
import '../meals/doctor_assign_meal_sheet.dart';
import '../sos/doctor_sos_respond_sheet.dart';
import '../vitals/doctor_assigned_vitals_view_sheet.dart';
import 'doctor_patient_vital_feed.dart';
import '../widgets/doctor_edit_chart_sheet.dart';
import '../widgets/doctor_patient_quick_links.dart';
import '../widgets/doctor_rx_sheet.dart';
import 'doctor_patient_section.dart';
import 'doctor_upload_document_sheet.dart';

part 'doctor_patient_panels.dart';
part 'doctor_patient_detail_panels.dart';
part 'doctor_patient_trends.dart';

/// Patient-centered workspace — most doctor tools live here, not the main nav.
class DoctorPatientWorkspaceView extends StatefulWidget {
  const DoctorPatientWorkspaceView({
    super.key,
    required this.patientId,
    this.initialSection = DoctorPatientSection.overview,
    this.openSosRespond = false,
    this.sosEventId,
  });

  final String patientId;
  final DoctorPatientSection initialSection;
  final bool openSosRespond;
  final String? sosEventId;

  @override
  State<DoctorPatientWorkspaceView> createState() =>
      _DoctorPatientWorkspaceViewState();
}

class _DoctorPatientWorkspaceViewState
    extends State<DoctorPatientWorkspaceView> {
  late DoctorPatientSection _section = widget.initialSection;
  var _respondSheetShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await DoctorPatientDetailService.instance.loadPatient(widget.patientId);
      if (!mounted) return;
      if (widget.openSosRespond && !_respondSheetShown) {
        _respondSheetShown = true;
        await DoctorSosRespondSheet.show(
          context,
          patientId: widget.patientId,
          eventId: widget.sosEventId,
        );
      }
    });
  }

  Map<DoctorPatientSection, int> _badges(String patientId) {
    final s = StaffState.instance;
    final patient = s.patientById(patientId);
    final conv = patient == null
        ? null
        : MessagesState.instance.conversationForPatient(
            patientId: patientId,
            patientName: patient.name,
          );
    return {
      DoctorPatientSection.alerts: s.openAlertCountForPatient(patientId),
      DoctorPatientSection.sos: s.hasActiveSos(patientId) ? 1 : 0,
      DoctorPatientSection.appointments: s
          .appointmentsForPatient(patientId)
          .length,
      DoctorPatientSection.documents: s.documentsForPatient(patientId).length,
      DoctorPatientSection.messages: conv?.unreadCount ?? 0,
      DoctorPatientSection.meals: s.mealPlansForPatient(patientId).length,
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: StaffState.instance,
      builder: (context, _) {
        final patient = StaffState.instance.patientById(widget.patientId);
        if (patient == null) {
          return RoleShell(
            currentRoute: RouteNames.doctorPatients,
            destinations: StaffDestinations.doctor(),
            profileRoute: RouteNames.doctorProfile,
            notificationsRoute: RouteNames.doctorNotifications,
            title: 'Patient workspace',
            body: GlassCard(
              frosted: true,
              child: EmptyStateView(
                icon: AppIcons.chart,
                title: 'Patient not found',
                compact: true,
              ),
            ),
          );
        }

        return RoleShell(
          currentRoute: RouteNames.doctorPatients,
          destinations: StaffDestinations.doctor(),
          profileRoute: RouteNames.doctorProfile,
          notificationsRoute: RouteNames.doctorNotifications,
          title: patient.name,
          subtitle: patient.demographicsLine,
          subjectIdentity: RoleSubjectIdentity(
            name: patient.name,
            initials: _patientInitials(patient.name),
            accent: AppColors.doctorGreen,
            onTap: () => StaffPatientProfileSheet.show(
              context,
              patientId: widget.patientId,
              patientName: patient.name,
            ),
          ),
          headerActions: [
            AppButton(
              label: 'All patients',
              icon: AppIcons.chevronLeft,
              size: AppButtonSize.sm,
              variant: AppButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                RouteNames.doctorPatients,
                (_) => false,
              ),
            ),
            IconButton(
              icon: const Icon(AppIcons.edit, size: 20),
              tooltip: 'Edit chart',
              onPressed: () => showDoctorEditChartSheet(
                context,
                patientId: widget.patientId,
              ),
            ),
            const SizedBox(width: 4),
          ],
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: _PatientStatusStrip(
                  patient: patient,
                  patientId: widget.patientId,
                  onNavigate: (s) => setState(() => _section = s),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 1,
                child: DoctorPatientQuickLinks(
                  selected: _section,
                  badges: _badges(widget.patientId),
                  onSelected: (s) => setState(() => _section = s),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 2,
                child: AnimatedSwitcher(
                  duration: AppMotion.page,
                  switchInCurve: AppMotion.easeOut,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.03),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: _SectionBody(
                    key: ValueKey(_section),
                    section: _section,
                    patientId: widget.patientId,
                    patientName: patient.name,
                    onNavigateSection: (s) => setState(() => _section = s),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Back-compat alias — routes still reference [DoctorPatientChartView].
class DoctorPatientChartView extends StatelessWidget {
  const DoctorPatientChartView({
    super.key,
    required this.patientId,
    this.initialSection = DoctorPatientSection.overview,
  });

  final String patientId;
  final DoctorPatientSection initialSection;

  @override
  Widget build(BuildContext context) => DoctorPatientWorkspaceView(
    patientId: patientId,
    initialSection: initialSection,
  );
}
