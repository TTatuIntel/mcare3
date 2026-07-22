import 'package:flutter/material.dart';

import '../../shared/models/support_ticket.dart';
import '../../shared/state/support_state.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_sheet.dart';

class CreateTicketSheet {
  CreateTicketSheet._();

  static Future<void> show(BuildContext context) {
    return GlassSheet.show(
      context,
      title: 'New support ticket',
      subtitle: 'We usually respond within an hour.',
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
  final _subject = TextEditingController();
  final _description = TextEditingController();
  TicketCategory _category = TicketCategory.technical;
  TicketPriority _priority = TicketPriority.normal;
  bool _saving = false;

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_subject.text.trim().isEmpty || _description.text.trim().isEmpty) {
      AppToast.warn(context, 'Subject and description are required.');
      return;
    }
    setState(() => _saving = true);
    try {
      await SupportState.instance.createRemote(
        subject: _subject.text.trim(),
        description: _description.text.trim(),
        category: _category,
        priority: _priority,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.warn(context, 'Could not submit: $e');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.success(context, 'Ticket submitted — we\'ll be in touch soon.');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Subject',
          controller: _subject,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'Description',
          controller: _description,
          maxLines: 4,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Category', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<TicketCategory>(
          value: _category,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: TicketCategory.values
              .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _category = v);
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Priority', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: TicketPriority.values.map((p) {
            return ChoiceChip(
              label: Text(p.label),
              selected: _priority == p,
              onSelected: (_) => setState(() => _priority = p),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Submit ticket',
          icon: AppIcons.support,
          loading: _saving,
          expand: true,
          onPressed: _submit,
        ),
      ],
    );
  }
}
