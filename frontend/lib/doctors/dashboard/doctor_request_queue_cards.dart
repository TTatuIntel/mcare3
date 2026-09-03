import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/models/document.dart';
import '../../shared/models/request_activity_event.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/loading/loading.dart';
import '../../shared/widgets/request_activity_trail.dart';

/// The care team's shared queues, as the doctor works them.
///
/// One rule runs through every row here: the whole caseload can see the
/// request, and exactly one clinician can hold it. Before that existed, two
/// doctors could open the same vital report request and both write the report,
/// and — worse — a request nobody had started looked identical to one being
/// written up right now, so the untouched ones were the ones that waited.
///
/// So each row says which of those two states it is in before it offers any
/// action, and the actions differ accordingly: unclaimed work can be taken on,
/// your own work can be finished or handed back, and a colleague's work offers
/// nothing but the trail.

// ---------------------------------------------------------------------------
// Vital report requests
// ---------------------------------------------------------------------------

class VitalReportRequestsCard extends StatelessWidget {
  const VitalReportRequestsCard({super.key, required this.requests});

  final List<StaffPatientRequest> requests;

  @override
  Widget build(BuildContext context) {
    return _QueueCard(
      children: [
        for (final req in requests)
          _QueueRow(
            icon: AppIcons.report,
            iconColor: AppColors.info,
            title:
                StaffState.instance.patientById(req.patientId)?.name ??
                req.patientName ??
                'Patient',
            subtitle: req.summary,
            claimedByName: req.claimedByName,
            claimedByMe: req.claimedByMe,
            raisedAt: req.createdAt,
            events: req.events,
            trailTitle: 'Vital report request',
            actions: _VitalReportActions(request: req),
          ),
      ],
    );
  }
}

class _VitalReportActions extends StatefulWidget {
  const _VitalReportActions({required this.request});

  final StaffPatientRequest request;

  @override
  State<_VitalReportActions> createState() => _VitalReportActionsState();
}

class _VitalReportActionsState extends State<_VitalReportActions> {
  bool _busy = false;

  Future<void> _run(Future<RequestActionResult> Function() action, String done) async {
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      AppToast.success(context, done);
    } else {
      // The server's message names the colleague who got there first, which is
      // the only thing that tells the clinician what to do next.
      AppToast.warn(context, result.error ?? 'Could not complete that.');
    }
  }

  Future<void> _complete() async {
    final note = await _NoteSheet.show(
      context,
      title: 'Complete report',
      subtitle: 'The report is generated and filed in the patient\'s documents.',
      hint: 'Clinical note for the patient (optional)',
      confirmLabel: 'Issue report',
    );
    if (note == null || !mounted) return;
    await _run(
      () => StaffState.instance.fulfillRequest(
        widget.request.id,
        note: note.isEmpty ? null : note,
      ),
      'Report issued and filed under Vital report.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const McarePulse(size: McarePulseSize.micro, semanticLabel: null);
    }

    final r = widget.request;

    if (r.heldByColleague) {
      return _HeldByColleagueNote(name: r.claimedByName!);
    }

    if (r.claimedByMe) {
      return Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          AppButton(
            label: 'Complete',
            icon: AppIcons.check,
            size: AppButtonSize.sm,
            onPressed: _complete,
          ),
          AppButton(
            label: 'Hand back',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => _run(
              () => StaffState.instance.releaseRequest(r.id),
              'Returned to the care team queue.',
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        AppButton(
          label: 'Take on',
          icon: AppIcons.acknowledge,
          size: AppButtonSize.sm,
          onPressed: () => _run(
            () => StaffState.instance.claimRequest(r.id),
            'You are working on this request.',
          ),
        ),
        AppButton(
          label: 'Escalate',
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.sm,
          onPressed: () => _run(
            () => StaffState.instance.escalateRequest(r.id),
            'Escalated to care admin.',
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Document requests
// ---------------------------------------------------------------------------

class DocumentRequestsCard extends StatelessWidget {
  const DocumentRequestsCard({super.key, required this.requests});

  final List<StaffDocumentRequest> requests;

  @override
  Widget build(BuildContext context) {
    return _QueueCard(
      children: [
        for (final req in requests)
          _QueueRow(
            icon: AppIcons.document,
            iconColor: AppColors.brandIndigo,
            title:
                StaffState.instance.patientById(req.patientId)?.name ??
                req.patientName ??
                'Patient',
            subtitle: req.title,
            claimedByName: req.claimedByName,
            claimedByMe: req.claimedByMe,
            raisedAt: req.createdAt,
            events: req.events,
            trailTitle: 'Document request',
            // Two things a vital report row never has to say: who the patient
            // named, and whether they need it by a date that has passed.
            flags: [
              if (req.addressedToMe) ('Asked of you', AppColors.brandIndigo),
              if (!req.addressedToMe && req.targetDoctorName != null)
                ('For ${req.targetDoctorName}', AppColors.textMutedAA),
              if (req.overdue) ('Overdue', AppColors.critical)
              else if (req.neededBy != null)
                ('Needed by ${DateFormat.MMMd().format(req.neededBy!)}',
                    AppColors.warning),
            ],
            note: req.note,
            actions: _DocumentRequestActions(request: req),
          ),
      ],
    );
  }
}

class _DocumentRequestActions extends StatefulWidget {
  const _DocumentRequestActions({required this.request});

  final StaffDocumentRequest request;

  @override
  State<_DocumentRequestActions> createState() =>
      _DocumentRequestActionsState();
}

class _DocumentRequestActionsState extends State<_DocumentRequestActions> {
  bool _busy = false;

  Future<void> _run(Future<RequestActionResult> Function() action, String done) async {
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      AppToast.success(context, done);
    } else {
      AppToast.warn(context, result.error ?? 'Could not complete that.');
    }
  }

  Future<void> _upload() async {
    final draft = await FulfilDocumentRequestSheet.show(context, widget.request);
    if (draft == null || !mounted) return;
    await _run(
      () => StaffState.instance.fulfillDocumentRequest(
        id: widget.request.id,
        file: draft.file,
        title: draft.title,
        category: draft.category,
        fileType: draft.fileType,
        description: draft.description,
        note: draft.note,
      ),
      'Document filed and the request closed.',
    );
  }

  Future<void> _decline() async {
    final reason = await _NoteSheet.show(
      context,
      title: 'Decline request',
      subtitle:
          'The patient reads this word for word, so say what they should do '
          'next if there is somewhere else to ask.',
      hint: 'Why this cannot be provided',
      confirmLabel: 'Send decline',
      required: true,
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    await _run(
      () => StaffState.instance.declineDocumentRequest(
        widget.request.id,
        reason: reason,
      ),
      'Declined, and the patient has been told why.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const McarePulse(size: McarePulseSize.micro, semanticLabel: null);
    }

    final r = widget.request;

    if (r.heldByColleague) {
      return _HeldByColleagueNote(name: r.claimedByName!);
    }

    if (r.claimedByMe) {
      return Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          AppButton(
            label: 'Upload',
            icon: AppIcons.upload,
            size: AppButtonSize.sm,
            onPressed: _upload,
          ),
          AppButton(
            label: 'Decline',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: _decline,
          ),
          AppButton(
            label: 'Hand back',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => _run(
              () => StaffState.instance.releaseDocumentRequest(r.id),
              'Returned to the care team queue.',
            ),
          ),
        ],
      );
    }

    return AppButton(
      label: 'Take on',
      icon: AppIcons.acknowledge,
      size: AppButtonSize.sm,
      onPressed: () => _run(
        () => StaffState.instance.claimDocumentRequest(r.id),
        'You are working on this request.',
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared row scaffolding
// ---------------------------------------------------------------------------

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.raisedAt,
    required this.events,
    required this.trailTitle,
    required this.actions,
    this.claimedByName,
    this.claimedByMe = false,
    this.flags = const [],
    this.note,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final DateTime raisedAt;
  final List<RequestActivityEvent> events;
  final String trailTitle;
  final Widget actions;
  final String? claimedByName;
  final bool claimedByMe;
  final List<(String, Color)> flags;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _ClaimBadge(name: claimedByName, mine: claimedByMe),
            ],
          ),
          if (note != null && note!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              note!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted(context),
                height: 1.35,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Flag(
                label: 'Raised ${_ago(raisedAt)}',
                color: AppColors.textMutedAA,
              ),
              for (final f in flags) _Flag(label: f.$1, color: f.$2),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: actions),
              TextButton.icon(
                onPressed: () => GlassSheet.show<void>(
                  context,
                  title: trailTitle,
                  subtitle: 'Everything that has happened on this request',
                  child: RequestActivityTrail(events: events),
                ),
                icon: const Icon(AppIcons.history, size: 15),
                label: const Text('Trail'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Deliberately coarse. "Raised 3 days ago" is the fact that decides whether
  /// to pick a request up; the exact minute is in the trail.
  static String _ago(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

/// Who holds the request — the first thing a shared queue has to answer.
class _ClaimBadge extends StatelessWidget {
  const _ClaimBadge({required this.name, required this.mine});

  final String? name;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final (label, color) = name == null
        ? ('Unclaimed', AppColors.warning)
        : mine
        ? ('You', AppColors.success)
        : (name!, AppColors.info);

    return Container(
      constraints: const BoxConstraints(maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  const _Flag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
        fontSize: 11,
      ),
    );
  }
}

/// Shown instead of buttons when a colleague holds the request.
///
/// Not a disabled button: an action that is greyed out invites a tap and then
/// explains itself, where a sentence says the same thing once and leaves the
/// row honest about whose work it is.
class _HeldByColleagueNote extends StatelessWidget {
  const _HeldByColleagueNote({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$name is working on this.',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppPalette.textMuted(context),
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sheets
// ---------------------------------------------------------------------------

/// A one-field sheet for the note or reason an action carries.
class _NoteSheet extends StatefulWidget {
  const _NoteSheet({
    required this.hint,
    required this.confirmLabel,
    required this.required,
  });

  final String hint;
  final String confirmLabel;
  final bool required;

  /// Returns the text, or null if the clinician backed out. An empty string is
  /// a deliberate "no note", which is different from cancelling.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String hint,
    required String confirmLabel,
    bool required = false,
  }) {
    return GlassSheet.show<String>(
      context,
      title: title,
      subtitle: subtitle,
      child: _NoteSheet(
        hint: hint,
        confirmLabel: confirmLabel,
        required: required,
      ),
    );
  }

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: widget.hint,
          controller: _controller,
          maxLines: 4,
          autofocus: true,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: widget.confirmLabel,
          icon: AppIcons.send,
          expand: true,
          onPressed: () {
            final text = _controller.text.trim();
            if (widget.required && text.length < 4) {
              AppToast.warn(context, 'Give the patient a reason.');
              return;
            }
            Navigator.of(context).pop(text);
          },
        ),
      ],
    );
  }
}

/// What the clinician chose in [FulfilDocumentRequestSheet].
typedef DocumentFulfilmentDraft = ({
  PlatformFile file,
  String title,
  DocumentCategory category,
  DocumentFileType fileType,
  String? description,
  String? note,
});

/// Answers a document request with the file.
///
/// Pre-filled from the request — the patient already said what they wanted and
/// under which category, and making the clinician retype it invites a mismatch
/// between what was asked for and what is filed.
class FulfilDocumentRequestSheet extends StatefulWidget {
  const FulfilDocumentRequestSheet({super.key, required this.request});

  final StaffDocumentRequest request;

  static Future<DocumentFulfilmentDraft?> show(
    BuildContext context,
    StaffDocumentRequest request,
  ) {
    return GlassSheet.show<DocumentFulfilmentDraft>(
      context,
      title: 'Answer request',
      subtitle: request.title,
      child: FulfilDocumentRequestSheet(request: request),
    );
  }

  @override
  State<FulfilDocumentRequestSheet> createState() =>
      _FulfilDocumentRequestSheetState();
}

class _FulfilDocumentRequestSheetState
    extends State<FulfilDocumentRequestSheet> {
  late final TextEditingController _title = TextEditingController(
    text: widget.request.title,
  );
  final _note = TextEditingController();
  late DocumentCategory _category = DocumentCategory.values.firstWhere(
    (c) => c.name == widget.request.category,
    orElse: () => DocumentCategory.other,
  );

  PlatformFile? _file;
  DocumentFileType _fileType = DocumentFileType.pdf;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    setState(() {
      _file = file;
      _fileType = switch ((file.extension ?? '').toLowerCase()) {
        'pdf' => DocumentFileType.pdf,
        'jpg' || 'jpeg' || 'png' => DocumentFileType.image,
        'doc' || 'docx' => DocumentFileType.doc,
        _ => DocumentFileType.other,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.request.note != null &&
            widget.request.note!.trim().isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppPalette.infoSoft(context).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              'They said: ${widget.request.note}',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        InkWell(
          onTap: _pickFile,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: _file == null
                    ? AppPalette.border(context)
                    : AppColors.success.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _file == null ? AppIcons.upload : AppIcons.check,
                  color: _file == null
                      ? AppColors.brandIndigo
                      : AppColors.success,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    _file?.name ?? 'Choose a file (PDF, image or DOC)',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(label: 'Document title', controller: _title),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Category',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final c in DocumentCategory.values)
              ChoiceChip(
                label: Text(c.label),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = c),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Note to the patient (optional)',
          controller: _note,
          maxLines: 2,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'File and close request',
          icon: AppIcons.check,
          expand: true,
          onPressed: () {
            if (_file == null) {
              AppToast.warn(context, 'Choose a file first.');
              return;
            }
            if (_title.text.trim().isEmpty) {
              AppToast.warn(context, 'Give the document a title.');
              return;
            }
            Navigator.of(context).pop((
              file: _file!,
              title: _title.text.trim(),
              category: _category,
              fileType: _fileType,
              description: null,
              note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            ));
          },
        ),
      ],
    );
  }
}
