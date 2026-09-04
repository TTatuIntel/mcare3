import 'package:flutter/material.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/care_provider.dart';
import '../../shared/state/care_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/section_label.dart';
import 'external_access_sheet.dart';

class RequestCareSheet {
  RequestCareSheet._();

  static Future<void> show(BuildContext context, CareProvider provider) {
    // The browse row already hides the call to action once a request is open;
    // this catches the stale-state case (a request made on another device, or
    // a row tapped before the sync landed) before the form is even shown.
    final open = CareState.instance.pendingRequestFor(provider.id);
    if (open != null) {
      AppToast.info(
        context,
        'You already have a pending request with ${provider.name}. '
        'Check Pending to follow it up.',
      );
      return Future.value();
    }

    return GlassSheet.show(
      context,
      title: 'Request care',
      subtitle: 'Ask this provider to join your team.',
      child: _Form(provider: provider),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({required this.provider});
  final CareProvider provider;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await CareState.instance.requestCareRemote(
        widget.provider,
        reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      );
    } on DuplicateCareRequest catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.info(context, '$e Check Pending to follow it up.');
      return;
    } on AlreadyOnCareTeam catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.info(context, '$e');
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.warn(context, 'Could not send: $e');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.success(context, 'Care request sent to ${widget.provider.name}.');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${widget.provider.specialty} · ${widget.provider.facility}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Reason (optional)',
          hint: 'Why would you like this provider on your team?',
          controller: _reason,
          maxLines: 3,
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Send request',
          icon: AppIcons.add,
          loading: _saving,
          expand: true,
          onPressed: _submit,
        ),
      ],
    );
  }
}

enum _CareTeamTab { myTeam, browse, pending }

class CareTeamView extends StatefulWidget {
  const CareTeamView({super.key});

  @override
  State<CareTeamView> createState() => _CareTeamViewState();
}

class _CareTeamViewState extends State<CareTeamView> {
  _CareTeamTab _tab = _CareTeamTab.myTeam;

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);

    return PatientScaffold(
      currentRoute: RouteNames.patientCareTeam,
      title: 'My team',
      subtitle: 'Your providers and available doctors',
      body: AnimatedBuilder(
        animation: CareState.instance,
        builder: (context, _) {
          final assigned = CareState.instance.assigned;
          final available = CareState.instance.available;
          final pending = CareState.instance.requests
              .where((r) => r.status == CareRequestStatus.pending)
              .toList();
          final providers = _tab == _CareTeamTab.browse
              ? available
              : _tab == _CareTeamTab.myTeam
              ? assigned
              : <CareProvider>[];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(index: 0, child: PatientDateHeader()),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 1,
                child: _TeamHero(
                  assignedCount: assigned.length,
                  availableCount: available.length,
                  pendingCount: pending.length,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 2,
                child: GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xs,
                  ),
                  child: PatientQuickActionsBar(
                    children: [
                      PatientQuickAction(
                        icon: AppIcons.careTeam,
                        label: 'My team',
                        horizontal: tier.isDesktop,
                        badge: assigned.isNotEmpty
                            ? '${assigned.length}'
                            : null,
                        selected: _tab == _CareTeamTab.myTeam,
                        onTap: () => setState(() => _tab = _CareTeamTab.myTeam),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.add,
                        label: 'Browse',
                        horizontal: tier.isDesktop,
                        badge: available.isNotEmpty
                            ? '${available.length}'
                            : null,
                        selected: _tab == _CareTeamTab.browse,
                        onTap: () => setState(() => _tab = _CareTeamTab.browse),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.link,
                        label: 'Emergency access',
                        horizontal: tier.isDesktop,
                        onTap: () => ExternalAccessSheet.show(context),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.time,
                        label: 'Pending',
                        horizontal: tier.isDesktop,
                        badge: pending.isNotEmpty ? '${pending.length}' : null,
                        badgeColor: AppColors.warning,
                        selected: _tab == _CareTeamTab.pending,
                        onTap: () =>
                            setState(() => _tab = _CareTeamTab.pending),
                      ),
                    ],
                  ),
                ),
              ),
              if (pending.isNotEmpty && _tab != _CareTeamTab.pending) ...[
                const SizedBox(height: AppSpacing.sm),
                StaggeredEntry(
                  index: 3,
                  child: _PendingBanner(count: pending.length),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 4,
                child: SectionLabel(
                  title: _tab == _CareTeamTab.browse
                      ? 'Browse providers'
                      : _tab == _CareTeamTab.pending
                      ? 'Pending requests'
                      : 'Assigned to you',
                  icon: AppIcons.careTeam,
                  trailing: _tab == _CareTeamTab.pending
                      ? '${pending.length}'
                      : providers.isEmpty
                      ? null
                      : '${providers.length}',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 5,
                child: _tab == _CareTeamTab.pending
                    ? (pending.isEmpty
                          ? GlassCard(
                              frosted: true,
                              child: EmptyStateView(
                                icon: AppIcons.time,
                                title: 'No pending requests',
                                message:
                                    'Browse providers to request care from a doctor.',
                                compact: true,
                              ),
                            )
                          : GlassCard(
                              frosted: true,
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.md,
                                AppSpacing.sm,
                                AppSpacing.md,
                                AppSpacing.md,
                              ),
                              child: Column(
                                children: [
                                  for (var i = 0; i < pending.length; i++) ...[
                                    if (i > 0)
                                      const SizedBox(height: AppSpacing.xs),
                                    _PendingRequestRow(request: pending[i]),
                                  ],
                                ],
                              ),
                            ))
                    : providers.isEmpty
                    ? GlassCard(
                        frosted: true,
                        child: EmptyStateView(
                          icon: AppIcons.careTeam,
                          title: _tab == _CareTeamTab.browse
                              ? 'No providers available'
                              : 'No assigned providers',
                          message: _tab == _CareTeamTab.browse
                              ? 'Check back later for new providers.'
                              : 'Browse and request care from available doctors.',
                          compact: true,
                        ),
                      )
                    : GlassCard(
                        frosted: true,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.md,
                          AppSpacing.md,
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < providers.length; i++) ...[
                              if (i > 0) const SizedBox(height: AppSpacing.xs),
                              _ProviderRow(
                                provider: providers[i],
                                assigned: _tab == _CareTeamTab.myTeam,
                                pendingRequest: CareState.instance
                                    .pendingRequestFor(providers[i].id),
                                onViewPending: () =>
                                    setState(() => _tab = _CareTeamTab.pending),
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
              SizedBox(height: tier.isHandheld ? 24 : AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }
}

class _TeamHero extends StatelessWidget {
  const _TeamHero({
    required this.assignedCount,
    required this.availableCount,
    required this.pendingCount,
  });

  final int assignedCount;
  final int availableCount;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headline = assignedCount == 0
        ? 'Build your care team'
        : '$assignedCount provider${assignedCount == 1 ? '' : 's'} on your team';
    final accent = AppColors.doctorGreen;

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 500;
              final leftSide = Row(
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: const Icon(
                      AppIcons.careTeam,
                      color: AppColors.doctorGreen,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        headline,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppPalette.ink(context),
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          height: 1.15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              );

              final rightSide = _HeroTeamStrip(
                pendingCount: pendingCount,
                availableCount: availableCount,
                accent: accent,
              );

              if (!isWide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    leftSide,
                    const SizedBox(height: AppSpacing.sm),
                    rightSide,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: leftSide),
                  Container(
                    height: 42,
                    width: 1,
                    color: AppPalette.border(context),
                    margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  ),
                  Expanded(child: rightSide),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: AppPalette.border(context)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              PatientHeroStat(
                label: 'My team',
                value: '$assignedCount',
                horizontal: true,
              ),
              const PatientHeroStatDivider(),
              PatientHeroStat(
                label: 'Browse',
                value: '$availableCount',
                horizontal: true,
              ),
              const PatientHeroStatDivider(),
              PatientHeroStat(
                label: 'Pending',
                value: '$pendingCount',
                accent: pendingCount > 0 ? AppColors.warning : null,
                horizontal: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroTeamStrip extends StatelessWidget {
  const _HeroTeamStrip({
    required this.pendingCount,
    required this.availableCount,
    required this.accent,
  });

  final int pendingCount;
  final int availableCount;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPending = pendingCount > 0;
    final tone = hasPending ? AppColors.warning : accent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ExternalAccessSheet.show(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Ink(
          width: double.infinity,
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs + 2,
            ),
            child: Row(
              children: [
                Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    hasPending ? AppIcons.time : AppIcons.link,
                    size: 16,
                    color: tone,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hasPending
                            ? 'PENDING REQUESTS ($pendingCount)'
                            : 'EMERGENCY ACCESS',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.textMuted(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 9.5,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasPending
                            ? 'Awaiting doctor response'
                            : 'Manage external provider access',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppPalette.ink(context),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          height: 1.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  AppIcons.chevronRight,
                  size: 14,
                  color: tone,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          const Icon(AppIcons.time, size: 16, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$count pending care request${count == 1 ? '' : 's'}',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingRequestRow extends StatelessWidget {
  const _PendingRequestRow({required this.request});
  final CareRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppPalette.warningSoft(context).withOpacity(0.45),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.warning.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(AppIcons.time, size: 16, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.providerName,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${request.providerSpecialty} · ${request.status.label}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontSize: 10,
                  ),
                ),
                if (request.reason != null && request.reason!.isNotEmpty)
                  Text(
                    request.reason!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.assigned,
    this.pendingRequest,
    this.onViewPending,
  });

  final CareProvider provider;
  final bool assigned;

  /// The patient's open request with this provider, when there is one. Its
  /// presence is what turns the call to action into a "Requested" state — a
  /// provider can only be asked once until that request is decided.
  final CareRequest? pendingRequest;
  final VoidCallback? onViewPending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.doctorGreen.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.doctorGreen.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                height: 32,
                width: 32,
                decoration: BoxDecoration(
                  color: AppColors.doctorGreen.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(
                  AppIcons.careTeam,
                  color: AppColors.doctorGreen,
                  size: 16,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            provider.name,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (pendingRequest != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          const _RequestedPill(),
                        ],
                      ],
                    ),
                    Text(
                      '${provider.specialty} · ${provider.facility}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        const Icon(
                          AppIcons.star,
                          size: 12,
                          color: AppColors.warning,
                        ),
                        Text(
                          ' ${provider.rating} (${provider.totalReviews})',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (provider.bio != null) ...[
            const SizedBox(height: 4),
            Text(
              provider.bio!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (assigned)
            AppButton(
              label: 'Message',
              variant: AppButtonVariant.secondary,
              icon: AppIcons.chat,
              size: AppButtonSize.sm,
              expand: true,
              onPressed: () =>
                  Navigator.of(context).pushNamed(RouteNames.patientMessages),
            )
          else if (pendingRequest != null) ...[
            AppButton(
              label: 'Requested',
              variant: AppButtonVariant.secondary,
              icon: AppIcons.time,
              size: AppButtonSize.sm,
              expand: true,
              semanticLabel:
                  'Care already requested from ${provider.name}. '
                  'View your pending request.',
              onPressed: onViewPending,
            ),
            const SizedBox(height: 4),
            Text(
              'Waiting for approval — one request per provider.',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontSize: 10,
              ),
            ),
          ] else
            AppButton(
              label: 'Request care',
              icon: AppIcons.add,
              size: AppButtonSize.sm,
              expand: true,
              onPressed: () => RequestCareSheet.show(context, provider),
            ),
        ],
      ),
    );
  }
}

/// "Pending" marker on a provider the patient has already asked for.
class _RequestedPill extends StatelessWidget {
  const _RequestedPill();

  @override
  Widget build(BuildContext context) {
    const tone = AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.14),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: tone.withOpacity(0.35)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.time, size: 9, color: tone),
          SizedBox(width: 3),
          Text(
            'Requested',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: tone,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
