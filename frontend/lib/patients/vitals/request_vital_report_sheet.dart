import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/patient_chart_api.dart';
import '../../shared/models/vital.dart';
import '../../shared/models/vital_report_request.dart';
import '../../shared/state/vital_report_state.dart';
import '../../shared/state/vitals_state.dart';
import '../../shared/services/vital_report_export.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/document_preview_panel.dart';
import '../../shared/models/document.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/period_filter_bar.dart';
import '../../shared/widgets/section_label.dart';

class RequestVitalReportSheet {
  RequestVitalReportSheet._();

  static Future<void> show(BuildContext context) {
    return GlassSheet.show(
      context,
      title: 'Vital reports',
      subtitle: 'Request reports or view completed ones',
      child: const _ReportsHub(),
    );
  }
}

// ---------------------------------------------------------------------------
// Hub: fulfilled reports list + new request form
// ---------------------------------------------------------------------------

class _ReportsHub extends StatelessWidget {
  const _ReportsHub();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: VitalReportState.instance,
      builder: (context, _) {
        VitalReportState.instance.checkEscalations();
        final fulfilled = VitalReportState.instance.fulfilled;
        final pending = VitalReportState.instance.pending;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fulfilled.isNotEmpty) ...[
              SectionLabel(
                title: 'Completed reports',
                icon: AppIcons.check,
                trailing: '${fulfilled.length}',
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final r in fulfilled) ...[
                _FulfilledReportRow(request: r),
                const SizedBox(height: AppSpacing.xs),
              ],
              const SizedBox(height: AppSpacing.md),
            ],
            SectionLabel(
              title: 'New request',
              icon: AppIcons.report,
            ),
            const SizedBox(height: AppSpacing.xs),
            _RequestForm(pending: pending),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Fulfilled report row
// ---------------------------------------------------------------------------

class _FulfilledReportRow extends StatelessWidget {
  const _FulfilledReportRow({required this.request});
  final VitalReportRequest request;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.MMMd();
    final theme = Theme.of(context);
    return GlassCard(
      frosted: true,
      onTap: () => _showDetail(context, request),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: AppPalette.successSoft(context),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: const Icon(AppIcons.check, color: AppColors.success, size: 18),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${fmt.format(request.from)} – ${fmt.format(request.to)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'By ${request.respondedBy ?? 'Your doctor'}'
                  '${request.respondedAt != null ? ' · ${DateFormat.MMMd().format(request.respondedAt!)}' : ''}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
          Icon(AppIcons.chevronRight, size: 16, color: AppPalette.textMuted(context)),
        ],
      ),
    );
  }

  static void _showDetail(BuildContext context, VitalReportRequest request) {
    GlassSheet.show<void>(
      context,
      title: 'Report details',
      subtitle: 'Fulfilled vital report',
      child: _FulfilledReportDetail(request: request),
    );
  }
}

// ---------------------------------------------------------------------------
// Fulfilled report detail sheet body
// ---------------------------------------------------------------------------

class _FulfilledReportDetail extends StatelessWidget {
  const _FulfilledReportDetail({required this.request});
  final VitalReportRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat.yMMMd();
    final timeFmt = DateFormat.jm();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Status badge
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: AppPalette.successSoft(context),
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(AppIcons.check, size: 12, color: AppColors.success),
                  const SizedBox(width: 4),
                  Text(
                    'Report ready',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Meta card
        GlassCard(
          frosted: true,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MetaRow(
                label: 'Period',
                value: '${dateFmt.format(request.from)} – ${dateFmt.format(request.to)}',
              ),
              if (request.respondedBy != null)
                _MetaRow(label: 'Prepared by', value: request.respondedBy!),
              if (request.respondedAt != null)
                _MetaRow(
                  label: 'Completed',
                  value: '${dateFmt.format(request.respondedAt!)} at ${timeFmt.format(request.respondedAt!)}',
                ),
              if (request.note != null)
                _MetaRow(label: 'Your note', value: request.note!),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Vitals included
        Text(
          'Vitals included',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: request.vitals
              .map((v) => _VitalChip(vital: v))
              .toList(),
        ),
        const SizedBox(height: AppSpacing.md),

        // Doctor response note
        if (request.responseNote != null && request.responseNote!.isNotEmpty) ...[
          Text(
            'Doctor\'s notes',
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          GlassCard(
            frosted: true,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              request.responseNote!,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        const SizedBox(height: AppSpacing.md),

        Text(
          'Report preview',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        DocumentPreviewPanel(
          documentId: 'report-${request.id}',
          fileType: DocumentFileType.pdf,
          height: 240,
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Open in new tab',
          icon: Icons.open_in_new_rounded,
          variant: AppButtonVariant.ghost,
          expand: true,
          onPressed: () => VitalReportExport.openInNewTab(request),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _VitalChip extends StatelessWidget {
  const _VitalChip({required this.vital});
  final VitalKey vital;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: vital.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: vital.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(vital.icon, size: 12, color: vital.accent),
          const SizedBox(width: 4),
          Text(
            vital.shortLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: vital.accent,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// New request form
// ---------------------------------------------------------------------------

class _RequestForm extends StatefulWidget {
  const _RequestForm({required this.pending});
  final List<VitalReportRequest> pending;

  @override
  State<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends State<_RequestForm> {
  DateTime? _from;
  DateTime? _to;
  final _note = TextEditingController();
  bool _allTracked = true;
  final _selected = <VitalKey>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected.addAll(VitalsState.instance.tracked);
    final now = DateTime.now();
    _to = DateTime(now.year, now.month, now.day);
    _from = _to!.subtract(const Duration(days: 30));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final picked = await PeriodPickerSheet.show(
      context,
      current: _from != null && _to != null
          ? ChartPeriod.range(_from!, _to!)
          : ChartPeriod.month,
      title: 'Report period',
      subtitle: 'The readings the report is built from.',
    );
    if (picked == null || !mounted) return;
    final window = picked.resolve();
    setState(() {
      _from = window.from;
      _to = window.to;
    });
  }

  Future<void> _submit() async {
    if (_from == null || _to == null) {
      AppToast.info(context, 'Choose a date range first.');
      return;
    }
    final vitals = _allTracked
        ? VitalsState.instance.tracked.toList()
        : _selected.toList();
    if (vitals.isEmpty) {
      AppToast.info(context, 'Select at least one vital.');
      return;
    }

    setState(() => _saving = true);
    try {
      await VitalReportState.instance.requestReportRemote(
        from: _from!,
        to: _to!,
        vitals: vitals,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.warn(context, 'Could not request: $e');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.success(
      context,
      'Report request sent to your doctor. We\'ll escalate if they don\'t respond.',
    );
  }

  String _rangeLabel() {
    if (_from == null || _to == null) return 'Tap to choose dates';
    final fmt = DateFormat.MMMd();
    return '${fmt.format(_from!)} – ${fmt.format(_to!)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracked = VitalsState.instance.tracked.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _pickRange,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppPalette.surfaceMuted(context).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppPalette.border(context)),
            ),
            child: Row(
              children: [
                const Icon(AppIcons.calendar, color: AppColors.brandIndigo),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Date range',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _rangeLabel(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppPalette.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(AppIcons.chevronRight, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Vitals to include',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Its own Material: the sheet paints its glass background with a
        // DecoratedBox, and a ListTile renders its ink on the nearest Material
        // ancestor — which was above that box, so the tap ripple on this row
        // was drawn underneath the background and never seen.
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('All tracked vitals'),
            value: _allTracked,
            onChanged: (v) => setState(() => _allTracked = v),
          ),
        ),
        if (!_allTracked)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final v in tracked)
                FilterChip(
                  label: Text(v.shortLabel),
                  selected: _selected.contains(v),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _selected.add(v);
                    } else {
                      _selected.remove(v);
                    }
                  }),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Note (optional)',
          hint: 'e.g. For my cardiology follow-up',
          controller: _note,
          maxLines: 2,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Your doctor has 48 hours to respond. If they don\'t, your mCare assistant steps in, then care admin.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppPalette.textMuted(context),
            height: 1.35,
          ),
        ),
        if (widget.pending.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Pending requests',
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final r in widget.pending.take(3))
            _PendingRequestRow(request: r),
        ],
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Send request',
          icon: AppIcons.report,
          loading: _saving,
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}

class _PendingRequestRow extends StatelessWidget {
  const _PendingRequestRow({required this.request});

  final VitalReportRequest request;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.MMMd();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppPalette.warningSoft(context).withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(AppIcons.time, size: 16, color: AppColors.warning),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${fmt.format(request.from)} – ${fmt.format(request.to)} · waiting on ${request.responderLabel}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
