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

/// Build a patient report by ticking exactly the sections needed.
///
/// Confidentiality is the point of this screen: the admin includes the
/// minimum, and the backend decides from that selection whether the patient
/// must approve the disclosure (OTP or approval link) and whether a doctor
/// must sign it. Nothing is assembled until both gates clear — so a mis-tick
/// cannot leak a record, it just stalls until someone approves it.
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
      child: _BuilderBody(patientId: patientId, patientName: patientName),
    );
  }
}

class _BuilderBody extends StatefulWidget {
  const _BuilderBody({required this.patientId, required this.patientName});

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
  final Set<String> _selected = {};
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title.text = 'Medical report — ${widget.patientName}';
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
      setState(() {
        _loading = false;
        _error = 'Reports need the backend connection.';
      });
      return;
    }
    try {
      final rows = await AdminApi.instance.reportSections();
      if (!mounted) return;
      setState(() {
        _catalog = rows.map(ReportSectionOption.fromJson).toList();
        _loading = false;
        // Start from the least-disclosing default rather than everything.
        if (_selected.isEmpty && _catalog.isNotEmpty) {
          _selected.add(_catalog.first.key);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  bool get _needsConsent => _catalog
      .where((s) => _selected.contains(s.key))
      .any((s) => s.requiresConsent);

  bool get _needsSignature =>
      _catalog.where((s) => _selected.contains(s.key)).any((s) => s.clinical);

  Map<String, List<ReportSectionOption>> get _grouped {
    final out = <String, List<ReportSectionOption>>{};
    for (final s in _catalog) {
      out.putIfAbsent(s.group, () => []).add(s);
    }
    return out;
  }

  Future<void> _submit() async {
    if (_selected.isEmpty) {
      AppToast.error(context, 'Tick at least one section to include.');
      return;
    }
    if (_purpose.text.trim().length < 4) {
      AppToast.error(context, 'Say why the report is needed.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final data = await AdminApi.instance.createReportRequest(
        patientUserId: widget.patientId,
        sections: _selected.toList(),
        title: _title.text.trim().isEmpty
            ? 'Medical report — ${widget.patientName}'
            : _title.text.trim(),
        purpose: _purpose.text.trim(),
        recipient: _recipient.text.trim(),
      );
      if (!mounted) return;

      final item = data == null
          ? null
          : PatientReportRequestItem.fromJson(data);
      Navigator.of(context, rootNavigator: true).pop(item);

      if (item != null && item.consentRequired) {
        AppToast.success(
          context,
          'Approval request sent to ${widget.patientName}.',
        );
      } else {
        AppToast.success(context, 'Report request created.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppToast.error(context, 'Could not create report: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: McareLoadingMark(size: McareMarkSize.small)),
      );
    }
    if (_catalog.isEmpty) {
      return EmptyStateView(
        icon: AppIcons.alert,
        title: 'Report sections unavailable',
        message: _error ?? 'Could not load the section catalogue.',
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
          'Sections marked “Needs consent” are confidential. Including any of '
          'them asks ${widget.patientName} to approve the disclosure with a '
          'one-time code or approval link before the report is assembled.',
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
                    onChanged: (v) => setState(() {
                      if (v) {
                        _selected.add(option.key);
                      } else {
                        _selected.remove(option.key);
                      }
                    }),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.sm),
        _GateSummary(
          needsConsent: _needsConsent,
          needsSignature: _needsSignature,
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
                onPressed: () => setState(
                  () => _selected
                    ..clear()
                    ..addAll(_catalog.map((s) => s.key)),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                label: 'Clear',
                variant: AppButtonVariant.ghost,
                onPressed: () => setState(_selected.clear),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: _needsConsent
              ? 'Request patient approval'
              : 'Create report request',
          icon: _needsConsent ? AppIcons.lock : AppIcons.report,
          expand: true,
          loading: _submitting,
          onPressed: _selected.isEmpty ? null : _submit,
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
              onChanged: (v) => onChanged(v ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 7, bottom: 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                        if (option.requiresConsent)
                          const DossierPill(
                            label: 'Needs consent',
                            color: AppColors.warning,
                            icon: AppIcons.lock,
                          )
                        else
                          const DossierPill(
                            label: 'Open',
                            color: AppColors.success,
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

/// Spells out, before submission, exactly which approvals the current
/// selection will trigger — so the admin is never surprised by a stalled
/// request.
class _GateSummary extends StatelessWidget {
  const _GateSummary({
    required this.needsConsent,
    required this.needsSignature,
    required this.patientName,
    required this.empty,
  });

  final bool needsConsent;
  final bool needsSignature;
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
          border: Border.all(color: AppPalette.border(context)),
        ),
        child: Text(
          'Nothing selected — tick the sections this report should contain.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppPalette.textMuted(context),
          ),
        ),
      );
    }

    final color = needsConsent ? AppColors.warning : AppColors.success;
    final steps = <String>[
      if (needsConsent)
        '$patientName approves the disclosure (one-time code or approval link)'
      else
        'No patient consent needed — only open sections were selected',
      if (needsSignature)
        'A doctor reviews and signs the report'
      else
        'No doctor signature needed — no clinical sections were selected',
      'You issue the report; the patient is notified it went out',
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                needsConsent ? AppIcons.lock : AppIcons.check,
                size: 15,
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                needsConsent ? 'Approval required' : 'Ready to issue',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
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
