import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/api/profile_api.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_state.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';
import '../services/profile_service.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_text_field.dart';
import '../widgets/app_toast.dart';
import '../widgets/glass_sheet.dart';
import 'change_email_sheet.dart';
import '../widgets/loading/loading.dart';

/// Role-agnostic account editor: photo, name, phone, email, and — for
/// clinicians — specialty and licence number.
class EditAccountSheet {
  EditAccountSheet._();

  static Future<void> show(BuildContext context) {
    final user = AuthState.instance.user;
    if (user == null) return Future.value();
    return GlassSheet.show(
      context,
      title: context.l10n.editAccount,
      subtitle: context.l10n.editAccountSub,
      child: _EditAccountForm(user: user),
    );
  }
}

class _EditAccountForm extends StatefulWidget {
  const _EditAccountForm({required this.user});
  final AppUser user;

  @override
  State<_EditAccountForm> createState() => _EditAccountFormState();
}

class _EditAccountFormState extends State<_EditAccountForm> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;
  late final TextEditingController _specialty;
  late final TextEditingController _license;
  bool _saving = false;
  bool _photoBusy = false;

  bool get _isDoctor => widget.user.role == UserRole.doctor;

  @override
  void initState() {
    super.initState();
    _firstName = TextEditingController(text: widget.user.firstName);
    _lastName = TextEditingController(text: widget.user.lastName);
    _phone = TextEditingController(text: widget.user.phone ?? '');
    _specialty = TextEditingController(text: widget.user.specialty ?? '');
    _license = TextEditingController(text: widget.user.licenseNumber ?? '');
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _specialty.dispose();
    _license.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _photoBusy = true);
    try {
      await ProfileApi.instance.uploadAvatar(result.files.first);
      if (!mounted) return;
      AppToast.success(context, 'Photo updated.');
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, 'Could not upload photo — please retry.');
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _photoBusy = true);
    try {
      await ProfileApi.instance.removeAvatar();
      if (!mounted) return;
      AppToast.success(context, 'Photo removed.');
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, 'Could not remove photo — please retry.');
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
      AppToast.warn(context, l10n.nameRequired);
      return;
    }
    if (_phone.text.trim().length < 7) {
      AppToast.warn(context, l10n.phoneInvalid);
      return;
    }
    setState(() => _saving = true);
    try {
      await ProfileService.updateAccount(
        editor: widget.user,
        firstName: _firstName.text,
        lastName: _lastName.text,
        phone: _phone.text,
        specialty: _isDoctor ? _specialty.text : null,
        licenseNumber: _isDoctor ? _license.text : null,
      );
      if (!mounted) return;
      AppToast.success(context, l10n.accountUpdated);
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, 'Could not save account — please retry.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AvatarEditor(
          busy: _photoBusy,
          onPick: _photoBusy ? null : _pickPhoto,
          onRemove: _photoBusy ? null : _removePhoto,
        ),
        const SizedBox(height: AppSpacing.xl),
        AppTextField(
          label: l10n.firstName,
          controller: _firstName,
          prefixIcon: AppIcons.user,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: l10n.lastName,
          controller: _lastName,
          prefixIcon: AppIcons.user,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: l10n.mobilePhone,
          controller: _phone,
          keyboardType: TextInputType.phone,
          prefixIcon: AppIcons.phone,
        ),
        if (_isDoctor) ...[
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Specialty',
            controller: _specialty,
            prefixIcon: AppIcons.nurse,
            hint: 'e.g. Cardiology',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Licence number',
            controller: _license,
            prefixIcon: AppIcons.approval,
            hint: 'Professional registration number',
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _EmailRow(
          email: widget.user.email,
          verified: widget.user.emailVerified,
          onChange: () => ChangeEmailSheet.show(context),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: l10n.saveChanges,
          icon: AppIcons.check,
          expand: true,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({
    required this.busy,
    required this.onPick,
    required this.onRemove,
  });

  final bool busy;
  final VoidCallback? onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthState.instance,
      builder: (context, _) {
        final user = AuthState.instance.user;
        final accent = (user?.role ?? UserRole.patient).accent;
        final avatarUrl = user?.avatarUrl;
        final hasPhoto = avatarUrl != null && avatarUrl.isNotEmpty;
        return Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: accent.withValues(alpha: 0.15),
                  backgroundImage: hasPhoto ? NetworkImage(avatarUrl) : null,
                  child: hasPhoto
                      ? null
                      : Text(
                          user?.initials ?? '',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 22,
                          ),
                        ),
                ),
                if (busy)
                  const McarePulse(
                    size: McarePulseSize.inline,
                    semanticLabel: null,
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppButton(
                    label: hasPhoto ? 'Change photo' : 'Add photo',
                    icon: AppIcons.photo,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.sm,
                    onPressed: onPick,
                  ),
                  if (hasPhoto) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: 'Remove photo',
                      icon: AppIcons.delete,
                      variant: AppButtonVariant.ghost,
                      size: AppButtonSize.sm,
                      onPressed: onRemove,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmailRow extends StatelessWidget {
  const _EmailRow({
    required this.email,
    required this.verified,
    required this.onChange,
  });

  final String email;
  final bool verified;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Email', style: theme.textTheme.labelSmall),
              const SizedBox(height: 2),
              Text(
                email,
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
              if (!verified)
                Text(
                  'Unverified — verify to secure your account',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontSize: 10.5,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        AppButton(
          label: 'Change',
          icon: AppIcons.email,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.sm,
          onPressed: onChange,
        ),
      ],
    );
  }
}
