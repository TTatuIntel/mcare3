import 'package:flutter/material.dart';

import '../../core/api/patient_record_api.dart';
import '../../core/env/app_env.dart';
import '../../core/realtime/realtime_refresh_mixin.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/user_dossier.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/dossier/dossier_blocks.dart';
import '../../shared/widgets/dossier/dossier_clinical_sections.dart';
import '../../shared/widgets/dossier/dossier_staff_sections.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/skeleton.dart';

/// The patient reading their own record, in the shape their clinic reads it.
///
/// Admins and doctors have long had one dossier per patient — health profile,
/// vitals, medications, care team, appointments, documents, alerts, account
/// and sign-in history — while the person the record describes had to piece
/// themselves together from four separate screens and still could not see the
/// account facts staff act on. This is that dossier, rendered by the same
/// widgets from the same payload, so what a patient reads about themselves can
/// never quietly diverge from what their clinic reads.
///
/// It is a record, not a settings screen: everything here is read-only, and
/// each segment points at the patient-facing page that owns the edit. Changing
/// details still happens under Profile, preferences still under Settings.
class PatientClinicalProfileView extends StatefulWidget {
  const PatientClinicalProfileView({super.key, this.initialSegment = 0});

  /// Which tab opens first — notifications about a specific part of the record
  /// can land the patient on it directly.
  final int initialSegment;

  @override
  State<PatientClinicalProfileView> createState() =>
      _PatientClinicalProfileViewState();
}

class _PatientClinicalProfileViewState extends State<PatientClinicalProfileView>
    with RealtimeRefreshMixin<PatientClinicalProfileView> {
  static const _segments = ['Overview', 'Clinical', 'Account', 'History'];

  UserDossier? _dossier;
  PatientReportAccess _reportAccess = PatientReportAccess.empty;
  bool _loading = true;
  String? _error;
  late int _segment = widget.initialSegment.clamp(0, _segments.length - 1);

  @override
  void initState() {
    super.initState();
    // The same domains the staff dossier watches: a reading recorded on the
    // phone, a document a clinician files, a new assignment — all of it should
    // appear here without the patient pulling to refresh.
    watchRealtime(const {
      'profile',
      'vitals',
      'medications',
      'appointments',
      'documents',
      'care',
      'reports',
      'alerts',
      'meals',
    }, _load);
    _load();
  }

  Future<void> _load() async {
    if (!AppEnv.backendEnabled) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Your full record needs the backend connection.';
      });
      return;
    }

    if (mounted) setState(() => _error = null);

    try {
      final data = await PatientRecordApi.instance.fetch();
      if (!mounted) return;
      setState(() {
        _dossier = data == null ? _dossier : UserDossier.fromJson(data);
        _reportAccess = PatientReportAccess.fromJson(
          (data?['report_access'] as Map?)?.cast<String, dynamic>(),
        );
        _loading = false;
        _error = data == null ? 'No record returned.' : null;
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
    return PatientScaffold(
      currentRoute: RouteNames.patientClinicalProfile,
      detachedNav: true,
      title: 'Clinical profile',
      subtitle: 'The record your care team reads',
      maxContentWidth: 900,
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final dossier = _dossier;

    if (dossier == null) {
      if (_loading) return const _RecordSkeleton();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.xxl),
          EmptyStateView(
            icon: AppIcons.alert,
            title: 'Could not load your record',
            message: _error ?? 'Please try again in a moment.',
          ),
          const SizedBox(height: AppSpacing.md),
          if (AppEnv.backendEnabled)
            AppButton(
              label: 'Try again',
              icon: AppIcons.refresh,
              onPressed: _load,
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StaggeredEntry(index: 0, child: DossierHero(dossier: dossier)),
        const SizedBox(height: AppSpacing.md),
        StaggeredEntry(
          index: 1,
          child: DossierStatStrip(stats: dossier.stats),
        ),
        const SizedBox(height: AppSpacing.md),
        StaggeredEntry(
          index: 2,
          child: DossierSegments(
            segments: _segments,
            selected: _segment,
            onSelect: (i) => setState(() => _segment = i),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: KeyedSubtree(
            key: ValueKey('record-$_segment'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._sectionsFor(dossier),
                _EditHint(segment: _segments[_segment]),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _StaleNotice(onRetry: _load),
        ],
        const SizedBox(height: AppSpacing.xl),
        RequestFullReportCard(
          access: _reportAccess,
          onSubmitted: _load,
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  List<Widget> _sectionsFor(UserDossier d) {
    return switch (_segments[_segment]) {
      'Clinical' => buildClinicalSections(context, d),
      'Account' => buildAccountSections(context, d),
      'History' => buildActivitySections(context, d),
      _ => buildPatientOverviewSections(context, d),
    };
  }
}

/// Where the record ends and the controls live.
///
/// The record is read-only by design, which leaves an obvious question on
/// every segment — "how do I change this?" — so each one answers it with the
/// page that actually owns the edit rather than leaving the patient hunting.
class _EditHint extends StatelessWidget {
  const _EditHint({required this.segment});

  final String segment;

  @override
  Widget build(BuildContext context) {
    final (message, label, route) = switch (segment) {
      'Clinical' => (
        'Readings, medicines and documents are added from the Health tab; '
            'your care team files the rest.',
        'Open Health',
        RouteNames.patientHealth,
      ),
      'Account' => (
        'Your name, contact details and emergency contacts are edited under '
            'Profile. Appearance, language and alerts live under Settings.',
        'Open Profile',
        RouteNames.patientProfile,
      ),
      'History' => (
        'This is the trail of what happened on your account. Reports shared '
            'about you are listed under Reports about you.',
        'Open reports',
        RouteNames.patientReportConsents,
      ),
      _ => (
        'Your health profile, conditions, allergies and emergency contacts '
            'are edited under Profile.',
        'Open Profile',
        RouteNames.patientProfile,
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppPalette.surfaceMuted(context),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppPalette.border(context)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              AppIcons.info,
              size: 16,
              color: AppPalette.textMuted(context),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppPalette.textMuted(context),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pushNamed(route),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

/// The patient asking for a complete, signed copy of their own record.
///
/// A patient who needed their record for an insurer, a second opinion or a new
/// clinic had to ring the desk, and nothing about the ask existed anywhere —
/// so nobody could see it was outstanding and nobody could be shown to have
/// answered it. The reason is required because it is what the doctor asked to
/// sign the report reads before signing it; a request with no stated purpose
/// is one they cannot judge.
///
/// It takes the same route as a report an admin raises: a care-team doctor
/// signs, an admin issues. The patient is told what that means before they ask.
class RequestFullReportCard extends StatefulWidget {
  const RequestFullReportCard({
    super.key,
    required this.access,
    this.onSubmitted,
  });

  final PatientReportAccess access;

  /// Called after a successful request so the page can pick up the new state
  /// (the button disables itself while one is in flight).
  final VoidCallback? onSubmitted;

  @override
  State<RequestFullReportCard> createState() => _RequestFullReportCardState();
}

class _RequestFullReportCardState extends State<RequestFullReportCard> {
  final _reason = TextEditingController();
  final _recipient = TextEditingController();
  bool _submitting = false;
  bool _showSections = false;
  String? _reasonError;

  /// Common reasons, so the patient is not made to compose a sentence before
  /// they can ask for their own record.
  static const _presets = [
    'For a second opinion',
    'For my insurer',
    'Moving to a new clinic',
    'For my own records',
    'For an employer or school',
  ];

  @override
  void dispose() {
    _reason.dispose();
    _recipient.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason.text.trim();
    if (reason.length < 10) {
      setState(
        () => _reasonError =
            'Please say a little more about what the report is for '
            '(at least 10 characters).',
      );
      return;
    }

    setState(() {
      _reasonError = null;
      _submitting = true;
    });

    try {
      final result = await PatientRecordApi.instance.requestFullReport(
        reason: reason,
        recipient: _recipient.text,
      );
      if (!mounted) return;
      final signer =
          ((result['report_request'] as Map?)?['doctor_name'] as String?)
              ?.trim();
      _reason.clear();
      _recipient.clear();
      setState(() => _submitting = false);
      AppToast.success(
        context,
        signer == null || signer.isEmpty
            ? 'Report requested. Your care team will review and sign it.'
            : 'Report requested. Sent to Dr. $signer to review and sign.',
      );
      widget.onSubmitted?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppToast.error(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final access = widget.access;
    final blocked = access.blockedReason;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brandIndigo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Icon(
                  AppIcons.report,
                  size: 20,
                  color: AppColors.brandIndigo,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Request your full report',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'A complete, signed copy of everything on this page. '
                      'One of your doctors reviews and signs it, then your '
                      'clinic issues it — you will be notified when it is '
                      'ready to open.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (access.signerName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  DossierPill(
                    label: 'Signed by Dr. ${access.signerName}',
                    color: AppColors.doctorGreen,
                    icon: AppIcons.careTeam,
                  ),
                ],
              ),
            ),
          if (access.sections.isNotEmpty) ...[
            InkWell(
              onTap: () => setState(() => _showSections = !_showSections),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Text(
                      'What the report covers '
                      '(${access.sections.length} sections)',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      _showSections
                          ? AppIcons.expandLess
                          : AppIcons.expandMore,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
            if (_showSections)
              DossierChips(
                labels: access.sections.map((s) => s.label).toList(),
                color: AppColors.bpPurple,
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (blocked != null)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.24),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    AppIcons.info,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      blocked,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final preset in _presets)
                  ActionChip(
                    label: Text(preset),
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                            _reason.text = preset;
                            _reasonError = null;
                          }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Why do you need this report?',
              hint: 'e.g. My new cardiologist has asked for my full history.',
              controller: _reason,
              maxLines: 3,
              minLines: 2,
              maxLength: 280,
              enabled: !_submitting,
              errorText: _reasonError,
              helperText:
                  'Your doctor reads this before signing, so be specific.',
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: 'Who is it for? (optional)',
              hint: 'e.g. Dr. Adeyemi, Lagoon Hospital',
              controller: _recipient,
              maxLength: 160,
              enabled: !_submitting,
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Request full report',
              icon: AppIcons.report,
              expand: true,
              loading: _submitting,
              loadingLabel: 'Sending your request',
              onPressed: _submitting ? null : _submit,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).pushNamed(RouteNames.patientReportConsents),
              icon: const Icon(AppIcons.document, size: 16),
              label: const Text('Track reports about you'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaleNotice extends StatelessWidget {
  const _StaleNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 16,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Showing your last synced record — could not refresh.',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _RecordSkeleton extends StatelessWidget {
  const _RecordSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonBox(
          height: 132,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        const SizedBox(height: AppSpacing.md),
        SkeletonBox(
          height: 74,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        const SizedBox(height: AppSpacing.md),
        SkeletonBox(
          height: 34,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        const SizedBox(height: AppSpacing.lg),
        SkeletonBox(
          height: 180,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        const SizedBox(height: AppSpacing.md),
        SkeletonBox(
          height: 140,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
      ],
    );
  }
}
