import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/services/patient_session_service.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/chronic_condition_catalog.dart';
import '../../shared/models/patient_profile.dart';
import '../../shared/models/sos.dart';
import '../../shared/models/vital.dart';
import '../../shared/navigation/root_navigator.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/patient_scaffold.dart';

/// First-time patient setup after account creation.
class PatientOnboardingView extends StatefulWidget {
  const PatientOnboardingView({super.key});

  @override
  State<PatientOnboardingView> createState() => _PatientOnboardingViewState();
}

class _PatientOnboardingViewState extends State<PatientOnboardingView> {
  static const _totalSteps = 6;
  int _step = 0;
  bool _saving = false;

  DateTime _dob = DateTime(1990, 1, 1);
  Gender _gender = Gender.female;
  BloodType _bloodType = BloodType.unknown;
  final _height = TextEditingController(text: '165');
  final _weight = TextEditingController(text: '68');
  final _address = TextEditingController();

  final Set<String> _conditions = {};
  final _allergies = TextEditingController();
  final _medications = TextEditingController();

  final _contactName = TextEditingController();
  final _contactRelation = TextEditingController(text: 'Spouse');
  final _contactPhone = TextEditingController();
  final _contactEmail = TextEditingController();

  bool _locationConsent = true;
  final Set<VitalKey> _trackedVitals = {};

  @override
  void initState() {
    super.initState();
    _conditions.add('general');
    _syncVitalsFromConditions();
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _address.dispose();
    _allergies.dispose();
    _medications.dispose();
    _contactName.dispose();
    _contactRelation.dispose();
    _contactPhone.dispose();
    _contactEmail.dispose();
    super.dispose();
  }

  void _syncVitalsFromConditions() {
    _trackedVitals
      ..clear()
      ..addAll(ChronicConditionCatalog.vitalsForConditions(_conditions));
  }

  void _toggleCondition(String id) {
    setState(() {
      if (_conditions.contains(id)) {
        _conditions.remove(id);
        if (_conditions.isEmpty) _conditions.add('general');
      } else {
        _conditions.add(id);
      }
      _syncVitalsFromConditions();
    });
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

  bool _validateCurrentStep() {
    switch (_step) {
      case 1:
        final h = double.tryParse(_height.text.trim());
        final w = double.tryParse(_weight.text.trim());
        if (h == null || h < 50 || h > 250) {
          AppToast.warn(context, 'Enter a valid height (cm).');
          return false;
        }
        if (w == null || w < 20 || w > 300) {
          AppToast.warn(context, 'Enter a valid weight (kg).');
          return false;
        }
        return true;
      case 2:
        if (_conditions.isEmpty) {
          AppToast.warn(context, 'Select at least one condition or wellness.');
          return false;
        }
        return true;
      case 4:
        if (_contactName.text.trim().isEmpty ||
            _contactPhone.text.trim().length < 7) {
          AppToast.warn(
            context,
            'Add an emergency contact with a valid phone.',
          );
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _next() {
    if (!_validateCurrentStep()) return;
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    final heightCm = double.parse(_height.text.trim());
    final weightKg = double.parse(_weight.text.trim());
    final allergies = _splitList(_allergies.text);
    final meds = _splitList(_medications.text);
    final conditionLabels = ChronicConditionCatalog.labelsForIds(_conditions);

    final health = PatientHealthProfile(
      bloodType: _bloodType,
      gender: _gender,
      dateOfBirth: _dob,
      heightCm: heightCm,
      weightKg: weightKg,
      allergies: allergies,
      chronicConditions: conditionLabels,
      currentMedications: meds,
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      locationConsent: _locationConsent,
      noKnownAllergies: allergies.isEmpty,
      noCurrentMedications: meds.isEmpty,
    );

    final contact = EmergencyContact(
      id: 'ec_${DateTime.now().millisecondsSinceEpoch}',
      name: _contactName.text.trim(),
      relationship: _contactRelation.text.trim().isEmpty
          ? 'Contact'
          : _contactRelation.text.trim(),
      phone: _contactPhone.text.trim(),
      email: _contactEmail.text.trim().isEmpty
          ? null
          : _contactEmail.text.trim(),
      priority: 1,
    );

    final assigned = _trackedVitals.toList();

    await PatientSessionService.instance.completeOnboarding(
      health: health,
      contacts: [contact],
      assignedVitals: assigned,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    final user = AuthState.instance.user;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(RouteNames.patientDashboard, (_) => false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final root = rootNavigatorKey.currentContext;
      if (root != null && user != null) {
        AppToast.success(
          root,
          'Welcome to mCare, ${user.firstName}! Your profile is ready.',
        );
      }
    });
  }

  List<String> _splitList(String raw) {
    if (raw.trim().isEmpty) return [];
    return raw
        .split(RegExp(r'[,;]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthState.instance.user;

    return PatientScaffold(
      currentRoute: RouteNames.patientOnboarding,
      detachedNav: true,
      scrollable: false,
      title: 'Get started',
      subtitle: 'Set up your health profile',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepProgress(step: _step, total: _totalSteps),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _buildStep(context, user?.firstName ?? 'there'),
              ),
            ),
          ),
          Row(
            children: [
              if (_step > 0)
                Expanded(
                  child: AppButton(
                    label: 'Back',
                    variant: AppButtonVariant.secondary,
                    onPressed: _saving ? null : _back,
                  ),
                ),
              if (_step > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: _step == 0 ? 1 : 1,
                child: AppButton(
                  label: _step == _totalSteps - 1
                      ? 'Go to dashboard'
                      : _step == 0
                      ? 'Get started'
                      : 'Continue',
                  loading: _saving,
                  expand: true,
                  onPressed: _saving ? null : _next,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep(BuildContext context, String firstName) {
    switch (_step) {
      case 0:
        return _WelcomeStep(firstName: firstName, key: const ValueKey(0));
      case 1:
        return _PersonalStep(
          key: const ValueKey(1),
          dob: _dob,
          gender: _gender,
          bloodType: _bloodType,
          height: _height,
          weight: _weight,
          address: _address,
          onPickDob: _pickDob,
          onGender: (g) => setState(() => _gender = g),
          onBloodType: (b) => setState(() => _bloodType = b),
        );
      case 2:
        return _ConditionsStep(
          key: const ValueKey(2),
          selected: _conditions,
          onToggle: _toggleCondition,
        );
      case 3:
        return _AllergiesStep(
          key: const ValueKey(3),
          allergies: _allergies,
          medications: _medications,
        );
      case 4:
        return _EmergencyStep(
          key: const ValueKey(4),
          name: _contactName,
          relationship: _contactRelation,
          phone: _contactPhone,
          email: _contactEmail,
        );
      case 5:
        return _MonitoringStep(
          key: const ValueKey(5),
          vitals: _trackedVitals,
          locationConsent: _locationConsent,
          onLocation: (v) => setState(() => _locationConsent = v),
          onToggleVital: (v) {
            setState(() {
              if (_trackedVitals.contains(v)) {
                _trackedVitals.remove(v);
              } else {
                _trackedVitals.add(v);
              }
            });
          },
        );
      default:
        return const SizedBox.shrink(key: ValueKey('x'));
    }
  }
}

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = [
      'Welcome',
      'About you',
      'Conditions',
      'Allergies',
      'Emergency',
      'Monitoring',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          child: LinearProgressIndicator(
            value: (step + 1) / total,
            minHeight: 6,
            backgroundColor: AppPalette.border(context),
            color: AppColors.brandIndigo,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Step ${step + 1} of $total · ${labels[step]}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            fontWeight: FontWeight.w600,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({super.key, required this.firstName});
  final String firstName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          frosted: true,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  color: AppColors.brandIndigo.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Icon(
                  AppIcons.vitals,
                  color: AppColors.brandIndigo,
                  size: 28,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Welcome, $firstName!',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Let\'s personalise mCare for your health needs. '
                'This takes about 3 minutes and helps your care team '
                'monitor the right vitals for you.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppPalette.textMuted(context),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        GlassCard(
          frosted: true,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Bullet(
                icon: AppIcons.vitals,
                text: 'Track vitals that match your conditions',
              ),
              _Bullet(
                icon: AppIcons.alert,
                text: 'Get alerts when readings need attention',
              ),
              _Bullet(
                icon: AppIcons.sos,
                text: 'Add emergency contacts for SOS',
              ),
              _Bullet(
                icon: AppIcons.careTeam,
                text: 'Connect with your care team',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.brandIndigo),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalStep extends StatelessWidget {
  const _PersonalStep({
    super.key,
    required this.dob,
    required this.gender,
    required this.bloodType,
    required this.height,
    required this.weight,
    required this.address,
    required this.onPickDob,
    required this.onGender,
    required this.onBloodType,
  });

  final DateTime dob;
  final Gender gender;
  final BloodType bloodType;
  final TextEditingController height;
  final TextEditingController weight;
  final TextEditingController address;
  final VoidCallback onPickDob;
  final ValueChanged<Gender> onGender;
  final ValueChanged<BloodType> onBloodType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tell us about you',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Basic details for your health profile and BMI.',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          onPressed: onPickDob,
          icon: const Icon(AppIcons.calendar, size: 18),
          label: Text(
            'Birth date: ${dob.month}/${dob.day}/${dob.year}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Gender', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: Gender.values.map((g) {
            return ChoiceChip(
              label: Text(g.label, style: const TextStyle(fontSize: 12)),
              selected: gender == g,
              onSelected: (_) => onGender(g),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Blood type', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<BloodType>(
          value: bloodType,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: BloodType.values
              .map((b) => DropdownMenuItem(value: b, child: Text(b.label)))
              .toList(),
          onChanged: (v) => v != null ? onBloodType(v) : null,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                label: 'Height (cm)',
                controller: height,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppTextField(
                label: 'Weight (kg)',
                controller: weight,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Address (optional)',
          hint: 'City, region',
          controller: address,
        ),
      ],
    );
  }
}

class _ConditionsStep extends StatelessWidget {
  const _ConditionsStep({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your health conditions',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Select all that apply. We\'ll recommend vitals to track.',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ...ChronicConditionCatalog.all.map((opt) {
          final isOn = selected.contains(opt.id);
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onToggle(opt.id),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                child: GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Icon(
                        isOn ? AppIcons.check : AppIcons.add,
                        size: 18,
                        color: isOn
                            ? AppColors.brandIndigo
                            : AppPalette.textMuted(context),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              opt.label,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                            ),
                            Text(
                              opt.description,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: AppPalette.textMuted(context),
                                    fontSize: 10,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _AllergiesStep extends StatelessWidget {
  const _AllergiesStep({
    super.key,
    required this.allergies,
    required this.medications,
  });

  final TextEditingController allergies;
  final TextEditingController medications;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Allergies & medications',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Separate items with commas. Leave blank if none.',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Allergies',
          hint: 'e.g. Penicillin, Peanuts',
          controller: allergies,
          maxLines: 2,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Current medications',
          hint: 'e.g. Metformin, Lisinopril',
          controller: medications,
          maxLines: 3,
        ),
      ],
    );
  }
}

class _EmergencyStep extends StatelessWidget {
  const _EmergencyStep({
    super.key,
    required this.name,
    required this.relationship,
    required this.phone,
    required this.email,
  });

  final TextEditingController name;
  final TextEditingController relationship;
  final TextEditingController phone;
  final TextEditingController email;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Emergency contact',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Someone we can reach if you trigger SOS.',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Full name',
          controller: name,
          prefixIcon: AppIcons.user,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(label: 'Relationship', controller: relationship),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Phone',
          controller: phone,
          keyboardType: TextInputType.phone,
          prefixIcon: AppIcons.phone,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Email (optional)',
          controller: email,
          keyboardType: TextInputType.emailAddress,
          prefixIcon: AppIcons.email,
        ),
      ],
    );
  }
}

class _MonitoringStep extends StatelessWidget {
  const _MonitoringStep({
    super.key,
    required this.vitals,
    required this.locationConsent,
    required this.onLocation,
    required this.onToggleVital,
  });

  final Set<VitalKey> vitals;
  final bool locationConsent;
  final ValueChanged<bool> onLocation;
  final ValueChanged<VitalKey> onToggleVital;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your monitoring plan',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Based on your conditions. You can change these later.',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        GlassCard(
          frosted: true,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            children: VitalKey.values.map((v) {
              final on = vitals.contains(v);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(v.icon, size: 16, color: v.accent),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        v.label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Switch(
                      value: on,
                      onChanged: (_) => onToggleVital(v),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        GlassCard(
          frosted: true,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: PatientCompactToggleRow(
            label: 'Share location during SOS',
            subtitle: 'Helps responders find you in an emergency',
            value: locationConsent,
            onChanged: onLocation,
          ),
        ),
      ],
    );
  }
}
