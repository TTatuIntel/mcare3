import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/models/care_provider.dart';
import '../../shared/models/document.dart';
import '../../shared/models/document_request.dart';
import '../../shared/state/care_state.dart';
import '../../shared/state/document_requests_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_sheet.dart';

/// Ask the care team — or one named doctor — for a document.
///
/// The record only ever moved one way: patients uploaded, clinicians filed,
/// and a patient who needed a referral letter or a copy of an old discharge
/// summary rang the desk and hoped. Nothing about the ask was recorded, so
/// nobody could see it was outstanding and nobody could be shown to have
/// answered it.
///
/// Naming a doctor is offered because patients think in people, not queues —
/// but it says who the request is *waiting on*, not who may answer it. The
/// whole team still sees it, which is what stops a request being stranded
/// behind one clinician's annual leave.
class RequestDocumentSheet {
  RequestDocumentSheet._();

  static Future<void> show(
    BuildContext context, {
    DocumentCategory? initialCategory,
  }) {
    return GlassSheet.show(
      context,
      title: 'Request a document',
      subtitle: 'Ask your care team for something that is not in your records',
      child: _Form(initialCategory: initialCategory),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({this.initialCategory});

  final DocumentCategory? initialCategory;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _title = TextEditingController();
  final _note = TextEditingController();

  late DocumentCategory _category =
      widget.initialCategory ?? DocumentCategory.referral;
  DocumentRequestTarget _target = DocumentRequestTarget.team;
  CareProvider? _doctor;
  DateTime? _neededBy;
  bool _saving = false;

  /// Only clinicians actually on the patient's team. Offering the full
  /// directory would let them address a request the server is bound to refuse
  /// — the doctor would never see it, and the patient would be waiting on
  /// nobody.
  List<CareProvider> get _team => CareState.instance.assigned
      .where((p) => p.userId != null)
      .toList(growable: false);

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickNeededBy() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _neededBy ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'When do you need it by?',
    );
    if (picked == null || !mounted) return;
    setState(() => _neededBy = picked);
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      AppToast.info(context, 'Say what you need — a letter, a copy, a form.');
      return;
    }
    if (_target == DocumentRequestTarget.doctor && _doctor == null) {
      AppToast.info(context, 'Choose which doctor you are asking.');
      return;
    }

    setState(() => _saving = true);
    try {
      await DocumentRequestsState.instance.submit(
        title: title,
        category: _category,
        target: _target,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        targetDoctorId: _doctor?.userId,
        targetDoctorName: _doctor?.name,
        neededBy: _neededBy,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.warn(context, 'Could not send: $e');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.success(
      context,
      _doctor == null
          ? 'Request sent to your care team.'
          : 'Request sent. ${_doctor!.name} and your care team can see it.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final team = _team;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'What do you need?',
          hint: 'e.g. Referral letter for physiotherapy',
          controller: _title,
        ),
        const SizedBox(height: AppSpacing.lg),

        _Label('Type of document'),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final c in DocumentCategory.values)
              ChoiceChip(
                avatar: Icon(
                  c.icon,
                  size: 15,
                  color: _category == c ? c.color : AppColors.textMutedAA,
                ),
                label: Text(c.label),
                selected: _category == c,
                selectedColor: c.color.withValues(alpha: 0.15),
                onSelected: (_) => setState(() => _category = c),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        _Label('Who are you asking?'),
        const SizedBox(height: AppSpacing.xs),
        _TargetTile(
          target: DocumentRequestTarget.team,
          selected: _target == DocumentRequestTarget.team,
          title: 'My care team',
          subtitle: 'Whoever is free picks it up first',
          onTap: () => setState(() {
            _target = DocumentRequestTarget.team;
            _doctor = null;
          }),
        ),
        const SizedBox(height: AppSpacing.xs),
        _TargetTile(
          target: DocumentRequestTarget.doctor,
          selected: _target == DocumentRequestTarget.doctor,
          title: 'A specific doctor',
          subtitle: team.isEmpty
              ? 'No doctors assigned to you yet'
              : 'Your team still sees it, so it never gets stuck',
          enabled: team.isNotEmpty,
          onTap: team.isEmpty
              ? null
              : () => setState(() => _target = DocumentRequestTarget.doctor),
        ),

        if (_target == DocumentRequestTarget.doctor && team.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final p in team)
                ChoiceChip(
                  label: Text(p.name),
                  selected: _doctor?.id == p.id,
                  onSelected: (_) => setState(() => _doctor = p),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),

        InkWell(
          onTap: _pickNeededBy,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppPalette.border(context)),
            ),
            child: Row(
              children: [
                const Icon(AppIcons.calendar, color: AppColors.brandIndigo),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Needed by (optional)',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _neededBy == null
                            ? 'Add a date if it is time-sensitive'
                            : DateFormat.yMMMd().format(_neededBy!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppPalette.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_neededBy != null)
                  IconButton(
                    icon: const Icon(AppIcons.close, size: 18),
                    tooltip: 'Clear date',
                    onPressed: () => setState(() => _neededBy = null),
                  )
                else
                  const Icon(AppIcons.chevronRight, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        AppTextField(
          label: 'Anything they should know (optional)',
          hint: 'e.g. The clinic needs it before my first session',
          controller: _note,
          maxLines: 3,
        ),
        const SizedBox(height: AppSpacing.md),

        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.brandIndigo.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(AppIcons.info, size: 16, color: AppColors.brandIndigo),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'You will see who picks this up and when. If it cannot be '
                  'provided, they have to tell you why.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        AppButton(
          label: 'Send request',
          icon: AppIcons.send,
          expand: true,
          loading: _saving,
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
  );
}

class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.target,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final DocumentRequestTarget target;
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = selected ? AppColors.brandIndigo : AppPalette.border(context);

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: accent, width: selected ? 1.5 : 1),
            color: selected
                ? AppColors.brandIndigo.withValues(alpha: 0.06)
                : null,
          ),
          child: Row(
            children: [
              Icon(
                target.icon,
                size: 20,
                color: selected
                    ? AppColors.brandIndigo
                    : AppPalette.textMuted(context),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: selected
                    ? AppColors.brandIndigo
                    : AppPalette.textMuted(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
