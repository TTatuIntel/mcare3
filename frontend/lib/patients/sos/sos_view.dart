import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/env/app_env.dart';
import '../../core/location/sos_location_service.dart';
import '../../shared/services/patient_session_service.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/sos.dart';
import '../../shared/state/profile_state.dart';
import '../../shared/state/sos_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dialog.dart';
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

class SosView extends StatefulWidget {
  const SosView({super.key});

  @override
  State<SosView> createState() => _SosViewState();
}

class _SosViewState extends State<SosView> {
  final _historyKey = GlobalKey();
  Timer? _livePoll;

  @override
  void initState() {
    super.initState();
    SosState.instance.addListener(_syncLivePoll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncLivePoll();
      if (AppEnv.backendEnabled && SosState.instance.hasActiveSos) {
        PatientSessionService.instance.syncFromApi();
      }
    });
  }

  @override
  void dispose() {
    SosState.instance.removeListener(_syncLivePoll);
    _livePoll?.cancel();
    super.dispose();
  }

  void _syncLivePoll() {
    if (!AppEnv.backendEnabled || !SosState.instance.hasActiveSos) {
      _livePoll?.cancel();
      _livePoll = null;
      return;
    }
    _livePoll ??= Timer.periodic(const Duration(seconds: 8), (_) {
      PatientSessionService.instance.syncFromApi();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PatientScaffold(
      currentRoute: RouteNames.patientSos,
      detachedNav: true,
      title: 'Emergency SOS',
      subtitle: 'One tap notifies contacts and your care team',
      body: AnimatedBuilder(
        animation: Listenable.merge([SosState.instance, ProfileState.instance]),
        builder: (context, _) {
          final active = SosState.instance.hasActiveSos;
          final activeEvent = SosState.instance.activeEvent;
          final history = SosState.instance.history;
          final contacts = SosState.instance.contacts;
          final resolvedCount = history
              .where((e) => e.status == SosStatus.resolved)
              .length;
          final lastEvent = history.isEmpty ? null : history.first;
          final tier = ResponsiveBuilder.of(context);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(index: 0, child: PatientDateHeader()),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 1,
                child: _SosHero(
                  active: active,
                  activeEvent: activeEvent,
                  contactCount: contacts.length,
                  totalEvents: history.length,
                  resolvedCount: resolvedCount,
                  lastEventAt: lastEvent?.triggeredAt,
                  onTrigger: () => _TriggerSheet.show(context),
                  onResolve: () async {
                    final ok = await SosState.instance.resolveActiveWithApi();
                    if (!context.mounted) return;
                    if (ok) {
                      AppToast.success(context, 'SOS marked resolved.');
                    } else {
                      AppToast.error(context, 'Could not update SOS.');
                    }
                  },
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
                        icon: AppIcons.sos,
                        label: 'Trigger',
                        horizontal: tier.isDesktop,
                        onTap: active
                            ? () => AppToast.info(
                                context,
                                'SOS is active. Mark resolved from the card above.',
                              )
                            : () => _TriggerSheet.show(context),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.phone,
                        label: 'Contacts',
                        horizontal: tier.isDesktop,
                        badge: contacts.isNotEmpty
                            ? '${contacts.length}'
                            : null,
                        onTap: () => ManageContactsSheet.show(context),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.time,
                        label: 'History',
                        horizontal: tier.isDesktop,
                        badge: history.isNotEmpty ? '${history.length}' : null,
                        onTap: () => patientScrollToKey(_historyKey),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.user,
                        label: 'Profile',
                        horizontal: tier.isDesktop,
                        onTap: () => Navigator.of(
                          context,
                        ).pushNamed(RouteNames.patientProfile),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 3,
                child: Builder(
                  builder: (context) {
                    final contactsSection = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionLabel(
                          title: 'Emergency contacts',
                          icon: AppIcons.phone,
                          trailing: contacts.isEmpty ? null : '${contacts.length}',
                          actionLabel: contacts.isEmpty ? 'Add' : 'Manage',
                          onAction: () => ManageContactsSheet.show(context),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        contacts.isEmpty
                            ? GlassCard(
                                frosted: true,
                                child: EmptyStateView(
                                  icon: AppIcons.phone,
                                  title: 'No contacts yet',
                                  message:
                                      'Add at least one trusted contact for emergencies.',
                                  actionLabel: 'Add contact',
                                  onAction: () => ManageContactsSheet.show(context),
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
                                    for (var i = 0; i < contacts.length; i++) ...[
                                      if (i > 0) const SizedBox(height: AppSpacing.xs),
                                      _ContactRow(contact: contacts[i]),
                                    ],
                                  ],
                                ),
                              ),
                      ],
                    );

                    final historySection = Column(
                      key: _historyKey,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionLabel(
                          title: 'SOS history',
                          icon: AppIcons.time,
                          trailing: history.isEmpty ? null : '${history.length}',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        history.isEmpty
                            ? GlassCard(
                                frosted: true,
                                child: EmptyStateView(
                                  icon: AppIcons.time,
                                  title: 'No past SOS events',
                                  message:
                                      'Every triggered SOS appears here with timeline.',
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
                                    for (var i = 0; i < history.length; i++) ...[
                                      if (i > 0) const SizedBox(height: AppSpacing.xs),
                                      _HistoryRow(event: history[i]),
                                    ],
                                  ],
                                ),
                              ),
                      ],
                    );

                    if (tier.isDesktop) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: contactsSection),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: historySection),
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        contactsSection,
                        const SizedBox(height: AppSpacing.md),
                        historySection,
                      ],
                    );
                  },
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

class _SosHero extends StatelessWidget {
  const _SosHero({
    required this.active,
    required this.activeEvent,
    required this.contactCount,
    required this.totalEvents,
    required this.resolvedCount,
    required this.lastEventAt,
    required this.onTrigger,
    required this.onResolve,
  });

  final bool active;
  final SosEvent? activeEvent;
  final int contactCount;
  final int totalEvents;
  final int resolvedCount;
  final DateTime? lastEventAt;
  final VoidCallback onTrigger;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.critical;
    final iconBg = AppPalette.criticalSoft(context);

    final headline = !active
        ? 'Need help now?'
        : activeEvent?.status == SosStatus.acknowledged
        ? 'Help is on the way'
        : 'SOS active';

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
                      color: iconBg,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Icon(
                      active ? Icons.emergency : AppIcons.sos,
                      color: accent,
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

              final rightSide = _HeroSosStrip(
                active: active,
                activeEvent: activeEvent,
                contactCount: contactCount,
                lastEventAt: lastEventAt,
                accent: accent,
                onTrigger: onTrigger,
                onResolve: onResolve,
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
                label: 'Contacts',
                value: '$contactCount',
                horizontal: true,
              ),
              const PatientHeroStatDivider(),
              PatientHeroStat(
                label: 'Events',
                value: '$totalEvents',
                horizontal: true,
              ),
              const PatientHeroStatDivider(),
              PatientHeroStat(
                label: 'Resolved',
                value: '$resolvedCount',
                accent: resolvedCount > 0 ? AppColors.success : null,
                horizontal: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroSosStrip extends StatelessWidget {
  const _HeroSosStrip({
    required this.active,
    required this.activeEvent,
    required this.contactCount,
    required this.lastEventAt,
    required this.accent,
    required this.onTrigger,
    required this.onResolve,
  });

  final bool active;
  final SosEvent? activeEvent;
  final int contactCount;
  final DateTime? lastEventAt;
  final Color accent;
  final VoidCallback onTrigger;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final caption = active
        ? (activeEvent?.status == SosStatus.acknowledged ? 'STATUS · ACKNOWLEDGED' : 'STATUS · EMERGENCY ACTIVE')
        : (contactCount == 0
            ? 'NO CONTACTS SET'
            : lastEventAt == null
                ? 'EMERGENCY DISPATCH'
                : 'LAST SOS EVENT');

    final subtext = !active
        ? (contactCount == 0
            ? 'Add emergency contacts now'
            : lastEventAt == null
                ? 'Alerts $contactCount contact${contactCount == 1 ? '' : 's'} + care team'
                : DateFormat.MMMd().add_jm().format(lastEventAt!))
        : (activeEvent?.status == SosStatus.acknowledged
            ? (activeEvent?.respondedBy != null
                ? '${activeEvent!.respondedBy} acknowledged'
                : 'Care team acknowledged — help is coming')
            : 'Contacts & team notified');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: active ? onResolve : onTrigger,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Ink(
          width: double.infinity,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
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
                    color: accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    active ? Icons.check_circle_outline : AppIcons.sos,
                    size: 16,
                    color: accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        caption,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.textMuted(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 9.5,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        active ? 'Mark SOS resolved' : 'Tap to Trigger SOS',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          height: 1.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtext,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.textMuted(context),
                          fontSize: 10,
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
                  color: accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact});
  final EmergencyContact contact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppPalette.criticalSoft(context).withOpacity(0.35),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.critical.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            height: 32,
            width: 32,
            decoration: BoxDecoration(
              color: AppColors.critical.withOpacity(0.14),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Center(
              child: Text(
                '${contact.priority}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.critical,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${contact.relationship} · ${contact.phone}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const Icon(AppIcons.phone, color: AppColors.critical, size: 16),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.event});
  final SosEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: event.status.color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: event.status.color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            height: 32,
            width: 32,
            decoration: BoxDecoration(
              color: event.status.color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(event.kind.icon, color: event.status.color, size: 16),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.kind.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  DateFormat.yMMMd().add_jm().format(event.triggeredAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontSize: 10,
                  ),
                ),
                if (event.locationLabel != null)
                  Text(
                    event.locationLabel!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: event.status.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Text(
              event.status.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: event.status.color,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TriggerSheet {
  _TriggerSheet._();
  static Future<void> show(BuildContext context) {
    return GlassSheet.show(
      context,
      title: 'Confirm SOS',
      subtitle: 'This will alert your emergency contacts and care team.',
      child: _TriggerForm(),
    );
  }
}

class _TriggerForm extends StatefulWidget {
  @override
  State<_TriggerForm> createState() => _TriggerFormState();
}

class _TriggerFormState extends State<_TriggerForm> {
  EmergencyKind _kind = EmergencyKind.medical;
  final _note = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _trigger() async {
    if (_sending) return;
    final ok = await AppDialog.confirm(
      context,
      title: 'Send SOS now?',
      message:
          'Emergency contacts and your assigned care team will be notified with your location.',
      confirmLabel: 'Send SOS',
      danger: true,
      icon: AppIcons.sos,
    );
    if (ok != true || !mounted) return;

    setState(() => _sending = true);
    final locationConsent =
        ProfileState.instance.health?.locationConsent == true;

    SosLocationSnapshot? location;
    if (locationConsent) {
      if (mounted) setState(() {});
      location = await SosLocationService.instance.capture(consent: true);
    }

    final locationLabel = location != null
        ? location.label
        : locationConsent
        ? 'Location unavailable — check GPS permissions'
        : 'Location not shared — enable in Settings';

    final sent = await SosState.instance.triggerWithApi(
      kind: _kind,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      locationLabel: locationLabel,
      latitude: location?.latitude,
      longitude: location?.longitude,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (!sent) {
      AppToast.error(context, 'Could not send SOS. Try again.');
      return;
    }
    Navigator.of(context).pop();
    AppToast.error(context, 'SOS sent — help is on the way.');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Emergency type', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: EmergencyKind.values.map((k) {
            final selected = _kind == k;
            return ChoiceChip(
              avatar: Icon(k.icon, size: 16),
              label: Text(k.label),
              selected: selected,
              onSelected: (_) => setState(() => _kind = k),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Note (optional)',
          hint: 'Brief description',
          controller: _note,
          maxLines: 2,
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: _sending
              ? (ProfileState.instance.health?.locationConsent == true
                    ? 'Locating & sending…'
                    : 'Sending…')
              : 'Send SOS',
          variant: AppButtonVariant.danger,
          icon: AppIcons.sos,
          expand: true,
          onPressed: _sending ? null : _trigger,
        ),
      ],
    );
  }
}

class ManageContactsSheet {
  ManageContactsSheet._();
  static Future<void> show(BuildContext context) {
    return GlassSheet.show(
      context,
      title: 'Emergency contacts',
      subtitle: 'Synced with your profile.',
      child: AnimatedBuilder(
        animation: SosState.instance,
        builder: (context, _) {
          final contacts = SosState.instance.contacts;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (contacts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: Text(
                    'No contacts yet. Add them from your profile.',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontSize: 11,
                    ),
                  ),
                ),
              for (final c in contacts)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                            ),
                            Text(
                              c.phone,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: AppPalette.textMuted(context),
                                    fontSize: 10,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      AppButton.icon(
                        icon: AppIcons.delete,
                        semanticLabel: 'Remove',
                        onPressed: () => SosState.instance.removeContact(c.id),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Add contact',
                icon: AppIcons.add,
                variant: AppButtonVariant.secondary,
                expand: true,
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushNamed(RouteNames.patientProfile);
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
