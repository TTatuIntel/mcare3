import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/document.dart';
import '../../shared/state/documents_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/section_label.dart';
import 'document_viewer_sheet.dart';
import 'upload_document_sheet.dart';

class DocumentsView extends StatefulWidget {
  const DocumentsView({super.key});

  @override
  State<DocumentsView> createState() => _DocumentsViewState();
}

class _DocumentsViewState extends State<DocumentsView> {
  DocumentCategory? _filter;

  int _countFor(DocumentCategory c, List<MedicalDocument> all) =>
      all.where((d) => d.category == c).length;

  @override
  Widget build(BuildContext context) {
    return PatientScaffold(
      currentRoute: RouteNames.patientDocuments,
      title: 'Documents',
      subtitle: 'Lab results, prescriptions, imaging and more',
      headerActions: [
        AppButton(
          label: 'Upload',
          icon: AppIcons.add,
          size: AppButtonSize.sm,
          onPressed: () => UploadDocumentSheet.show(context),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
      body: AnimatedBuilder(
        animation: DocumentsState.instance,
        builder: (context, _) {
          final all = DocumentsState.instance.all;
          final items = DocumentsState.instance.filter(_filter);
          final tier = ResponsiveBuilder.of(context);
          final labCount = _countFor(DocumentCategory.labResult, all);
          final rxCount = _countFor(DocumentCategory.prescription, all);
          final imagingCount = _countFor(DocumentCategory.imaging, all);
          final mostRecent = all.isNotEmpty
              ? all
                    .map((d) => d.uploadedAt)
                    .reduce((a, b) => a.isAfter(b) ? a : b)
              : null;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(index: 0, child: PatientDateHeader()),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 1,
                child: _DocumentsHero(
                  totalCount: all.length,
                  labCount: labCount,
                  rxCount: rxCount,
                  imagingCount: imagingCount,
                  mostRecent: mostRecent,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 2,
                child: GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xs,
                  ),
                  child: PatientQuickActionsBar(
                    children: [
                      PatientQuickAction(
                        icon: AppIcons.add,
                        label: 'Upload',
                        horizontal: true,
                        onTap: () => UploadDocumentSheet.show(context),
                      ),
                      PatientQuickAction(
                        icon: DocumentCategory.labResult.icon,
                        label: 'Labs',
                        horizontal: true,
                        badge: labCount > 0 ? '$labCount' : null,
                        badgeColor: DocumentCategory.labResult.color,
                        selected: _filter == DocumentCategory.labResult,
                        onTap: () => setState(
                          () => _filter = DocumentCategory.labResult,
                        ),
                      ),
                      PatientQuickAction(
                        icon: DocumentCategory.prescription.icon,
                        label: 'Rx',
                        horizontal: true,
                        badge: rxCount > 0 ? '$rxCount' : null,
                        badgeColor: DocumentCategory.prescription.color,
                        selected: _filter == DocumentCategory.prescription,
                        onTap: () => setState(
                          () => _filter = DocumentCategory.prescription,
                        ),
                      ),
                      PatientQuickAction(
                        icon: DocumentCategory.imaging.icon,
                        label: 'Imaging',
                        horizontal: true,
                        badge: imagingCount > 0 ? '$imagingCount' : null,
                        badgeColor: DocumentCategory.imaging.color,
                        selected: _filter == DocumentCategory.imaging,
                        onTap: () =>
                            setState(() => _filter = DocumentCategory.imaging),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 3,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: _filter == null,
                        onTap: () => setState(() => _filter = null),
                      ),
                      ...DocumentCategory.values.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(left: AppSpacing.sm),
                          child: _FilterChip(
                            label: c.label,
                            selected: _filter == c,
                            color: c.color,
                            onTap: () => setState(() => _filter = c),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 4,
                child: SectionLabel(
                  title: _filter == null ? 'All documents' : _filter!.label,
                  icon: AppIcons.document,
                  trailing: items.isEmpty ? null : '${items.length}',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (items.isEmpty)
                StaggeredEntry(
                  index: 5,
                  child: EmptyStateView(
                    icon: AppIcons.document,
                    title: 'No documents',
                    message: _filter == null
                        ? 'Upload your first document to get started.'
                        : 'No documents in this category.',
                    actionLabel: 'Upload',
                    onAction: () => UploadDocumentSheet.show(context),
                  ),
                )
              else if (tier.isDesktop)
                StaggeredEntry(
                  index: 5,
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: AppSpacing.md,
                          crossAxisSpacing: AppSpacing.md,
                          // Document tiles contain a compact icon and three
                          // text lines; their height should not grow with the
                          // much wider patient desktop workspace.
                          mainAxisExtent: 180,
                        ),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _DocumentTile(doc: items[i]),
                  ),
                )
              else
                ...items.asMap().entries.map(
                  (e) => StaggeredEntry(
                    index: e.key + 5,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _DocumentTile(doc: e.value, compact: true),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }
}

class _DocumentsHero extends StatelessWidget {
  const _DocumentsHero({
    required this.totalCount,
    required this.labCount,
    required this.rxCount,
    required this.imagingCount,
    required this.mostRecent,
  });

  final int totalCount;
  final int labCount;
  final int rxCount;
  final int imagingCount;
  final DateTime? mostRecent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headline = totalCount == 0
        ? 'Keep records handy'
        : '$totalCount document${totalCount == 1 ? '' : 's'} on file';

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: AppPalette.infoSoft(context),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Icon(
                  AppIcons.document,
                  color: AppColors.info,
                  size: 23,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppPalette.ink(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        height: 1.25,
                      ),
                    ),
                    if (mostRecent != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Last upload · ${DateFormat.yMMMd().format(mostRecent!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppPalette.textMuted(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (totalCount > 0) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                PatientHeroStat(
                  label: 'Labs',
                  value: '$labCount',
                  accent: DocumentCategory.labResult.color,
                  horizontal: true,
                ),
                PatientHeroStatDivider(),
                PatientHeroStat(
                  label: 'Rx',
                  value: '$rxCount',
                  accent: DocumentCategory.prescription.color,
                  horizontal: true,
                ),
                PatientHeroStatDivider(),
                PatientHeroStat(
                  label: 'Imaging',
                  value: '$imagingCount',
                  accent: DocumentCategory.imaging.color,
                  horizontal: true,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.brandIndigo;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: c.withValues(alpha: 0.15),
      checkmarkColor: c,
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.doc, this.compact = false});
  final MedicalDocument doc;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: () => DocumentViewerSheet.show(context, doc),
      child: compact
          ? Row(
              children: [
                _IconBox(doc: doc),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: _Content(doc: doc)),
                Icon(Icons.chevron_right, color: AppPalette.textMuted(context)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconBox(doc: doc, large: true),
                const SizedBox(height: AppSpacing.md),
                _Content(doc: doc),
              ],
            ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.doc, this.large = false});
  final MedicalDocument doc;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: large ? 56 : 44,
      width: large ? 56 : 44,
      decoration: BoxDecoration(
        color: doc.category.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Icon(
        doc.category.icon,
        color: doc.category.color,
        size: large ? 28 : 22,
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.doc});
  final MedicalDocument doc;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(doc.title, style: Theme.of(context).textTheme.titleMedium),
        Text(
          '${doc.category.label} · ${doc.sizeLabel}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          DateFormat.yMMMd().format(doc.uploadedAt),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
          ),
        ),
      ],
    );
  }
}
