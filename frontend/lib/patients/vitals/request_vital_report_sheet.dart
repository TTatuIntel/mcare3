import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/patient_chart_api.dart';
import '../../shared/models/vital.dart';
import '../../shared/models/vital_report_request.dart';
import '../../shared/state/documents_state.dart';
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
import '../../shared/widgets/request_activity_trail.dart';
import '../../shared/widgets/section_label.dart';
import '../documents/document_viewer_sheet.dart';

class RequestVitalReportSheet {
  RequestVitalReportSheet._();

  static Future<void> show(
    BuildContext context, {
    ChartPeriod initialPeriod = ChartPeriod.threeWeeks,
    Set<VitalKey>? initialVitals,
  }) {
    return GlassSheet.show(
      context,
      title: 'Vital reports',
      subtitle: 'Request reports or view completed ones',
      child: _ReportsHub(
        initialPeriod: initialPeriod,
        initialVitals: initialVitals,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hub: fulfilled reports list + new request form
// ---------------------------------------------------------------------------

class _ReportsHub extends StatelessWidget {
  const _ReportsHub({required this.initialPeriod, this.initialVitals});

  final ChartPeriod initialPeriod;
  final Set<VitalKey>? initialVitals;

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
            // What is already moving comes first. A patient opening this sheet
            // with a request outstanding came to check on it, not to raise a
            // second one — and a form at the top is an invitation to do
            // exactly that.
            if (pending.isNotEmpty) ...[
              SectionLabel(
                title: 'In progress',
                icon: AppIcons.time,
                trailing: '${pending.length}',
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final r in pending) ...[
                _OpenRequestRow(request: r),
                const SizedBox(height: AppSpacing.xs),
              ],
              const SizedBox(height: AppSpacing.md),
            ],
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
            SectionLabel(title: 'New request', icon: AppIcons.report),
            const SizedBox(height: AppSpacing.xs),
            _RequestForm(
              initialPeriod: initialPeriod,
              initialVitals: initialVitals,
            ),
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
            child: const Icon(
              AppIcons.check,
              color: AppColors.success,
              size: 18,
            ),
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
                  'By ${request.respondedBy ?? 'your care team'}'
                  '${request.respondedAt != null ? ' · ${DateFormat.MMMd().format(request.respondedAt!)}' : ''}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            AppIcons.chevronRight,
            size: 16,
            color: AppPalette.textMuted(context),
          ),
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
                  const Icon(
                    AppIcons.check,
                    size: 12,
                    color: AppColors.success,
                  ),
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
                value:
                    '${dateFmt.format(request.from)} – ${dateFmt.format(request.to)}',
              ),
              if (request.respondedBy != null)
                _MetaRow(label: 'Prepared by', value: request.respondedBy!),
              if (request.respondedAt != null)
                _MetaRow(
                  label: 'Completed',
                  value:
                      '${dateFmt.format(request.respondedAt!)} at ${timeFmt.format(request.respondedAt!)}',
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
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: request.vitals.map((v) => _VitalChip(vital: v)).toList(),
        ),
        const SizedBox(height: AppSpacing.md),

        // Who touched it and when. The same trail the care team reads.
        Text(
          'What happened',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        RequestActivityTrail(events: request.events),
        const SizedBox(height: AppSpacing.md),

        // Doctor response note
        if (request.responseNote != null &&
            request.responseNote!.isNotEmpty) ...[
          Text(
            'Clinical notes',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
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

        // The filed report. It is rendered once, on the server, from the
        // readings inside the window — so what the patient opens next year is
        // what the clinician signed off today, rather than a fresh derivation
        // from a record that has moved on.
        if (_filedDocument(request) != null) ...[
          Text(
            'Report preview',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          DocumentPreviewPanel(
            documentId: request.documentId!,
            fileType: _filedDocument(request)!.fileType,
            height: 240,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Open in Documents',
            icon: AppIcons.document,
            expand: true,
            onPressed: () {
              Navigator.of(context).pop();
              DocumentViewerSheet.show(context, _filedDocument(request)!);
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Filed under Documents · Vital report.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          ),
        ] else
          // Reports issued before the server started filing them, and the rare
          // case where rendering failed. The locally built printable is the
          // fallback rather than the main path.
          AppButton(
            label: 'Open printable summary',
            icon: Icons.open_in_new_rounded,
            variant: AppButtonVariant.ghost,
            expand: true,
            onPressed: () => VitalReportExport.openInNewTab(request),
          ),
      ],
    );
  }

  /// The filed report, if the documents list has caught up with the request.
  static MedicalDocument? _filedDocument(VitalReportRequest request) {
    if (request.documentId == null) return null;
    for (final d in DocumentsState.instance.all) {
      if (d.id == request.documentId) return d;
    }
    return null;
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
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
  const _RequestForm({required this.initialPeriod, this.initialVitals});
  final ChartPeriod initialPeriod;
  final Set<VitalKey>? initialVitals;

  @override
  State<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends State<_RequestForm> {
  DateTime? _from;
  DateTime? _to;
  final _note = TextEditingController();
  late bool _allTracked;
  final _selected = <VitalKey>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _allTracked = widget.initialVitals == null;
    _selected.addAll(widget.initialVitals ?? VitalsState.instance.tracked);
    final window = widget.initialPeriod.resolve();
    _from = window.from;
    _to = window.to;
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
          : ChartPeriod.threeWeeks,
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
      'Sent to your care team. You will see who picks it up.',
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
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('All tracked vitals'),
          value: _allTracked,
          onChanged: (v) => setState(() => _allTracked = v),
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
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.brandIndigo.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Row(
            children: [
              const Icon(
                AppIcons.trend,
                color: AppColors.brandIndigo,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Average, lowest, highest, in-range percentage and trend '
                  'charts are included automatically.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
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
          'Anyone on your care team can pick this up. If nobody does within '
          '48 hours it goes to your mCare assistant, then to care admin.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppPalette.textMuted(context),
            height: 1.35,
          ),
        ),
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

/// An open request, with the one fact a status chip never carried: whether
/// anyone has actually picked it up.
class _OpenRequestRow extends StatelessWidget {
  const _OpenRequestRow({required this.request});

  final VitalReportRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat.MMMd();
    final status = request.status;

    return GlassCard(
      frosted: true,
      onTap: () => GlassSheet.show<void>(
        context,
        title: 'Report request',
        subtitle: '${fmt.format(request.from)} – ${fmt.format(request.to)}',
        child: _OpenRequestDetail(request: request),
      ),
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
              color: status.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(status.icon, color: status.color, size: 18),
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
                  request.statusLine,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            AppIcons.chevronRight,
            size: 16,
            color: AppPalette.textMuted(context),
          ),
        ],
      ),
    );
  }
}

class _OpenRequestDetail extends StatelessWidget {
  const _OpenRequestDetail({required this.request});

  final VitalReportRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat.yMMMd();
    final status = request.status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: status.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: status.color.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(status.icon, size: 18, color: status.color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: status.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      request.statusLine,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        GlassCard(
          frosted: true,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MetaRow(
                label: 'Period',
                value:
                    '${dateFmt.format(request.from)} – '
                    '${dateFmt.format(request.to)}',
              ),
              _MetaRow(
                label: 'Requested',
                value: dateFmt.format(request.createdAt),
              ),
              if (request.note != null && request.note!.isNotEmpty)
                _MetaRow(label: 'Your note', value: request.note!),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        Text(
          'Vitals included',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: request.vitals.map((v) => _VitalChip(vital: v)).toList(),
        ),
        const SizedBox(height: AppSpacing.md),

        Text(
          'What has happened',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        RequestActivityTrail(
          events: request.events,
          emptyMessage: 'Nobody on your care team has opened this yet.',
        ),

        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Cancel request',
          icon: AppIcons.close,
          variant: AppButtonVariant.ghost,
          expand: true,
          onPressed: () => _cancel(context),
        ),
      ],
    );
  }

  Future<void> _cancel(BuildContext context) async {
    final navigator = Navigator.of(context);
    try {
      await VitalReportState.instance.cancelRemote(request.id);
    } catch (e) {
      if (!context.mounted) return;
      AppToast.warn(context, 'Could not cancel: $e');
      return;
    }
    if (!context.mounted) return;
    navigator.pop();
    AppToast.success(context, 'Request cancelled.');
  }
}
