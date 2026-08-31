import 'package:flutter/material.dart';

import '../../core/api/admin_api.dart';
import '../../shared/models/patient_report_request.dart';
import '../../shared/services/document_opener.dart';
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
/// challenge, and once a doctor has signed, decide what happens to the report:
/// read it, issue it, send it back for a correction, or remove the request.
/// Each action is refused server-side if the corresponding gate is not
/// satisfied, so the UI can present them without gating logic of its own.
///
/// The review block is deliberately the loudest thing on the sheet once a
/// signature lands. Issuing is the moment a patient's record leaves mCare, and
/// it used to be a single unlabelled button under a list of section names the
/// admin had ticked days earlier — nothing on the screen showed what was about
/// to be disclosed.
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
    _apply(
      await AdminApi.instance.verifyReportConsent(_request.id, code: code),
    );
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

  /// Approve the disclosure. Issuing is what puts the copy in the patient's
  /// documents, so the confirmation says so rather than leaving the admin to
  /// wonder whether a second step is needed.
  Future<void> _issue() => _run(() async {
    final ok = await _confirmIssue();
    if (ok != true || !mounted) return;

    final data = await AdminApi.instance.issueReport(_request.id);
    if (data == null || !mounted) return;
    _apply((data['report_request'] as Map?)?.cast<String, dynamic>());
    final doc = data['document'];
    AppToast.success(
      context,
      'Report issued. A copy is now in the patient’s documents.',
    );
    if (doc is Map && mounted) {
      await PatientReportDocumentView.show(
        context,
        document: PatientReportDocument.fromJson(doc.cast<String, dynamic>()),
      );
    }
  });

  Future<bool?> _confirmIssue() {
    final r = _request;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Issue this report?'),
        content: Text(
          'This discloses '
          '${r.sectionLabels.length} section'
          '${r.sectionLabels.length == 1 ? '' : 's'} of '
          '${r.patientName ?? 'the patient'}’s record'
          '${r.recipient == null ? '' : ' to ${r.recipient}'}.\n\n'
          'A copy goes into their documents immediately and cannot be '
          'deleted afterwards — only revoked, which leaves a trace.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Issue report'),
          ),
        ],
      ),
    );
  }

  /// Back to the doctor for a correction, keeping the patient's consent.
  Future<void> _sendBack() => _run(() async {
    final note = await promptReason(
      context,
      title: 'Send back to the doctor',
      message:
          'Say what needs changing. Dr. ${_request.doctorName ?? 'the signer'} '
          'sees this, their signature is cleared, and the patient’s approval '
          'is kept — they will not be asked again.',
      label: 'What needs changing',
      confirmLabel: 'Send back',
    );
    if (note == null || note.trim().length < 4) return;
    _apply(
      await AdminApi.instance.sendReportBack(_request.id, note: note.trim()),
    );
    if (!mounted) return;
    AppToast.info(context, 'Sent back to the doctor for changes.');
  });

  /// Remove the request, or withdraw a report that has already gone out. The
  /// row itself is never deleted — a consent ledger that forgets what was
  /// asked for answers nothing.
  Future<void> _revoke() => _run(() async {
    final issued = _request.isIssued;
    final reason = await promptReason(
      context,
      title: issued ? 'Revoke issued report' : 'Remove this report',
      message: issued
          ? 'The patient is told, and their copy is marked as revoked. The '
                'reason is recorded in the audit trail.'
          : 'Nothing has been disclosed, so nothing is withdrawn — the request '
                'is closed and kept in the audit trail with your reason.',
      confirmLabel: issued ? 'Revoke' : 'Remove',
    );
    if (reason == null || reason.trim().length < 4) return;
    _apply(
      await AdminApi.instance.revokeReportRequest(
        _request.id,
        reason: reason.trim(),
      ),
    );
    if (!mounted) return;
    AppToast.info(
      context,
      issued ? 'Report revoked.' : 'Report request removed.',
    );
  });

  /// Read the report itself — the draft before issue, the frozen snapshot
  /// after. Reviewing a document you cannot see is not a review.
  Future<void> _viewDocument() => _run(() async {
    final data = await AdminApi.instance.reportRequest(_request.id);
    final doc = data?['document'];
    if (doc is! Map || !mounted) {
      if (mounted) {
        AppToast.info(
          context,
          'There is nothing to read yet — the patient has not approved this '
          'disclosure.',
        );
      }
      return;
    }
    await PatientReportDocumentView.show(
      context,
      document: PatientReportDocument.fromJson(doc.cast<String, dynamic>()),
    );
  });

  /// Hands staff the report as a file — the thing they actually need once a
  /// doctor has signed, to send to the recipient it was prepared for.
  /// Viewing it on screen was never the same as having a copy.
  Future<void> _sendDocument() => _run(() async {
    final bytes = await AdminApi.instance.reportDocumentBytes(_request.id);
    if (!mounted) return;
    final opened = await DocumentOpener.openBytes(
      bytes: bytes,
      mimeType: 'text/html',
      filename: DocumentOpener.filenameWith(_request.title, 'html'),
    );
    if (!mounted) return;
    if (!opened) {
      AppToast.warn(context, 'Could not open the report file.');
    }
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
            DossierChips(labels: r.sectionLabels, color: AppColors.brandIndigo),
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
              value: r.signatureRequired ? 'Yes' : 'No — no clinical sections',
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
            if (r.returnCount > 0)
              DossierRow(
                label: 'Sent back',
                value: r.returnCount == 1
                    ? 'Once'
                    : '${r.returnCount} times',
                valueColor: AppColors.warning,
              ),
            if (r.awaitingRework) ...[
              DossierRow(
                label: 'Returned',
                value: [
                  dossierDateTime(r.returnedAt),
                  r.returnedByName,
                ].whereType<String>().join(' — '),
                valueColor: AppColors.warning,
                emphasise: true,
              ),
              DossierRow(label: 'Asked to change', value: r.returnNote),
            ],
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
                : r.awaitingRework
                ? 'You sent this back to Dr. ${r.doctorName}. Their signature '
                      'was cleared and they have been asked to correct it. The '
                      'patient’s approval still stands.'
                : 'Waiting on Dr. ${r.doctorName} to review and sign. They '
                      'have been notified.',
            color: r.doctorName == null
                ? AppColors.critical
                : AppColors.warning,
          ),
        ],
        if (r.awaitingIssueDecision) ...[
          const SizedBox(height: AppSpacing.md),
          _ReviewPanel(request: r),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Read the signed report',
            icon: AppIcons.document,
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: _busy ? null : _viewDocument,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Approve & issue to patient',
            icon: AppIcons.check,
            expand: true,
            loading: _busy,
            onPressed: _issue,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Send back to the doctor',
            icon: AppIcons.refresh,
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: _busy ? null : _sendBack,
          ),
        ] else if (r.readyToIssue) ...[
          // Signature was never required — no review step, but the admin can
          // still read what they are about to disclose.
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Read the report first',
            icon: AppIcons.document,
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: _busy ? null : _viewDocument,
          ),
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
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Save or send the file',
            icon: AppIcons.download,
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: _busy ? null : _sendDocument,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The patient already has this copy in their documents, and neither '
            'you nor a doctor can delete it. Print it or save it as a PDF to '
            'send it on.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontSize: 10,
              height: 1.4,
            ),
          ),
        ],
        if (!r.isClosed || r.isIssued) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            // "Remove" while nothing has gone out, "revoke" once it has: they
            // are the same operation, but calling a withdrawal a removal would
            // suggest the disclosure can be undone, and it cannot.
            label: r.isIssued ? 'Revoke issued report' : 'Remove this report',
            icon: r.isIssued ? AppIcons.close : AppIcons.delete,
            variant: AppButtonVariant.danger,
            expand: true,
            onPressed: _busy ? null : _revoke,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            r.isIssued
                ? 'The patient keeps their copy, marked as revoked, and is '
                      'told why. Nothing is deleted.'
                : 'The request is closed and kept in the audit trail. Nothing '
                      'was disclosed.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                    _ =>
                      request.issuedAt != null
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

/// What the admin is being asked to decide, said plainly.
///
/// The three exits are equally reachable on purpose. When the only buttons
/// were "issue" and "revoke", an admin who spotted a small error had to choose
/// between disclosing something wrong and destroying a consent the patient had
/// already given — so in practice they issued.
class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({required this.request});

  final PatientReportRequestItem request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = request;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.doctorGreen.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: AppColors.doctorGreen.withValues(alpha: 0.26),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                AppIcons.approval,
                size: 18,
                color: AppColors.doctorGreen,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Signed — your decision',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.doctorGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${r.signatureName ?? r.doctorName ?? 'A doctor'} signed this'
            '${dossierDate(r.signedAt) == null ? '' : ' on ${dossierDate(r.signedAt)}'}'
            '. Read it, then issue it, send it back for a correction, or '
            'remove the request.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontSize: 10.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Issuing files a copy in the patient’s documents straight away. '
            'Neither you nor a doctor can delete it afterwards.',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10.5,
              height: 1.45,
              fontWeight: FontWeight.w700,
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
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontSize: 10.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
