import 'package:flutter/material.dart';

import '../../admin/reports/patient_report_document_view.dart';
import '../../admin/reports/report_reason_prompt.dart';
import '../../core/api/doctor_api.dart';
import '../../core/env/app_env.dart';
import '../../shared/auth/auth_state.dart';
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
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/loading/loading.dart';

/// Reports nominated to this doctor for sign-off.
///
/// A report reaches this list only after the patient has consented, so the
/// doctor is never asked to pre-authorise a disclosure the patient has not
/// approved. Signing is done against the real assembled document, not a list
/// of section names.
class DoctorReportSignaturesList extends StatefulWidget {
  const DoctorReportSignaturesList({super.key});

  @override
  State<DoctorReportSignaturesList> createState() =>
      _DoctorReportSignaturesListState();
}

class _DoctorReportSignaturesListState
    extends State<DoctorReportSignaturesList> {
  List<PatientReportRequestItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
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
      final rows = await DoctorApi.instance.listReportRequests();
      if (!mounted) return;
      setState(() {
        _items = rows.map(PatientReportRequestItem.fromJson).toList();
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
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: McareLoadingMark(size: McareMarkSize.small)),
      );
    }

    if (_items.isEmpty) {
      return GlassCard(
        child: EmptyStateView(
          icon: AppIcons.approval,
          title: 'No reports awaiting signature',
          message: _error ??
              'Reports nominated to you appear here once the patient has '
                  'approved the disclosure.',
          compact: true,
        ),
      );
    }

    final pending = _items.where((r) => r.awaitingSignature).toList();
    final rest = _items.where((r) => !r.awaitingSignature).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending.isNotEmpty) ...[
          SectionLabel(
            title: 'Awaiting your signature',
            icon: AppIcons.approval,
            trailing: '${pending.length}',
          ),
          for (final r in pending)
            _ReportCard(request: r, onChanged: _load, highlight: true),
          const SizedBox(height: AppSpacing.md),
        ],
        if (rest.isNotEmpty) ...[
          SectionLabel(
            title: 'Other reports',
            icon: AppIcons.report,
            trailing: '${rest.length}',
          ),
          for (final r in rest) _ReportCard(request: r, onChanged: _load),
        ],
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.request,
    required this.onChanged,
    this.highlight = false,
  });

  final PatientReportRequestItem request;
  final VoidCallback onChanged;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlight ? AppColors.warning : AppColors.textMutedAA;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: GlassCard(
        border: highlight
            ? Border.all(color: color.withValues(alpha: 0.4), width: 1.4)
            : null,
        onTap: () => DoctorReportSignSheet.show(
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
                  label: request.statusLabel,
                  color: switch (request.status) {
                    'issued' || 'signed' => AppColors.success,
                    'declined' || 'revoked' || 'expired' => AppColors.critical,
                    _ => AppColors.warning,
                  },
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                request.patientName,
                request.purpose,
              ].whereType<String>().join(' · '),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${request.sectionLabels.length} section'
              '${request.sectionLabels.length == 1 ? '' : 's'} · '
              'requested by ${request.requestedByName ?? 'staff'}',
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

/// Review the assembled document, then sign it or refuse with a reason.
class DoctorReportSignSheet {
  DoctorReportSignSheet._();

  static Future<void> show(
    BuildContext context, {
    required PatientReportRequestItem request,
    VoidCallback? onChanged,
  }) {
    return GlassSheet.show<void>(
      context,
      title: request.title,
      subtitle: request.patientName ?? 'Patient report',
      maxWidth: 700,
      child: _SignBody(request: request, onChanged: onChanged),
    );
  }
}

class _SignBody extends StatefulWidget {
  const _SignBody({required this.request, this.onChanged});

  final PatientReportRequestItem request;
  final VoidCallback? onChanged;

  @override
  State<_SignBody> createState() => _SignBodyState();
}

class _SignBodyState extends State<_SignBody> {
  late final TextEditingController _signature = TextEditingController(
    text: _defaultSignature(),
  );
  final _note = TextEditingController();
  bool _busy = false;

  String _defaultSignature() {
    final user = AuthState.instance.user;
    if (user == null) return '';
    final name = user.fullName.trim();
    if (name.isEmpty) return '';
    // License number on the signature line is what makes it a real sign-off.
    final license = user.licenseNumber?.trim();
    return license == null || license.isEmpty
        ? 'Dr. $name'
        : 'Dr. $name ($license)';
  }

  @override
  void dispose() {
    _signature.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _preview() async {
    setState(() => _busy = true);
    try {
      final data =
          await DoctorApi.instance.previewReportRequest(widget.request.id);
      final doc = data?['document'];
      if (!mounted) return;
      if (doc is! Map) {
        AppToast.info(context, 'Nothing to preview yet.');
        return;
      }
      await PatientReportDocumentView.show(
        context,
        document: PatientReportDocument.fromJson(doc.cast<String, dynamic>()),
      );
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not load preview: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sign() async {
    if (_signature.text.trim().length < 2) {
      AppToast.error(context, 'Enter the name to sign with.');
      return;
    }
    setState(() => _busy = true);
    try {
      await DoctorApi.instance.signReportRequest(
        widget.request.id,
        signatureName: _signature.text.trim(),
        note: _note.text.trim(),
      );
      if (!mounted) return;
      widget.onChanged?.call();
      Navigator.of(context, rootNavigator: true).pop();
      AppToast.success(context, 'Report signed.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.error(context, 'Could not sign: $e');
    }
  }

  Future<void> _decline() async {
    final reason = await promptReason(
      context,
      title: 'Decline to sign',
      message: 'Say why — the requesting admin sees this reason.',
      confirmLabel: 'Decline',
    );
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await DoctorApi.instance
          .declineReportRequest(widget.request.id, reason: reason);
      if (!mounted) return;
      widget.onChanged?.call();
      Navigator.of(context, rootNavigator: true).pop();
      AppToast.info(context, 'Signature declined.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.error(context, 'Could not decline: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final canSign = r.awaitingSignature;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DossierCard(
          title: 'What you are signing',
          icon: AppIcons.report,
          children: [
            DossierRow(label: 'Patient', value: r.patientName),
            DossierRow(label: 'Patient ID', value: r.patientUniqueId),
            DossierRow(label: 'Purpose', value: r.purpose),
            DossierRow(label: 'Recipient', value: r.recipient),
            DossierRow(label: 'Requested by', value: r.requestedByName),
            DossierRow(
              label: 'Patient consent',
              value: r.consentedAt == null
                  ? 'Not granted'
                  : '${dossierDateTime(r.consentedAt)} '
                      '(${dossierHumanize(r.consentMethod)})',
              valueColor:
                  r.consentedAt == null ? AppColors.critical : AppColors.success,
              emphasise: true,
            ),
          ],
        ),
        DossierCard(
          title: 'Sections disclosed',
          icon: AppIcons.catalog,
          trailing: '${r.sectionLabels.length}',
          children: [
            DossierChips(
              labels: r.sectionLabels,
              color: AppColors.brandIndigo,
            ),
          ],
        ),
        AppButton(
          label: 'Preview full document',
          icon: AppIcons.visibility,
          variant: AppButtonVariant.secondary,
          expand: true,
          onPressed: _busy ? null : _preview,
        ),
        if (canSign) ...[
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Sign as',
            controller: _signature,
            prefixIcon: AppIcons.edit,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: 'Note (optional)',
            hint: 'e.g. Reviewed against the chart; accurate as of today.',
            controller: _note,
            prefixIcon: AppIcons.info,
            maxLines: 3,
            minLines: 2,
            maxLength: 280,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Sign report',
            icon: AppIcons.approval,
            expand: true,
            loading: _busy,
            onPressed: _sign,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Decline to sign',
            icon: AppIcons.close,
            variant: AppButtonVariant.danger,
            expand: true,
            onPressed: _busy ? null : _decline,
          ),
        ] else if (r.signedAt != null) ...[
          const SizedBox(height: AppSpacing.sm),
          DossierCard(
            title: 'Signature on file',
            icon: AppIcons.approval,
            children: [
              DossierRow(label: 'Signed by', value: r.signatureName),
              DossierRow(
                label: 'Signed at',
                value: dossierDateTime(r.signedAt),
              ),
              DossierRow(label: 'Note', value: r.signatureNote),
              DossierRow(
                label: 'Issued',
                value: dossierDateTime(r.issuedAt) ?? 'Not yet issued',
              ),
            ],
          ),
        ],
      ],
    );
  }
}
