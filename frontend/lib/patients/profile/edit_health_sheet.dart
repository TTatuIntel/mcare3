import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/auth/auth_state.dart';
import '../../shared/models/app_user.dart';
import '../../shared/models/patient_profile.dart';
import '../../shared/services/profile_service.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/state/profile_state.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_sheet.dart';

class EditHealthSheet {
  EditHealthSheet._();

  static Future<void> show(BuildContext context) {
    final health = ProfileState.instance.health;
    final user = AuthState.instance.user;
    if (health == null || user == null) return Future.value();
    return GlassSheet.show(
      context,
      title: 'Edit health profile',
      subtitle: 'Updates notify you and your care team.',
      child: _EditHealthForm(initial: health, editor: user),
    );
  }
}

class _EditHealthForm extends StatefulWidget {
  const _EditHealthForm({required this.initial, required this.editor});
  final PatientHealthProfile initial;
  final AppUser editor;

  @override
  State<_EditHealthForm> createState() => _EditHealthFormState();
}

class _EditHealthFormState extends State<_EditHealthForm> {
  late DateTime _dob;
  late Gender _gender;
  late BloodType _bloodType;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _address;
  late final TextEditingController _conditions;
  late final TextEditingController _allergies;
  late final TextEditingController _medications;
  late bool _noAllergies;
  late bool _noMeds;
  late bool _locationConsent;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final h = widget.initial;
    _dob = h.dateOfBirth;
    _gender = h.gender;
    _bloodType = h.bloodType;
    _height = TextEditingController(
      text: h.heightCm.toStringAsFixed(0),
    );
    _weight = TextEditingController(
      text: h.weightKg.toStringAsFixed(0),
    );
    _address = TextEditingController(text: h.address ?? '');
    _conditions = TextEditingController(text: h.chronicConditions.join(', '));
    _allergies = TextEditingController(text: h.allergies.join(', '));
    _medications =
        TextEditingController(text: h.currentMedications.join(', '));
    _noAllergies = h.noKnownAllergies;
    _noMeds = h.noCurrentMedications;
    _locationConsent = h.locationConsent;
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _address.dispose();
    _conditions.dispose();
    _allergies.dispose();
    _medications.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob,
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  List<String> _split(String raw) {
    if (raw.trim().isEmpty) return [];
    return raw
        .split(RegExp(r'[,;]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<void> _save() async {
    final height = double.tryParse(_height.text.trim());
    final weight = double.tryParse(_weight.text.trim());
    if (height == null || height < 50 || height > 250) {
      AppToast.warn(context, 'Enter a valid height (cm).');
      return;
    }
    if (weight == null || weight < 20 || weight > 300) {
      AppToast.warn(context, 'Enter a valid weight (kg).');
      return;
    }

    final conditions = _split(_conditions.text);
    if (conditions.isEmpty) {
      AppToast.warn(context, 'Add at least one condition or wellness note.');
      return;
    }

    final allergies = _noAllergies ? <String>[] : _split(_allergies.text);
    final meds = _noMeds ? <String>[] : _split(_medications.text);

    final updated = PatientHealthProfile(
      bloodType: _bloodType,
      gender: _gender,
      dateOfBirth: _dob,
      heightCm: height,
      weightKg: weight,
      allergies: allergies,
      chronicConditions: conditions,
      currentMedications: meds,
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      locationConsent: _locationConsent,
      noKnownAllergies: _noAllergies,
      noCurrentMedications: _noMeds,
    );

    setState(() => _saving = true);
    await ProfileService.updateHealthProfile(
      editor: widget.editor,
      health: updated,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    AppToast.success(context, 'Health profile saved.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          OutlinedButton.icon(
            onPressed: _pickDob,
            icon: const Icon(AppIcons.calendar, size: 18),
            label: Text(
              'Birth date: ${_dob.month}/${_dob.day}/${_dob.year}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Gender', style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: Gender.values.map((g) {
              return ChoiceChip(
                label: Text(g.label, style: const TextStyle(fontSize: 12)),
                selected: _gender == g,
                onSelected: (_) => setState(() => _gender = g),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Blood type', style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: BloodType.values.map((b) {
              return ChoiceChip(
                label: Text(b.label, style: const TextStyle(fontSize: 11)),
                selected: _bloodType == b,
                onSelected: (_) => setState(() => _bloodType = b),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Height (cm)',
                  controller: _height,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppTextField(
                  label: 'Weight (kg)',
                  controller: _weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Home address',
            controller: _address,
            hint: 'City, country',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Conditions',
            controller: _conditions,
            hint: 'Comma-separated',
          ),
          const SizedBox(height: AppSpacing.lg),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('No known allergies', style: TextStyle(fontSize: 13)),
            value: _noAllergies,
            activeThumbColor: AppColors.brandIndigo,
            onChanged: (v) => setState(() => _noAllergies = v),
          ),
          if (!_noAllergies)
            AppTextField(
              label: 'Allergies',
              controller: _allergies,
              hint: 'Comma-separated',
            ),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('No current medications', style: TextStyle(fontSize: 13)),
            value: _noMeds,
            activeThumbColor: AppColors.brandIndigo,
            onChanged: (v) => setState(() => _noMeds = v),
          ),
          if (!_noMeds)
            AppTextField(
              label: 'Medications',
              controller: _medications,
              hint: 'Comma-separated',
            ),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Share location during SOS',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: const Text(
              'Allow sharing GPS with responders in an emergency',
              style: TextStyle(fontSize: 11),
            ),
            value: _locationConsent,
            activeThumbColor: AppColors.brandIndigo,
            onChanged: (v) => setState(() => _locationConsent = v),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Save health profile',
            icon: AppIcons.check,
            expand: true,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
    );
  }
}
