part of 'doctor_patient_workspace_view.dart';

void _showDocumentSheet(BuildContext context, StaffPatientDocument doc) {
  GlassSheet.show(
    context,
    title: doc.title,
    subtitle: '${doc.category} · ${DateFormat.yMMMd().format(doc.uploadedAt)}',
    maxHeightFactor: 0.92,
    child: _DoctorDocumentViewer(doc: doc),
  );
}

class _DoctorDocumentViewer extends StatefulWidget {
  const _DoctorDocumentViewer({required this.doc});
  final StaffPatientDocument doc;

  @override
  State<_DoctorDocumentViewer> createState() => _DoctorDocumentViewerState();
}

class _DoctorDocumentViewerState extends State<_DoctorDocumentViewer> {
  late StaffPatientDocument _doc;
  int _previewReload = 0;

  MedicalDocument get _asMedical => MedicalDocument(
    id: _doc.id,
    title: _doc.title,
    category: PatientDomainMapper.documentCategoryFromApi(_doc.category),
    fileType: _doc.fileType,
    sizeBytes: 0,
    uploadedAt: _doc.uploadedAt,
    uploadedBy: _doc.uploadedBy,
    description: _doc.description,
    hasFile: _doc.hasFile,
  );

  @override
  void initState() {
    super.initState();
    _doc = widget.doc;
  }

  Future<void> _edit() async {
    final updated = await EditDocumentSheet.show(
      context,
      doc: _asMedical,
      patientUserId: _doc.patientId,
    );
    if (updated != true || !mounted) return;
    await DoctorPatientDetailService.instance.loadPatient(_doc.patientId);
    if (!mounted) return;
    final refreshed = StaffState.instance
        .documentsForPatient(_doc.patientId)
        .where((d) => d.id == _doc.id);
    if (refreshed.isNotEmpty) {
      setState(() {
        _doc = refreshed.first;
        _previewReload++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MedicalDocumentViewerBody(
      documentId: _doc.id,
      fileType: _doc.fileType,
<<<<<<< Updated upstream
=======
      documentTitle: _doc.title,
      // The care team opens the same bytes the patient does, so it reads the
      // same server-recorded type and filename rather than guessing.
      mimeType: _doc.mimeType,
      downloadName: _doc.downloadName,
>>>>>>> Stashed changes
      patientUserId: _doc.patientId,
      hasFile: _doc.hasFile,
      previewReloadToken: _previewReload,
      metaRows: [
        DocumentMetaRow(label: 'Category', value: _doc.category),
        DocumentMetaRow(
          label: 'Uploaded',
          value: DateFormat.yMMMd().add_jm().format(_doc.uploadedAt),
        ),
        DocumentMetaRow(label: 'Uploaded by', value: _doc.uploadedBy),
      ],
      onEdit: _edit,
      onDelete: () async {
        if (AppEnv.backendEnabled) {
          await DocumentsApi.instance.doctorDelete(
            patientUserId: _doc.patientId,
            documentId: _doc.id,
          );
          await DoctorPatientDetailService.instance.loadPatient(_doc.patientId);
        } else {
          StaffState.instance.removeDocumentForPatient(_doc.id);
        }
      },
    );
  }
}

class _MessagesPanel extends StatelessWidget {
  const _MessagesPanel({required this.patientId, required this.patientName});

  final String patientId;
  final String patientName;

  @override
  Widget build(BuildContext context) {
    final conv = MessagesState.instance.conversationForPatient(
      patientId: patientId,
      patientName: patientName,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title: 'Messages', icon: AppIcons.chat),
        GlassCard(
          frosted: true,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (conv != null) ...[
                Text(
                  conv.lastMessage.body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  DateFormat.MMMd().add_jm().format(conv.lastMessage.sentAt),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppPalette.textFaint(context),
                    fontSize: 10,
                  ),
                ),
              ] else
                Text(
                  'Secure messaging with $patientName.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: conv != null ? 'Open conversation' : 'Open messages',
                icon: AppIcons.chat,
                onPressed: () =>
                    _openPatientChat(context, patientId, patientName),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReportsPanel extends StatelessWidget {
  const _ReportsPanel({required this.patientId, required this.patientName});

  final String patientId;
  final String patientName;

  @override
  Widget build(BuildContext context) {
    final reports = StaffState.instance.reportsForPatient(patientId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: 'Clinical reports',
          icon: AppIcons.report,
          trailing: '${reports.length}',
          actionLabel: 'New report',
          onAction: () => Navigator.of(
            context,
          ).pushNamed(RouteNames.doctorReportEditor, arguments: patientName),
        ),
        if (reports.isEmpty)
          GlassCard(
            frosted: true,
            child: EmptyStateView(
              icon: AppIcons.report,
              title: 'No reports yet',
              actionLabel: 'Write report',
              onAction: () => Navigator.of(context).pushNamed(
                RouteNames.doctorReportEditor,
                arguments: patientName,
              ),
              compact: true,
            ),
          )
        else
          StaffListCard(
            children: reports
                .map(
                  (r) => StaffListRow(
                    icon: AppIcons.report,
                    iconColor: AppColors.doctorGreen,
                    title: r.title,
                    subtitle: DateFormat.MMMd().format(r.createdAt),
                    pill: r.published ? 'Published' : 'Draft',
                    pillColor: r.published
                        ? AppColors.success
                        : AppColors.warning,
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed(RouteNames.doctorReportEditor, arguments: r.id),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel({required this.patientId});
  final String patientId;

  @override
  Widget build(BuildContext context) {
    final s = StaffState.instance;
    final items = <_TimelineItem>[
      ...s
          .vitalsForPatient(patientId)
          .map(
            (v) => _TimelineItem(
              at: v.recordedAt,
              icon: v.vital.icon,
              title: '${v.vital.label} recorded',
              subtitle: v.value,
            ),
          ),
      ...s
          .alertsForPatient(patientId)
          .map(
            (a) => _TimelineItem(
              at: a.createdAt,
              icon: AppIcons.alert,
              title: 'Alert · ${a.vital.label}',
              subtitle: a.value,
            ),
          ),
      ...s
          .documentsForPatient(patientId)
          .map(
            (d) => _TimelineItem(
              at: d.uploadedAt,
              icon: AppIcons.document,
              title: 'Document uploaded',
              subtitle: d.title,
            ),
          ),
    ]..sort((a, b) => b.at.compareTo(a.at));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title: 'Activity timeline', icon: AppIcons.audit),
        if (items.isEmpty)
          GlassCard(
            frosted: true,
            child: Text(
              'No activity yet.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          StaffListCard(
            children: items
                .take(12)
                .map(
                  (e) => StaffListRow(
                    icon: e.icon,
                    title: e.title,
                    subtitle:
                        '${e.subtitle} · ${DateFormat.MMMd().add_jm().format(e.at)}',
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _TimelineItem {
  _TimelineItem({
    required this.at,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final DateTime at;
  final IconData icon;
  final String title;
  final String subtitle;
}

class _MealsPanel extends StatelessWidget {
  const _MealsPanel({required this.patientId, required this.patientName});

  final String patientId;
  final String patientName;

  @override
  Widget build(BuildContext context) {
    final plans = StaffState.instance.mealPlansForPatient(patientId);
    final grouped = <MealType, List<StaffMealPlan>>{};
    for (final p in plans) {
      grouped.putIfAbsent(p.mealType, () => []).add(p);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: 'Meal plans',
          icon: AppIcons.meals,
          trailing: '${plans.length}',
          actionLabel: 'Assign',
          onAction: () => showDoctorAssignMealSheet(
            context,
            patientId: patientId,
            patientName: patientName,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        GlassCard(
          frosted: true,
          onTap: () => showDoctorAssignMealSheet(
            context,
            patientId: patientId,
            patientName: patientName,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(AppIcons.add, size: 18, color: AppColors.doctorGreen),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Assign meal plan for $patientName',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                AppIcons.chevronRight,
                size: 14,
                color: AppPalette.textMuted(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (plans.isEmpty)
          GlassCard(
            frosted: true,
            child: EmptyStateView(
              icon: AppIcons.meals,
              title: 'No meal plans assigned',
              message: 'Assign a diet or nutrition plan for $patientName.',
              compact: true,
              actionLabel: 'Assign meal plan',
              onAction: () => showDoctorAssignMealSheet(
                context,
                patientId: patientId,
                patientName: patientName,
              ),
            ),
          )
        else
          for (final entry in grouped.entries) ...[
            SectionLabel(
              title: entry.key.label,
              icon: entry.key.icon,
              trailing: '${entry.value.length}',
            ),
            const SizedBox(height: AppSpacing.xs),
            StaffListCard(
              children: entry.value
                  .map(
                    (plan) => StaffListRow(
                      icon: plan.mealType.icon,
                      iconColor: plan.mealType.color,
                      title: plan.title,
                      subtitle: plan.macroSummary.isNotEmpty
                          ? plan.macroSummary
                          : (plan.description ?? ''),
                      trailing: IconButton(
                        icon: const Icon(AppIcons.delete, size: 18),
                        color: AppPalette.textMuted(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        onPressed: () {
                          StaffState.instance.removeMealPlan(plan.id);
                          AppToast.success(context, 'Meal plan removed.');
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }
}
