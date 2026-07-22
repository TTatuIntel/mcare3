import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/web/web_platform.dart' as web_platform;
import '../models/sos.dart';
import '../state/staff_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/glass_card.dart';

/// Patient identity, direct contacts, emergency contacts, and SOS location —
/// shared across doctor workspace, SOS hub, and respond sheets.
class SosRespondContextCard extends StatelessWidget {
  const SosRespondContextCard({
    super.key,
    required this.patientId,
    this.event,
    this.compact = false,
  });

  final String patientId;
  final StaffPatientSos? event;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final patient = StaffState.instance.patientById(patientId);
    final detail = StaffState.instance.patientClinicalDetail(patientId);
    final theme = Theme.of(context);

    if (patient == null) {
      return GlassCard(
        frosted: true,
        child: Text(
          'Loading patient details…',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    final health = detail?.health;
    final address = health?.address?.trim();
    final conditions = health?.chronicConditions ?? const [];
    final allergies = health?.allergies ?? const [];
    final contacts = List<EmergencyContact>.from(
      detail?.emergencyContacts ?? const [],
    )..sort((a, b) => a.priority.compareTo(b.priority));

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      border: Border.all(color: AppColors.critical.withOpacity(0.35)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PatientAvatar(name: patient.name),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${patient.age} · ${patient.sex}'
                      '${detail?.uniqueId != null ? ' · ${detail!.uniqueId}' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                    if (patient.condition.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          patient.condition,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (conditions.isNotEmpty || allergies.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final c in conditions)
                  _InfoChip(
                    label: c,
                    icon: AppIcons.heartRate,
                    color: AppColors.info,
                  ),
                for (final a in allergies)
                  _InfoChip(
                    label: 'Allergy: $a',
                    icon: AppIcons.alert,
                    color: AppColors.warning,
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _SectionTitle(icon: AppIcons.profile, label: 'Patient contact'),
          const SizedBox(height: AppSpacing.xs),
          if (detail?.phone != null && detail!.phone!.trim().isNotEmpty)
            _ContactActionRow(
              icon: AppIcons.phone,
              title: 'Patient phone',
              subtitle: detail.phone!,
              actionLabel: 'Call',
              onAction: () => SosContactActions.call(detail.phone!),
            ),
          if (detail?.email != null && detail!.email!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            _ContactActionRow(
              icon: AppIcons.email,
              title: 'Patient email',
              subtitle: detail.email!,
              actionLabel: 'Email',
              onAction: () => SosContactActions.email(detail.email!),
            ),
          ],
          if ((detail?.phone?.trim().isEmpty ?? true) &&
              (detail?.email?.trim().isEmpty ?? true))
            Text(
              'No direct patient contact on file.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
          if (address != null && address.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _ContactActionRow(
              icon: AppIcons.homeAddress,
              title: 'Home address',
              subtitle: address,
            ),
          ],
          if (event != null) ...[
            const SizedBox(height: AppSpacing.md),
            _SectionTitle(icon: AppIcons.location, label: 'SOS location'),
            const SizedBox(height: AppSpacing.xs),
            if (event!.locationLabel != null)
              _ContactActionRow(
                icon: AppIcons.location,
                title: 'Reported location',
                subtitle: event!.locationLabel!,
                actionLabel: event!.mapsUrl != null ? 'Open map' : null,
                onAction:
                    event!.mapsUrl != null ? () => SosContactActions.map(event!.mapsUrl!) : null,
              )
            else
              Text(
                'No GPS location shared for this alert.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppPalette.textMuted(context),
                ),
              ),
            if (!compact && event!.mapsUrl != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Open in Google Maps',
                icon: AppIcons.map,
                variant: AppButtonVariant.secondary,
                expand: true,
                onPressed: () => SosContactActions.map(event!.mapsUrl!),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.md),
          _SectionTitle(
            icon: AppIcons.sos,
            label: 'Emergency contacts',
            trailing: contacts.isEmpty ? null : '${contacts.length}',
          ),
          const SizedBox(height: AppSpacing.xs),
          if (contacts.isEmpty)
            Text(
              'No emergency contacts on file — use patient phone above.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            )
          else
            for (var i = 0; i < contacts.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.xs),
              _EmergencyContactRow(contact: contacts[i]),
            ],
        ],
      ),
    );
  }
}

class SosContactActions {
  SosContactActions._();

  static void call(String phone) {
    final normalized = phone.replaceAll(RegExp(r'\s+'), '');
    if (kIsWeb) {
      web_platform.openWindow('tel:$normalized', '_self');
    }
  }

  static void email(String address) {
    if (kIsWeb) {
      web_platform.openWindow('mailto:$address', '_self');
    }
  }

  static void map(String url) {
    if (kIsWeb) {
      web_platform.openWindow(url, '_blank');
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.label,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppPalette.textMuted(context)),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
        ),
        if (trailing != null) ...[
          const Spacer(),
          Text(
            trailing!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.textFaint(context),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ],
    );
  }
}

class _PatientAvatar extends StatelessWidget {
  const _PatientAvatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : (parts.isEmpty ? '?' : parts.first[0].toUpperCase());

    return Container(
      height: 44,
      width: 44,
      decoration: BoxDecoration(
        color: AppPalette.criticalSoft(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: AppColors.critical.withOpacity(0.35)),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: AppColors.critical,
          fontWeight: FontWeight.w900,
          fontSize: 15,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
          ),
        ],
      ),
    );
  }
}

class _ContactActionRow extends StatelessWidget {
  const _ContactActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppPalette.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _EmergencyContactRow extends StatelessWidget {
  const _EmergencyContactRow({required this.contact});
  final EmergencyContact contact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppPalette.criticalSoft(context).withOpacity(0.35),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.critical.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(AppIcons.phone, size: 16, color: AppColors.critical),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  contact.relationship,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontSize: 10,
                      ),
                ),
                Text(
                  contact.phone,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (contact.email != null && contact.email!.isNotEmpty)
                  Text(
                    contact.email!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.info,
                          fontSize: 10,
                        ),
                  ),
              ],
            ),
          ),
          Column(
            children: [
              TextButton(
                onPressed: () => SosContactActions.call(contact.phone),
                child: const Text('Call'),
              ),
              if (contact.email != null && contact.email!.isNotEmpty)
                TextButton(
                  onPressed: () => SosContactActions.email(contact.email!),
                  child: const Text('Email'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
