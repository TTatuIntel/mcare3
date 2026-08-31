import 'package:flutter/material.dart';

import '../../core/api/report_consents_api.dart';
import '../../shared/services/document_opener.dart';
import '../../core/env/app_env.dart';
import '../../core/realtime/realtime_refresh_mixin.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/patient_report_request.dart';
import '../../shared/state/report_consents_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/dossier/dossier_blocks.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/section_label.dart';
import '../../admin/reports/report_reason_prompt.dart';
import '../../shared/widgets/loading/loading.dart';

/// Where a patient sees, and decides on, every request to share their record.
///
/// The point of the screen is informed consent: before approving, the patient
/// reads exactly which parts of their record would be disclosed, to whom, and
/// why. Declining is as prominent as approving, and nothing is shared unless
/// they say yes.
class PatientReportConsentsView extends StatefulWidget {
  const PatientReportConsentsView({super.key});

  @override
  State<PatientReportConsentsView> createState() =>
      _PatientReportConsentsViewState();
}

class _PatientReportConsentsViewState extends State<PatientReportConsentsView>
    with RealtimeRefreshMixin<PatientReportConsentsView> {
  List<PatientReportRequestItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    watchRealtime(const {'reports'}, _load);
    _load();
  }

  Future<void> _load() async {
    if (!AppEnv.backendEnabled) {
      setState(() {
        _loading = false;
        _items = const [];
      });
      return;
    }
    setState(() => _loading = true);
    try {
      // Refresh through the shared store, so the More badge and the home
      // prompt clear at the same moment this list does.
      await ReportConsentsState.instance.refresh();
      if (!mounted) return;
      setState(() {
        _items = ReportConsentsState.instance.requests;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final awaiting = _items.where((r) => r.awaitingMe).toList();
    final history = _items.where((r) => !r.awaitingMe).toList();

    return PatientScaffold(
      currentRoute: RouteNames.patientReportConsents,
      title: 'Sharing requests',
      subtitle: 'Approve or decline what is shared from your record',
      headerActions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _load,
          icon: const Icon(AppIcons.refresh),
        ),
      ],
      body: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: McareLoadingMark(size: McareMarkSize.small)),
            )
          : _items.isEmpty
          ? GlassCard(
              child: EmptyStateView(
                icon: AppIcons.lock,
                title: 'No sharing requests',
                message:
                    _error ??
                    'When mCare staff need to share part of your record, '
                        'the request appears here for your approval.',
                compact: true,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (awaiting.isNotEmpty) ...[
                  SectionLabel(
                    title: 'Needs your approval',
                    icon: AppIcons.lock,
                    trailing: '${awaiting.length}',
                  ),
                  for (final r in awaiting)
                    _ConsentCard(request: r, onChanged: _load, urgent: true),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (history.isNotEmpty) ...[
                  SectionLabel(
                    title: 'Past requests',
                    icon: AppIcons.audit,
                    trailing: '${history.length}',
                  ),
                  for (final r in history)
                    _ConsentCard(request: r, onChanged: _load),
                ],
              ],
            ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  const _ConsentCard({
    required this.request,
    required this.onChanged,
    this.urgent = false,
  });

  final PatientReportRequestItem request;
  final VoidCallback onChanged;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = urgent
        ? AppColors.warning
        : switch (request.status) {
            'issued' || 'signed' || 'consented' => AppColors.success,
            'declined' || 'revoked' || 'expired' => AppColors.critical,
            _ => AppColors.textMutedAA,
          };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: GlassCard(
        border: urgent
            ? Border.all(color: color.withValues(alpha: 0.45), width: 1.4)
            : null,
        onTap: () => PatientConsentDetailSheet.show(
          context,
          request: request,
          onChanged: onChanged,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                DossierPill(
                  label: urgent ? 'Action needed' : request.statusLabel,
                  color: color,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'For: ${request.purpose}'
              '${request.recipient == null ? '' : '  ·  To: ${request.recipient}'}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${request.sectionLabels.length} part'
              '${request.sectionLabels.length == 1 ? '' : 's'} of your record'
              '${request.requestedByName == null ? '' : ' · asked by ${request.requestedByName}'}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.textFaint(context),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The full disclosure statement plus the approve / decline decision.
class PatientConsentDetailSheet {
  PatientConsentDetailSheet._();

  static Future<void> show(
    BuildContext context, {
    required PatientReportRequestItem request,
    VoidCallback? onChanged,
  }) {
    return GlassSheet.show<void>(
      context,
      title: 'Sharing request',
      subtitle: request.title,
      maxWidth: 640,
      child: _ConsentDetailBody(request: request, onChanged: onChanged),
    );
  }
}

class _ConsentDetailBody extends StatefulWidget {
  const _ConsentDetailBody({required this.request, this.onChanged});

  final PatientReportRequestItem request;
  final VoidCallback? onChanged;

  @override
  State<_ConsentDetailBody> createState() => _ConsentDetailBodyState();
}

class _ConsentDetailBodyState extends State<_ConsentDetailBody> {
  bool _busy = false;
  bool _opening = false;

  /// Opens the finished report.
  ///
  /// Issuing froze the assembled report and told the patient it had gone out,
  /// but there was no way to read it — the person the report describes was the
  /// only party who could not see what had been disclosed about them. The page
  /// arrives as HTML so the platform's own viewer can print it or save it as
  /// PDF without this app carrying a PDF renderer.
  Future<void> _openReport() async {
    setState(() => _opening = true);
    try {
      final bytes = await ReportConsentsApi.instance.documentBytes(
        widget.request.id,
      );
      if (!mounted) return;
      final opened = await DocumentOpener.openBytes(
        bytes: bytes,
        mimeType: 'text/html',
        filename: DocumentOpener.filenameWith(widget.request.title, 'html'),
      );
      if (!mounted) return;
      setState(() => _opening = false);
      if (!opened) {
        AppToast.warn(context, 'Could not open the report.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _opening = false);
      AppToast.error(context, 'Could not open the report: $e');
    }
  }

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      await ReportConsentsApi.instance.approve(widget.request.id);
      if (!mounted) return;
      widget.onChanged?.call();
      Navigator.of(context, rootNavigator: true).pop();
      AppToast.success(context, 'Approved — thank you.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.error(context, 'Could not approve: $e');
    }
  }

  Future<void> _decline() async {
    final reason = await promptReason(
      context,
      title: 'Decline this request',
      message: 'You can say why, or leave it blank. Nothing will be shared.',
      label: 'Reason (optional)',
      confirmLabel: 'Decline',
    );
    // A blank reason is fine here, but promptReason returns null on cancel.
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ReportConsentsApi.instance.decline(
        widget.request.id,
        reason: reason,
      );
      if (!mounted) return;
      widget.onChanged?.call();
      Navigator.of(context, rootNavigator: true).pop();
      AppToast.info(context, 'Declined — nothing was shared.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.error(context, 'Could not decline: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.request;
    final decidable = r.awaitingMe;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(AppIcons.lock, size: 16, color: AppColors.info),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'You decide what is shared',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.info,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Only the parts listed below would be included. Nothing else '
                'from your record is shared, and nothing at all is shared '
                'unless you approve.',
                style: theme.textTheme.labelSmall?.copyWith(
                  height: 1.45,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DossierCard(
          title: 'The request',
          icon: AppIcons.report,
          children: [
            DossierRow(label: 'Purpose', value: r.purpose),
            DossierRow(label: 'Would be shared with', value: r.recipient),
            DossierRow(label: 'Asked by', value: r.requestedByName),
            DossierRow(
              label: 'Doctor signing',
              value: r.doctorName ?? 'Not required',
            ),
            DossierRow(
              label: 'Expires',
              value: r.consentExpiresAt == null
                  ? null
                  : '${dossierDateTime(r.consentExpiresAt)}'
                        '${r.consentExpired ? ' — expired' : ''}',
              valueColor: r.consentExpired ? AppColors.critical : null,
            ),
          ],
        ),
        DossierCard(
          title: 'What would be included',
          icon: AppIcons.catalog,
          trailing: '${r.sectionLabels.length}',
          emptyMessage: 'Nothing selected.',
          children: [
            for (final detail in r.sectionDetails)
              DossierRecordRow(
                icon: AppIcons.checkMark,
                iconColor: AppColors.info,
                title: '${detail['label'] ?? ''}',
                subtitle: '${detail['description'] ?? ''}',
              ),
            // Fall back to plain labels if the detail list is unavailable.
            if (r.sectionDetails.isEmpty)
              DossierChips(labels: r.sectionLabels, color: AppColors.info),
          ],
        ),
        if (r.consentedAt != null)
          DossierCard(
            title: 'Your decision',
            icon: AppIcons.check,
            children: [
              DossierRow(
                label: 'Approved',
                value: dossierDateTime(r.consentedAt),
                valueColor: AppColors.success,
                emphasise: true,
              ),
              DossierRow(
                label: 'Report issued',
                value: dossierDateTime(r.issuedAt) ?? 'Not yet',
              ),
            ],
          ),
        if (r.declinedAt != null)
          DossierCard(
            title: 'Your decision',
            icon: AppIcons.close,
            children: [
              DossierRow(
                label: 'Declined',
                value: dossierDateTime(r.declinedAt),
                valueColor: AppColors.critical,
                emphasise: true,
              ),
              DossierRow(label: 'Reason', value: r.declineReason),
            ],
          ),
        // A report the patient can read. Offered whenever there is a finished
        // copy — including a revoked one, which stays readable because it was
        // disclosed and they are entitled to see what went out.
        if (r.canOpenDocument) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Open the report',
            icon: AppIcons.document,
            expand: true,
            loading: _opening,
            onPressed: _opening ? null : _openReport,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Opens the copy that was issued. Use your browser or share sheet '
            'to print it or save it as a PDF.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontSize: 10,
              height: 1.4,
            ),
          ),
        ],
        if (decidable) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Approve sharing',
            icon: AppIcons.check,
            expand: true,
            loading: _busy,
            onPressed: _approve,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Decline',
            icon: AppIcons.close,
            variant: AppButtonVariant.danger,
            expand: true,
            onPressed: _busy ? null : _decline,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'You can also approve by entering the one-time code from your '
            'email, or by reading it back to mCare staff on a call.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontSize: 10,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}
