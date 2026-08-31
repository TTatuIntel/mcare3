import 'package:flutter/material.dart';

import '../../core/api/admin_api.dart';
import '../../core/env/app_env.dart';
import '../../shared/models/patient_report_request.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/dossier/dossier_blocks.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/loading/loading.dart';

/// Builds a patient report request.
///
/// Patient consent is NOT part of this flow.
/// The admin selects only the sections required for the report and chooses
/// a doctor from the patient's care team to review and sign the report.
///
/// Every report is sent to a doctor for review/signature first. After the
/// doctor signs, the report returns to the admin queue. The admin reviews
/// the signed report and explicitly approves/shares it with the patient.
/// Confidential sections are clearly identified, but they never trigger a
/// patient-consent step.
class PatientReportBuilderSheet {
  PatientReportBuilderSheet._();

  static Future<PatientReportRequestItem?> show(
    BuildContext context, {
    required String patientId,
    required String patientName,
  }) {
    return GlassSheet.show<PatientReportRequestItem>(
      context,
      title: 'Issue patient report',
      subtitle: patientName,
      maxWidth: 700,
      child: _BuilderBody(
        patientId: patientId,
        patientName: patientName,
      ),
    );
  }
}

class _BuilderBody extends StatefulWidget {
  const _BuilderBody({
    required this.patientId,
    required this.patientName,
  });

  final String patientId;
  final String patientName;

  @override
  State<_BuilderBody> createState() => _BuilderBodyState();
}

class _BuilderBodyState extends State<_BuilderBody> {
  final _title = TextEditingController();
  final _purpose = TextEditingController();
  final _recipient = TextEditingController();

  List<ReportSectionOption> _catalog = const [];
  List<Map<String, dynamic>> _signers = const [];

  final Set<String> _selected = <String>{};

  String? _doctorUserId;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title.text = 'Medical report — ${widget.patientName}';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _purpose.dispose();
    _recipient.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!AppEnv.backendEnabled) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Reports require the backend connection.';
      });
      return;
    }

    try {
      final rows = await AdminApi.instance.reportSections();
      final signerRows =
          await AdminApi.instance.reportSigners(widget.patientId);

      if (!mounted) return;

      final catalog = rows
          .map(ReportSectionOption.fromJson)
          .where((section) => section.key.trim().isNotEmpty)
          .toList();

      final validSigners = signerRows
          .where((signer) => signer['user_id'] != null)
          .map((signer) => Map<String, dynamic>.from(signer))
          .toList();

      setState(() {
        _catalog = catalog;
        _signers = validSigners;

        // Automatically choose the doctor only when there is exactly one
        // valid signer. Otherwise the admin must choose explicitly.
        _doctorUserId = validSigners.length == 1
            ? validSigners.first['user_id'].toString()
            : null;

        _loading = false;
        _error = null;

        // Least-disclosing default: start with one section, not all sections.
        if (_selected.isEmpty && _catalog.isNotEmpty) {
          _selected.add(_catalog.first.key);
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  bool get _hasConfidential {
    return _catalog
        .where((section) => _selected.contains(section.key))
        .any((section) => section.confidential);
  }

  Map<String, dynamic>? get _chosenDoctor {
    final selectedId = _doctorUserId;
    if (selectedId == null) return null;

    for (final signer in _signers) {
      if (signer['user_id']?.toString() == selectedId) {
        return signer;
      }
    }

    return null;
  }

  Map<String, List<ReportSectionOption>> get _grouped {
    final grouped = <String, List<ReportSectionOption>>{};

    for (final section in _catalog) {
      final group = section.group.trim().isEmpty ? 'Other' : section.group;
      grouped.putIfAbsent(group, () => <ReportSectionOption>[]).add(section);
    }

    return grouped;
  }

  Future<void> _submit() async {
    if (_submitting) return;

    if (_selected.isEmpty) {
      AppToast.error(context, 'Select at least one section to include.');
      return;
    }

    if (_purpose.text.trim().length < 4) {
      AppToast.error(context, 'Enter the purpose of the report.');
      return;
    }

    if (_doctorUserId == null) {
      AppToast.error(context, 'Choose the doctor who will sign this report.');
      return;
    }

    final selectedDoctor = _chosenDoctor;
    final selectedDoctorName =
        selectedDoctor?['name']?.toString().trim().isNotEmpty == true
            ? selectedDoctor!['name'].toString().trim()
            : 'the selected doctor';

    setState(() => _submitting = true);

    try {
      final data = await AdminApi.instance.createReportRequest(
        patientUserId: widget.patientId,
        sections: _selected.toList(),
        title: _title.text.trim().isEmpty
            ? 'Medical report — ${widget.patientName}'
            : _title.text.trim(),
        purpose: _purpose.text.trim(),
        doctorUserId: _doctorUserId!,
        recipient: _recipient.text.trim(),
      );

      if (!mounted) return;

      if (data == null) {
        setState(() => _submitting = false);
        AppToast.error(
          context,
          'The report request was not created. Please try again.',
        );
        return;
      }

      final item = PatientReportRequestItem.fromJson(data);

      // Capture a context owned by the root navigator before closing the sheet.
      final rootContext = Navigator.of(
        context,
        rootNavigator: true,
      ).context;

      Navigator.of(
        context,
        rootNavigator: true,
      ).pop(item);

      AppToast.success(
        rootContext,
        'Sent to Dr. $selectedDoctorName for review and signature.',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _submitting = false);
      AppToast.error(
        context,
        'Could not create report: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: McareLoadingMark(size: McareMarkSize.small),
        ),
      );
    }

    if (_catalog.isEmpty) {
      return EmptyStateView(
        icon: AppIcons.alert,
        title: 'Report sections unavailable',
        message: _error ?? 'Could not load the report section catalogue.',
        compact: true,
      );
    }

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Report title',
          controller: _title,
          prefixIcon: AppIcons.report,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Purpose',
          hint: 'e.g. Insurance claim, specialist referral',
          controller: _purpose,
          prefixIcon: AppIcons.info,
          maxLines: 2,
          minLines: 1,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Recipient (optional)',
          hint: 'Who will receive this report',
          controller: _recipient,
          prefixIcon: AppIcons.send,
        ),
        const SizedBox(height: AppSpacing.lg),

        Row(
          children: [
            Expanded(
              child: Text(
                'Include only what is needed',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${_selected.length} selected',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.xs),

        Text(
          'Confidential sections contain sensitive clinical or identifying '
          'information. Select only the information required for this report. '
          'The selected doctor will review exactly what is included before '
          'signing.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            fontSize: 10.5,
            height: 1.45,
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        for (final entry in _grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              bottom: AppSpacing.xs,
              top: AppSpacing.sm,
            ),
            child: Text(
              entry.key.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          GlassCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              children: [
                for (final option in entry.value)
                  _SectionTile(
                    option: option,
                    selected: _selected.contains(option.key),
                    onChanged: (selected) {
                      setState(() {
                        if (selected) {
                          _selected.add(option.key);
                        } else {
                          _selected.remove(option.key);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],

        const SizedBox(height: AppSpacing.sm),

        _SignerPicker(
          signers: _signers,
          selected: _doctorUserId,
          onSelect: (id) {
            setState(() => _doctorUserId = id);
          },
        ),

        const SizedBox(height: AppSpacing.sm),

        _GateSummary(
          hasConfidential: _hasConfidential,
          doctorName: _chosenDoctor?['name']?.toString(),
          patientName: widget.patientName,
          empty: _selected.isEmpty,
        ),

        const SizedBox(height: AppSpacing.md),

        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Select all',
                variant: AppButtonVariant.ghost,
                onPressed: _submitting
                    ? null
                    : () {
                        setState(() {
                          _selected
                            ..clear()
                            ..addAll(_catalog.map((section) => section.key));
                        });
                      },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                label: 'Clear',
                variant: AppButtonVariant.ghost,
                onPressed: _submitting
                    ? null
                    : () {
                        setState(_selected.clear);
                      },
              ),
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.sm),

        AppButton(
          label: 'Send to doctor for signature',
          icon: AppIcons.approval,
          expand: true,
          loading: _submitting,
          onPressed:
              _selected.isEmpty || _doctorUserId == null || _submitting
                  ? null
                  : _submit,
        ),
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.option,
    required this.selected,
    required this.onChanged,
  });

  final ReportSectionOption option;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => onChanged(!selected),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: selected,
              onChanged: (value) => onChanged(value ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(
                  top: 7,
                  bottom: 7,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            option.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),

                        // Patient consent is intentionally not shown or required.
                        if (option.confidential)
                          const DossierPill(
                            label: 'Confidential',
                            color: AppColors.warning,
                            icon: AppIcons.lock,
                          )
                        else
                          const DossierPill(
                            label: 'Standard',
                            color: AppColors.success,
                            icon: AppIcons.check,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.description,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontSize: 10,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignerPicker extends StatelessWidget {
  const _SignerPicker({
    required this.signers,
    required this.selected,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> signers;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (signers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: AppColors.warning.withValues(alpha: 0.24),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.medical_services_outlined,
              size: 18,
              color: AppColors.warning,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No doctor available',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Assign a doctor to this patient before creating the report.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final validSelected = signers.any(
      (signer) => signer['user_id']?.toString() == selected,
    )
        ? selected
        : null;

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.medical_services_outlined,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Doctor who will review and sign',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A doctor signature is required for every report.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            value: validSelected,
            isExpanded: true,
            decoration: InputDecoration(
              hintText: 'Select doctor',
              filled: true,
              fillColor: AppPalette.surfaceMuted(context),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                borderSide: BorderSide(
                  color: AppPalette.border(context),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                borderSide: BorderSide(
                  color: AppPalette.border(context),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 1.4,
                ),
              ),
            ),
            items: signers.map((signer) {
              final id = signer['user_id'].toString();
              final name = signer['name']?.toString().trim();
              final specialty = signer['specialty']?.toString().trim();

              final displayName =
                  name == null || name.isEmpty ? 'Doctor #$id' : name;

              final displayText =
                  specialty == null || specialty.isEmpty
                      ? displayName
                      : '$displayName — $specialty';

              return DropdownMenuItem<String>(
                value: id,
                child: Text(
                  displayText,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: onSelect,
          ),
        ],
      ),
    );
  }
}

/// Shows the exact route the report will take.
///
/// There is deliberately no patient-consent stage:
/// 1. Admin selects the required content.
/// 2. Doctor reviews and signs.
/// 3. Admin issues the report.
class _GateSummary extends StatelessWidget {
  const _GateSummary({
    required this.hasConfidential,
    required this.doctorName,
    required this.patientName,
    required this.empty,
  });

  final bool hasConfidential;
  final String? doctorName;
  final String patientName;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (empty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppPalette.surfaceMuted(context),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: AppPalette.border(context),
          ),
        ),
        child: Text(
          'Nothing selected — choose the sections this report should contain.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppPalette.textMuted(context),
          ),
        ),
      );
    }

    final color =
        hasConfidential ? AppColors.warning : AppColors.success;

    final signer = doctorName?.trim().isNotEmpty == true
        ? 'Dr. ${doctorName!.trim()}'
        : 'The selected doctor';

    final steps = <String>[
      '$signer reviews the selected report sections',
      '$signer signs the report',
      'The admin approves and shares the signed report with $patientName',
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: color.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasConfidential ? AppIcons.lock : AppIcons.check,
                size: 15,
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  hasConfidential
                      ? 'Confidential content selected'
                      : 'Ready for doctor review',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            hasConfidential
                ? 'No patient-consent step is required. The selected doctor '
                    'reviews and signs first; the admin then approves sharing.'
                : 'No patient-consent step is required. The report goes '
                    'directly to the selected doctor, then back to admin approval.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.ink(context),
                        fontSize: 10.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
