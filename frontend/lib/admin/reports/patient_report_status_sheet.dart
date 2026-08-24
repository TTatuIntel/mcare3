import 'package:flutter/material.dart';

import '../../core/api/admin_api.dart';
import '../../shared/models/patient_report_request.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/dossier/dossier_blocks.dart';
import '../../shared/widgets/glass_sheet.dart';
import 'patient_report_document_view.dart';
import 'report_reason_prompt.dart';

/// Track one report request through consent → signature → issue.
///
/// The admin can read a phone-dictated approval code back in here, resend the
/// challenge, issue once both gates clear, or revoke the whole request. Each
/// action is refused server-side if the corresponding gate is not satisfied,
/// so the UI can present them without gating logic of its own.
class PatientReportStatusSheet {
  PatientReportStatusSheet._();

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
      child: _StatusBody(initial: request, onChanged: onChanged),
    );
  }
}

class _StatusBody extends StatefulWidget {
  const _StatusBody({required this.initial, this.onChanged});

  final PatientReportRequestItem initial;
  final VoidCallback? onChanged;

  @override
  State<_StatusBody> createState() => _StatusBodyState();
}

class _StatusBodyState extends State<_StatusBody> {
  late PatientReportRequestItem _request = widget.initial;
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _apply(Map<String, dynamic>? data) {
    if (data == null) return;
    setState(() => _request = PatientReportRequestItem.fromJson(data));
    widget.onChanged?.call();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) AppToast.error(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() => _run(() async {
        final code = _code.text.trim();
        if (code.length < 4) {
          AppToast.error(context, 'Enter the code the patient read back.');
          return;
        }
        _apply(await AdminApi.instance
            .verifyReportConsent(_request.id, code: code));
        if (!mounted) return;
        _code.clear();
        AppToast.success(context, 'Patient consent recorded.');
      });

  Future<void> _resend() => _run(() async {
        _apply(await AdminApi.instance.resendReportConsent(_request.id));
        if (!mounted) return;
        AppToast.success(
          context,
          'A new code and approval link were sent to the patient.',
        );
      });

  Future<void> _issue() => _run(() async {
        final data = await AdminApi.instance.issueReport(_request.id);
        if (data == null || !mounted) return;
        _apply((data['report_request'] as Map?)?.cast<String, dynamic>());
        final doc = data['document'];
        AppToast.success(context, 'Report issued.');
        if (doc is Map && mounted) {
          await PatientReportDocumentView.show(
            context,
            document:
                PatientReportDocument.fromJson(doc.cast<String, dynamic>()),
          );
        }
      });

  Future<void> _revoke() => _run(() async {
        final reason = await promptReason(
          context,
          title: 'Revoke report request',
          message: 'Say why — the reason is recorded in the audit trail.',
          confirmLabel: 'Revoke',
        );
        if (reason == null || reason.trim().length < 4) return;
        _apply(await AdminApi.instance
            .revokeReportRequest(_request.id, reason: reason.trim()));
        if (!mounted) return;
        AppToast.info(context, 'Report request revoked.');
      });

  Future<void> _viewDocument() => _run(() async {
        final data = await AdminApi.instance.reportRequest(_request.id);
        final doc = data?['document'];
        if (doc is! Map || !mounted) {
          if (mounted) AppToast.info(context, 'No issued document to show.');
          return;
        }
        await PatientReportDocumentView.show(
          context,
          document:
              PatientReportDocument.fromJson(doc.cast<String, dynamic>()),
        );
      });

  @override
  Widget build(BuildContext context) {
    final r = _request;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusBanner(request: r),
        const SizedBox(height: AppSpacing.md),
        DossierCard(
          title: 'Request',
          icon: AppIcons.report,
          children: [
            DossierRow(label: 'Patient', value: r.patientName),
            DossierRow(label: 'Patient ID', value: r.patientUniqueId),
            DossierRow(label: 'Purpose', value: r.purpose),
            DossierRow(label: 'Recipient', value: r.recipient),
            DossierRow(label: 'Requested by', value: r.requestedByName),
            DossierRow(label: 'Created', value: dossierDate(r.createdAt)),
          ],
        ),
        DossierCard(
          title: 'Sections included',
          icon: AppIcons.catalog,
          trailing: '${r.sectionLabels.length}',
          emptyMessage: 'No sections selected.',
          children: [
            DossierChips(
              labels: r.sectionLabels,
              color: AppColors.brandIndigo,
            ),
          ],
        ),
        DossierCard(
          title: 'Patient consent',
          icon: AppIcons.lock,
          children: [
            DossierRow(
              label: 'Required',
              value: r.consentRequired ? 'Yes' : 'No — open sections only',
            ),
            if (r.consentRequired) ...[
              DossierRow(
                label: 'Granted',
                value: r.consentedAt == null
                    ? 'Not yet'
                    : '${dossierDateTime(r.consentedAt)} '
                        '(${dossierHumanize(r.consentMethod)})',
                valueColor: r.consentedAt == null
                    ? AppColors.warning
                    : AppColors.success,
                emphasise: r.consentedAt != null,
              ),
              DossierRow(
                label: 'Code sent',
                value: dossierDateTime(r.consentSentAt),
              ),
              DossierRow(
                label: 'Expires',
                value: r.consentExpiresAt == null
                    ? null
                    : '${dossierDateTime(r.consentExpiresAt)}'
                        '${r.consentExpired ? ' — expired' : ''}',
                valueColor: r.consentExpired ? AppColors.critical : null,
              ),
              if (r.consentAttempts > 0)
                DossierRow(
                  label: 'Failed attempts',
                  value: '${r.consentAttempts}',
                  valueColor: AppColors.warning,
                ),
              if (r.declinedAt != null)
                DossierRow(
                  label: 'Declined',
                  value: [
                    dossierDateTime(r.declinedAt),
                    r.declineReason,
                  ].whereType<String>().join(' — '),
                  valueColor: AppColors.critical,
                  emphasise: true,
                ),
            ],
          ],
        ),
        DossierCard(
          title: 'Doctor signature',
          icon: AppIcons.approval,
          children: [
            DossierRow(
              label: 'Required',
              value:
                  r.signatureRequired ? 'Yes' : 'No — no clinical sections',
            ),
            DossierRow(label: 'Nominated', value: r.doctorName),
            if (r.signatureRequired)
              DossierRow(
                label: 'Signed',
                value: r.signedAt == null
                    ? 'Not yet'
                    : '${dossierDateTime(r.signedAt)} — ${r.signatureName}',
                valueColor: r.signedAt == null
                    ? AppColors.warning
                    : AppColors.success,
                emphasise: r.signedAt != null,
              ),
            if (r.signatureNote != null)
              DossierRow(label: 'Note', value: r.signatureNote),
          ],
        ),
        if (r.awaitingConsent && !r.isClosed) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'If the patient reads their code back over the phone, enter it '
            'here. Otherwise they can approve from the app or the emailed '
            'link.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                  fontSize: 10.5,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: 'Approval code from patient',
            controller: _code,
            prefixIcon: AppIcons.lock,
            keyboardType: TextInputType.number,
            maxLength: 6,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Confirm consent',
            icon: AppIcons.check,
            expand: true,
            loading: _busy,
            onPressed: _verify,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Resend code & link',
            icon: AppIcons.send,
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: _busy ? null : _resend,
          ),
        ],
        if (r.awaitingSignature) ...[
          const SizedBox(height: AppSpacing.sm),
          _WaitingNotice(
            icon: AppIcons.approval,
            message: r.doctorName == null
                ? 'Waiting on a doctor signature, but no doctor is nominated. '
                    'Assign this patient to a doctor first.'
                : 'Waiting on Dr. ${r.doctorName} to review and sign. They '
                    'have been notified.',
            color: r.doctorName == null
                ? AppColors.critical
                : AppColors.warning,
          ),
        ],
        if (r.readyToIssue) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Issue report',
            icon: AppIcons.report,
            expand: true,
            loading: _busy,
            onPressed: _issue,
          ),
        ],
        if (r.isIssued) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'View issued report',
            icon: AppIcons.document,
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: _busy ? null : _viewDocument,
          ),
        ],
        if (!r.isClosed) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Revoke request',
            icon: AppIcons.close,
            variant: AppButtonVariant.danger,
            expand: true,
            onPressed: _busy ? null : _revoke,
          ),
        ],
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.request});
  final PatientReportRequestItem request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (request.status) {
      'issued' || 'signed' || 'consented' => AppColors.success,
      'declined' || 'revoked' || 'expired' => AppColors.critical,
      _ => AppColors.warning,
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Row(
        children: [
          Icon(
            switch (request.status) {
              'issued' => AppIcons.check,
              'declined' || 'revoked' || 'expired' => AppIcons.close,
              _ => AppIcons.time,
            },
            size: 20,
            color: color,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.statusLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  switch (request.blockedOn) {
                    'patient_consent' =>
                      'Nothing is assembled until the patient approves.',
                    'doctor_signature' =>
                      'Consent granted — a doctor must sign before issue.',
                    'issue' => 'All approvals in place. Ready to issue.',
                    _ => request.issuedAt != null
                        ? 'Issued ${dossierDate(request.issuedAt)}'
                        : request.revokeReason ??
                            request.declineReason ??
                            'This request is closed.',
                  },
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontSize: 10.5,
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
}

class _WaitingNotice extends StatelessWidget {
  const _WaitingNotice({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10.5,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
