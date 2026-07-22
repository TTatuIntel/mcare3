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
        animation: Listenable.merge([
          SosState.instance,
          ProfileState.instance,
        ]),
        builder: (context, _) {
    final active = SosState.instance.hasActiveSos;
    final activeEvent = SosState.instance.activeEvent;
    final history = SosState.instance.history;
          final contacts = SosState.instance.contacts;
          final resolvedCount =
              history.where((e) => e.status == SosStatus.resolved).length;
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
                        badge: contacts.isNotEmpty ? '${contacts.length}' : null,
                        onTap: () => ManageContactsSheet.show(context),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.time,
                        label: 'History',
                        badge: history.isNotEmpty ? '${history.length}' : null,
                        onTap: () => patientScrollToKey(_historyKey),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.user,
                        label: 'Profile',
                        onTap: () => Navigator.of(context)
                            .pushNamed(RouteNames.patientProfile),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 3,
                child: SectionLabel(
                  title: 'Emergency contacts',
                  icon: AppIcons.phone,
                  trailing: contacts.isEmpty ? null : '${contacts.length}',
                  actionLabel: contacts.isEmpty ? 'Add' : 'Manage',
                  onAction: () => ManageContactsSheet.show(context),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 4,
                child: contacts.isEmpty
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
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 5,
                child: KeyedSubtree(
                  key: _historyKey,
                  child: SectionLabel(
                    title: 'SOS history',
                    icon: AppIcons.time,
                    trailing: history.isEmpty ? null : '${history.length}',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 6,
                child: history.isEmpty
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
    final accent = active ? AppColors.critical : AppColors.critical;
    final iconBg = active ? AppPalette.criticalSoft(context) : AppPalette.criticalSoft(context);

    final headline = !active
        ? 'Need help now?'
        : activeEvent?.status == SosStatus.acknowledged
            ? 'Help is on the way'
            : 'SOS active';
    final subline = !active
        ? (contactCount == 0
            ? 'Add a contact before triggering SOS.'
            : lastEventAt == null
                ? 'Alerts $contactCount contact${contactCount == 1 ? '' : 's'} + care team.'
                : 'Last event ${DateFormat.MMMd().add_jm().format(lastEventAt!)}')
        : activeEvent?.status == SosStatus.acknowledged
            ? (activeEvent?.respondedBy != null
                ? '${activeEvent!.respondedBy} acknowledged your SOS.'
                : 'Your care team acknowledged — stay calm, help is coming.')
            : 'Contacts and care team have been notified.';

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(
                  active ? Icons.emergency : AppIcons.sos,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  headline,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppPalette.ink(context),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs + 2,
            ),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: accent.withOpacity(0.2)),
            ),
            child: Text(
              subline,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: AppPalette.border(context)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              PatientHeroStat(label: 'Contacts', value: '$contactCount'),
              const PatientHeroStatDivider(),
              PatientHeroStat(label: 'Events', value: '$totalEvents'),
              const PatientHeroStatDivider(),
              PatientHeroStat(
                label: 'Resolved',
                value: '$resolvedCount',
                accent: resolvedCount > 0 ? AppColors.success : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (active)
            AppButton(
              label: 'Mark as resolved',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              expand: true,
              onPressed: onResolve,
            )
          else
            AppButton(
              label: 'Trigger SOS',
              icon: AppIcons.sos,
              variant: AppButtonVariant.danger,
              size: AppButtonSize.sm,
              expand: true,
              onPressed: onTrigger,
            ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
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
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                            ),
                            Text(
                              c.phone,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
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
