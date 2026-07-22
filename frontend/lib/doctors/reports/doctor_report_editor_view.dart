import 'package:flutter/material.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/role_shell.dart';

/// Report editor — works in two modes:
///   - arg is a report id → edit existing
///   - arg is a patient name (or null) → start a new draft for that patient
class DoctorReportEditorView extends StatefulWidget {
  const DoctorReportEditorView({super.key, this.argument});
  final Object? argument;

  @override
  State<DoctorReportEditorView> createState() => _DoctorReportEditorViewState();
}

class _DoctorReportEditorViewState extends State<DoctorReportEditorView> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _patient;
  String? _existingId;

  @override
  void initState() {
    super.initState();
    final arg = widget.argument;
    ClinicalReport? existing;
    if (arg is String) {
      existing = StaffState.instance.reportById(arg);
    }
    if (existing != null) {
      _existingId = existing.id;
      _title = TextEditingController(text: existing.title);
      _body = TextEditingController(text: existing.body);
      _patient = TextEditingController(text: existing.patientName);
    } else {
      _title = TextEditingController();
      _body = TextEditingController();
      _patient = TextEditingController(text: arg is String ? arg : '');
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _patient.dispose();
    super.dispose();
  }

  void _save({required bool publish}) {
    if (_title.text.trim().isEmpty || _patient.text.trim().isEmpty) {
      AppToast.warn(context, 'Patient and title are required.');
      return;
    }
    if (_existingId == null) {
      final id = 'rp_${DateTime.now().millisecondsSinceEpoch}';
      StaffState.instance.addReport(
        ClinicalReport(
          id: id,
          patientName: _patient.text.trim(),
          title: _title.text.trim(),
          body: _body.text.trim(),
          createdAt: DateTime.now(),
          published: publish,
        ),
      );
    } else {
      StaffState.instance.updateReport(
        _existingId!,
        title: _title.text.trim(),
        body: _body.text.trim(),
      );
      if (publish) StaffState.instance.publishReport(_existingId!);
    }
    AppToast.success(context, publish ? 'Report published.' : 'Draft saved.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: RouteNames.doctorReports,
      destinations: StaffDestinations.doctor(),
      profileRoute: RouteNames.doctorProfile,
      notificationsRoute: RouteNames.doctorNotifications,
      title: _existingId == null ? 'New report' : 'Edit report',
      subtitle: _patient.text.isNotEmpty ? _patient.text : 'Clinical note',
      body: GlassCard(
        frosted: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(controller: _patient, label: 'Patient', hint: 'Patient name'),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(controller: _title, label: 'Title', hint: 'Report title'),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              controller: _body,
              label: 'Body',
              hint: 'Findings, recommendations, plan…',
              maxLines: 12,
              minLines: 8,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Save draft',
                    variant: AppButtonVariant.secondary,
                    icon: AppIcons.download,
                    onPressed: () => _save(publish: false),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton(
                    label: 'Publish',
                    icon: AppIcons.check,
                    onPressed: () => _save(publish: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
