import 'package:flutter/material.dart';

import '../../../core/api/admin_api.dart';
import '../../../core/env/app_env.dart';
import '../../auth/auth_state.dart';
import '../../models/user_dossier.dart';
import '../../models/user_role.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../app_button.dart';
import '../app_icons.dart';
import '../app_toast.dart';
import '../empty_state.dart';
import '../glass_sheet.dart';
import '../skeleton.dart';
import 'dossier_blocks.dart';
import 'dossier_clinical_sections.dart';
import 'dossier_staff_sections.dart';

/// The complete profile for ANY account — patient, doctor, mCare assistant,
/// or admin — in one sheet with the same layout for every role.
///
/// Staff previously saw a rich clinical sheet for patients and a three-line
/// card for everyone else, which made it easy to suspend a doctor without
/// seeing their caseload or approve someone without seeing their credentials.
/// One surface, one shape, nothing hidden.
class UserDossierSheet {
  UserDossierSheet._();

  static Future<void> show(
    BuildContext context, {
    required String userId,
    String? name,
    String? subtitle,
    VoidCallback? onIssueReport,
  }) {
    return GlassSheet.show<void>(
      context,
      title: name ?? 'Profile',
      subtitle: subtitle ?? 'Full account record',
      maxWidth: 700,
      child: _DossierBody(userId: userId, onIssueReport: onIssueReport),
    );
  }
}

class _DossierBody extends StatefulWidget {
  const _DossierBody({required this.userId, this.onIssueReport});

  final String userId;
  final VoidCallback? onIssueReport;

  @override
  State<_DossierBody> createState() => _DossierBodyState();
}

class _DossierBodyState extends State<_DossierBody> {
  UserDossier? _dossier;
  bool _loading = true;
  String? _error;
  int _segment = 0;

  @override
  void initState() {
    super.initState();
    // Fetch after first frame so the sheet animates in immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!AppEnv.backendEnabled) {
      setState(() {
        _loading = false;
        _error = 'Full profiles need the backend connection.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await AdminApi.instance.userDossier(widget.userId);
      if (!mounted) return;
      setState(() {
        _dossier = data == null ? null : UserDossier.fromJson(data);
        _loading = false;
        _error = data == null ? 'No profile returned.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// Segment labels differ by role, but the first and last two are always
  /// Overview / Account / Activity so staff build one mental model.
  List<String> get _segments {
    final d = _dossier;
    if (d == null) return const ['Overview'];
    if (d.isPatient) {
      return const ['Overview', 'Clinical', 'Account', 'Activity'];
    }
    return const ['Overview', 'Work', 'Account', 'Activity'];
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _dossier == null) return const _DossierSkeleton();

    final dossier = _dossier;
    if (dossier == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmptyStateView(
            icon: AppIcons.alert,
            title: 'Could not load profile',
            message: _error ?? 'Please try again.',
            compact: true,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(label: 'Retry', icon: AppIcons.refresh, onPressed: _load),
        ],
      );
    }

    final segments = _segments;
    final index = _segment.clamp(0, segments.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DossierHero(dossier: dossier),
        const SizedBox(height: AppSpacing.md),
        DossierStatStrip(stats: dossier.stats),
        const SizedBox(height: AppSpacing.md),
        DossierSegments(
          segments: segments,
          selected: index,
          onSelect: (i) => setState(() => _segment = i),
        ),
        const SizedBox(height: AppSpacing.lg),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: KeyedSubtree(
            key: ValueKey('${dossier.account.id}-$index'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _sectionsFor(dossier, segments[index]),
            ),
          ),
        ),
        if (dossier.isPatient && _canIssueReports) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Issue patient report',
            icon: AppIcons.report,
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: () {
              Navigator.of(context, rootNavigator: true).pop();
              widget.onIssueReport?.call();
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Choose exactly which sections to include. Confidential sections '
            'need the patient\'s approval and a doctor\'s signature.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontSize: 10,
              height: 1.4,
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _StaleNotice(onRetry: _load),
        ],
      ],
    );
  }

  bool get _canIssueReports {
    if (widget.onIssueReport == null) return false;
    final role = AuthState.instance.user?.role;
    return role == UserRole.admin || role == UserRole.mcareAssistant;
  }

  List<Widget> _sectionsFor(UserDossier d, String segment) {
    return switch (segment) {
      'Clinical' => buildClinicalSections(context, d),
      'Work' => buildStaffWorkSections(context, d),
      'Account' => buildAccountSections(context, d),
      'Activity' => buildActivitySections(context, d),
      _ =>
        d.isPatient
            ? buildPatientOverviewSections(context, d)
            : buildStaffOverviewSections(context, d),
    };
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
              'Showing cached details — could not refresh.',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _DossierSkeleton extends StatelessWidget {
  const _DossierSkeleton();

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
          height: 150,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        const SizedBox(height: AppSpacing.md),
        SkeletonBox(
          height: 120,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
      ],
    );
  }
}

/// Convenience for callers that only have a name and want a toast on failure.
Future<void> showUserDossier(
  BuildContext context, {
  required String userId,
  String? name,
  String? subtitle,
  VoidCallback? onIssueReport,
}) async {
  try {
    await UserDossierSheet.show(
      context,
      userId: userId,
      name: name,
      subtitle: subtitle,
      onIssueReport: onIssueReport,
    );
  } catch (e) {
    if (context.mounted) AppToast.error(context, 'Could not open profile: $e');
  }
}
