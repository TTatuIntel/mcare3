import 'package:flutter/material.dart';

import '../../shared/auth/auth_state.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/app_user.dart';
import '../../shared/models/patient_profile.dart';
import '../../shared/models/profile_completion.dart';
import '../../shared/models/sos.dart';
import '../../shared/models/vital.dart';
import '../../shared/services/profile_service.dart';
import '../../shared/state/profile_state.dart';
import '../../shared/state/vitals_state.dart';
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
import '../../shared/widgets/profile_completion_heart.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/profile/edit_account_sheet.dart';
import '../../shared/profile/profile_header_card.dart';
import '../../shared/profile/profile_sections.dart';
import 'edit_health_sheet.dart';

Future<void> _updateLocationConsent(
  BuildContext context,
  AppUser user,
  bool value,
) async {
  try {
    await ProfileService.setLocationConsent(editor: user, value: value);
    if (!context.mounted) return;
    AppToast.success(
      context,
      value ? 'Location sharing enabled.' : 'Location sharing disabled.',
    );
  } catch (e) {
    if (!context.mounted) return;
    AppToast.error(context, 'Could not update consent: $e');
  }
}

class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    return PatientScaffold(
      currentRoute: RouteNames.patientProfile,
      detachedNav: true,
      title: 'Profile',
      subtitle: 'Personal info and health profile',
      body: AnimatedBuilder(
        animation: Listenable.merge([
          AuthState.instance,
          ProfileState.instance,
          VitalsState.instance,
        ]),
        builder: (context, _) {
          final user = AuthState.instance.user;
          final health = ProfileState.instance.health;
          final contacts = ProfileState.instance.emergencyContacts;
          final tracked = VitalsState.instance.tracked.toList();
          final completion = ProfileCompletion.forUser(
            user: user,
            health: health,
            contacts: contacts,
            assignedVitals: tracked,
          );
          final tier = ResponsiveBuilder.of(context);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(index: 0, child: PatientDateHeader()),
              const SizedBox(height: AppSpacing.sm),
              if (user != null)
                StaggeredEntry(
                  index: 1,
                  child: ProfileHeaderCard(
                    user: user,
                    completionPercent: completion.percent,
                    onEdit: () => EditAccountSheet.show(context),
                    warning: user.isProfileComplete
                        ? null
                        : 'Complete your profile so your care team has what they need.',
                    stats: [
                      ProfileHeaderStat(
                        label: 'Complete',
                        value: '${completion.percent}%',
                        accent: completion.percent >= 100
                            ? AppColors.success
                            : AppColors.brandIndigo,
                      ),
                      ProfileHeaderStat(
                        label: 'BMI',
                        value: health != null
                            ? health.bmi.toStringAsFixed(1)
                            : '—',
                      ),
                      ProfileHeaderStat(
                        label: 'Contacts',
                        value: '${contacts.length}',
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 2,
                child: GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: ProfileCompletionCard(
                    percent: completion.percent,
                    incompleteLabels: completion.incompleteItems
                        .map((i) => i.label)
                        .toList(),
                    onTap: () => _CompletionSheet.show(context, completion),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 3,
                child: GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xs,
                  ),
                  child: PatientQuickActionsBar(
                    children: [
                      PatientQuickAction(
                        icon: AppIcons.edit,
                        label: 'Edit health',
                        onTap: () {
                          if (health == null) {
                            AppToast.info(
                              context,
                              'Health profile is still loading — try again in a moment.',
                            );
                            return;
                          }
                          EditHealthSheet.show(context);
                        },
                      ),
                      PatientQuickAction(
                        icon: AppIcons.sos,
                        label: 'Contacts',
                        badge: contacts.isNotEmpty
                            ? '${contacts.length}'
                            : null,
                        onTap: () => _AddContactSheet.show(context),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.settings,
                        label: 'Settings',
                        onTap: () => Navigator.of(
                          context,
                        ).pushNamed(RouteNames.patientSettings),
                      ),
                    ],
                  ),
                ),
              ),
              if (user != null) ...[
                const SizedBox(height: AppSpacing.md),
                StaggeredEntry(
                  index: 4,
                  child: ProfileAccountSection(
                    user: user,
                    onEdit: () => EditAccountSheet.show(context),
                  ),
                ),
              ],
              if (health != null) ...[
                const SizedBox(height: AppSpacing.md),
                StaggeredEntry(
                  index: 5,
                  child: SectionLabel(
                    title: 'Health profile',
                    icon: AppIcons.vitals,
                    trailing: health.bmiCategory,
                    actionLabel: 'Edit',
                    onAction: () => EditHealthSheet.show(context),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                StaggeredEntry(
                  index: 5,
                  child: GlassCard(
                    frosted: true,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    child: Column(
                      children: [
                        PatientCompactInfoRow(
                          label: 'Age',
                          value: '${health.ageYears} years',
                        ),
                        PatientCompactInfoRow(
                          label: 'Gender',
                          value: health.gender.label,
                        ),
                        PatientCompactInfoRow(
                          label: 'Blood type',
                          value: health.bloodType.label,
                        ),
                        PatientCompactInfoRow(
                          label: 'BMI',
                          value:
                              '${health.bmi.toStringAsFixed(1)} (${health.bmiCategory})',
                        ),
                        PatientCompactInfoRow(
                          label: 'Height / Weight',
                          value:
                              '${health.heightCm.toStringAsFixed(0)} cm · ${health.weightKg.toStringAsFixed(0)} kg',
                        ),
                        if (health.address != null &&
                            health.address!.isNotEmpty)
                          PatientCompactInfoRow(
                            label: 'Address',
                            value: health.address!,
                          ),
                        PatientCompactInfoRow(
                          label: 'Conditions',
                          value: health.chronicConditions.join(', '),
                        ),
                        PatientCompactInfoRow(
                          label: 'Allergies',
                          value: health.noKnownAllergies
                              ? 'None known'
                              : health.allergies.isEmpty
                              ? 'Not recorded'
                              : health.allergies.join(', '),
                        ),
                        PatientCompactInfoRow(
                          label: 'Medications',
                          value: health.noCurrentMedications
                              ? 'None'
                              : health.currentMedications.isEmpty
                              ? 'Not recorded'
                              : health.currentMedications.join(', '),
                        ),
                        Divider(height: 1, color: AppPalette.border(context)),
                        PatientCompactToggleRow(
                          label: 'Location consent for SOS',
                          subtitle: 'Allow sharing GPS during emergencies',
                          value: health.locationConsent,
                          onChanged: (v) {
                            if (user == null) {
                              AppToast.error(context, 'Sign in required.');
                              return;
                            }
                            _updateLocationConsent(context, user, v);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 6,
                child: SectionLabel(
                  title: 'Monitoring',
                  icon: AppIcons.vitals,
                  trailing: tracked.isEmpty ? null : '${tracked.length} vitals',
                  actionLabel: 'Edit',
                  onAction: () => _MonitoringSheet.show(context),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 7,
                child: _MonitoringCard(tracked: tracked),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 8,
                child: SectionLabel(
                  title: 'Emergency contacts',
                  icon: AppIcons.sos,
                  trailing: contacts.isEmpty ? null : '${contacts.length}',
                  actionLabel: 'Add',
                  onAction: () => _AddContactSheet.show(context),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 9,
                child: contacts.isEmpty
                    ? GlassCard(
                        frosted: true,
                        child: EmptyStateView(
                          icon: AppIcons.phone,
                          title: 'No emergency contacts',
                          message: 'Add someone we can reach in an emergency.',
                          actionLabel: 'Add contact',
                          onAction: () => _AddContactSheet.show(context),
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
              StaggeredEntry(index: 10, child: const ProfileSecuritySection()),
              SizedBox(height: tier.isHandheld ? 24 : AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }
}

/// Shows the vitals currently being monitored for this patient. Vitals a
/// clinician assigned are flagged as locked; the rest are self-selected.
class _MonitoringCard extends StatelessWidget {
  const _MonitoringCard({required this.tracked});
  final List<VitalKey> tracked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (tracked.isEmpty) {
      return GlassCard(
        frosted: true,
        child: EmptyStateView(
          icon: AppIcons.vitals,
          title: 'No vitals monitored yet',
          message: 'Choose the vitals you want mCare to keep an eye on.',
          actionLabel: 'Set up monitoring',
          onAction: () => _MonitoringSheet.show(context),
          compact: true,
        ),
      );
    }
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'mCare is monitoring these vitals for you.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final v in tracked)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: v.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                    border: Border.all(color: v.accent.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(v.icon, size: 13, color: v.accent),
                      const SizedBox(width: 5),
                      Text(
                        v.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: v.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                        ),
                      ),
                      if (VitalsState.instance.isAssigned(v)) ...[
                        const SizedBox(width: 4),
                        Icon(AppIcons.lock, size: 10, color: v.accent),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonitoringSheet {
  _MonitoringSheet._();
  static Future<void> show(BuildContext context) {
    return GlassSheet.show(
      context,
      title: 'Edit monitoring',
      subtitle: 'Choose which vitals mCare tracks for you.',
      child: const _MonitoringForm(),
    );
  }
}

class _MonitoringForm extends StatefulWidget {
  const _MonitoringForm();

  @override
  State<_MonitoringForm> createState() => _MonitoringFormState();
}

class _MonitoringFormState extends State<_MonitoringForm> {
  late final Set<VitalKey> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = {...VitalsState.instance.tracked};
  }

  Future<void> _save() async {
    final user = AuthState.instance.user;
    if (user == null) {
      AppToast.error(context, 'Sign in required.');
      return;
    }
    if (_selected.isEmpty) {
      AppToast.warn(context, 'Select at least one vital to monitor.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ProfileService.updateMonitoring(
        editor: user,
        assignedVitals: _selected.toList(),
      );
      if (!mounted) return;
      AppToast.success(context, 'Monitoring plan updated.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Could not update monitoring: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectable = VitalsState.instance.selectableVitals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          frosted: true,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Column(
            children: [
              for (final v in selectable)
                PatientCompactToggleRow(
                  label: v.label,
                  subtitle: VitalsState.instance.isAssigned(v)
                      ? 'Assigned by your care team'
                      : v.unit,
                  value: _selected.contains(v),
                  onChanged: (on) {
                    if (!on && VitalsState.instance.isAssigned(v)) {
                      AppToast.info(
                        context,
                        'This vital was assigned by your care team.',
                      );
                      return;
                    }
                    setState(() {
                      if (on) {
                        _selected.add(v);
                      } else {
                        _selected.remove(v);
                      }
                    });
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Save monitoring',
          icon: AppIcons.check,
          expand: true,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

class _CompletionSheet {
  _CompletionSheet._();

  static Future<void> show(
    BuildContext context,
    ProfileCompletionResult result,
  ) {
    return GlassSheet.show(
      context,
      title: 'Profile completion',
      subtitle: result.isComplete
          ? 'Your profile is 100% complete.'
          : 'Complete these items to reach 100%.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ProfileCompletionHeart(
              percent: result.percent,
              size: 72,
              showLabel: true,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final item in result.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(
                    item.complete ? AppIcons.check : AppIcons.alert,
                    size: 18,
                    color: item.complete
                        ? AppColors.success
                        : AppPalette.textMuted(context),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      item.label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    item.complete ? 'Done' : '${item.weight}%',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: item.complete
                          ? AppColors.success
                          : AppPalette.textMuted(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
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

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact});
  final EmergencyContact contact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = AuthState.instance.user;
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
          if (user != null)
            AppButton.icon(
              icon: AppIcons.delete,
              semanticLabel: 'Remove',
              onPressed: () => _confirmRemove(context, user),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, AppUser user) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Remove ${contact.name}?',
      message:
          'This emergency contact will no longer be called during an SOS. You can add them again anytime.',
      danger: true,
      icon: AppIcons.delete,
      iconActionOnly: true,
    );
    if (ok != true || !context.mounted) return;
    try {
      await ProfileService.removeEmergencyContact(
        editor: user,
        contactId: contact.id,
        contactName: contact.name,
      );
      if (!context.mounted) return;
      AppToast.success(context, '${contact.name} removed.');
    } catch (e) {
      if (!context.mounted) return;
      AppToast.error(context, 'Could not remove contact: $e');
    }
  }
}

class _AddContactSheet {
  _AddContactSheet._();
  static Future<void> show(BuildContext context) {
    return GlassSheet.show(
      context,
      title: 'Add emergency contact',
      subtitle: 'Someone we can call in an emergency.',
      child: const _AddContactForm(),
    );
  }
}

class _AddContactForm extends StatefulWidget {
  const _AddContactForm();

  @override
  State<_AddContactForm> createState() => _AddContactFormState();
}

class _AddContactFormState extends State<_AddContactForm> {
  final _name = TextEditingController();
  final _relationship = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _relationship.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = AuthState.instance.user;
    if (user == null) {
      AppToast.error(context, 'Sign in required.');
      return;
    }
    if (_name.text.trim().isEmpty) {
      AppToast.warn(context, 'Name is required.');
      return;
    }
    if (_phone.text.trim().length < 7) {
      AppToast.warn(context, 'Enter a valid phone number.');
      return;
    }
    final email = _email.text.trim();
    if (email.isNotEmpty && !email.contains('@')) {
      AppToast.warn(context, 'Enter a valid email address.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ProfileService.addEmergencyContact(
        editor: user,
        contact: EmergencyContact(
          id: 'ec_${DateTime.now().millisecondsSinceEpoch}',
          name: _name.text.trim(),
          relationship: _relationship.text.trim().isEmpty
              ? 'Contact'
              : _relationship.text.trim(),
          phone: _phone.text.trim(),
          email: email.isEmpty ? null : email,
          priority: ProfileState.instance.emergencyContacts.length + 1,
        ),
      );
      if (!mounted) return;
      AppToast.success(context, 'Emergency contact added.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Could not save contact: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Name',
          hint: 'Full name',
          controller: _name,
          prefixIcon: AppIcons.user,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Relationship',
          hint: 'e.g. Spouse, Parent',
          controller: _relationship,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Phone',
          hint: 'Mobile number',
          controller: _phone,
          keyboardType: TextInputType.phone,
          prefixIcon: AppIcons.phone,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Email (optional)',
          hint: 'name@example.com',
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          prefixIcon: AppIcons.email,
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Save contact',
          icon: AppIcons.add,
          expand: true,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}
