import 'package:flutter/material.dart';

import '../../shared/state/medications_state.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_sheet.dart';

class AddMedicationSheet {
  AddMedicationSheet._();

  static Future<void> show(BuildContext context) {
    return GlassSheet.show(
      context,
      title: 'Add medication',
      subtitle: 'Track something you are currently taking',
      child: const _Form(),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form();

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _name = TextEditingController();
  final _dosage = TextEditingController();
  final _frequency = TextEditingController();
  final _instructions = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _dosage.dispose();
    _frequency.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _dosage.text.trim().isEmpty) {
      AppToast.info(context, 'Enter name and dosage.');
      return;
    }
    setState(() => _saving = true);
    try {
      await MedicationsState.instance.addPatientMedicationRemote(
        name: _name.text.trim(),
        dosage: _dosage.text.trim(),
        frequency: _frequency.text.trim().isEmpty
            ? 'As needed'
            : _frequency.text.trim(),
        instructions: _instructions.text.trim().isEmpty
            ? null
            : _instructions.text.trim(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.warn(context, 'Could not save: $e');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.success(context, 'Medication added to your list.');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Medication name',
          hint: 'e.g. Vitamin D',
          controller: _name,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Dosage',
          hint: 'e.g. 1000 IU',
          controller: _dosage,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'How often',
          hint: 'e.g. Once daily',
          controller: _frequency,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Instructions (optional)',
          hint: 'e.g. Take with breakfast',
          controller: _instructions,
          maxLines: 2,
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Add to my meds',
          loading: _saving,
          expand: true,
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}
