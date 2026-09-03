import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/document.dart';
import '../../shared/state/document_requests_state.dart';
import '../../shared/state/documents_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/section_label.dart';
import 'document_request_card.dart';
import 'document_viewer_sheet.dart';
import 'request_document_sheet.dart';
import 'upload_document_sheet.dart';

/// How the list is ordered. Newest-first is right for a record that mostly
/// grows at the top, but a patient hunting for last year's discharge summary
/// is looking for a *name*, and scrolling three years of labs to find it is
/// the failure this exists to fix.
enum _DocumentSort { newest, oldest, title, category }

extension _DocumentSortX on _DocumentSort {
  String get label => switch (this) {
    _DocumentSort.newest => 'Newest',
    _DocumentSort.oldest => 'Oldest',
    _DocumentSort.title => 'A–Z',
    _DocumentSort.category => 'By type',
  };
}

/// The patient's record, and the things they are still waiting on.
///
/// Two collections, deliberately not merged. What is filed can be opened; what
/// has been requested cannot, and a row that looked the same for both would be
/// a promise the record cannot keep. They sit on one screen because the
/// question the patient arrives with — "do I have my referral letter?" — is
/// answered by both halves together.
class DocumentsView extends StatefulWidget {
  const DocumentsView({super.key});

  @override
  State<DocumentsView> createState() => _DocumentsViewState();
}

class _DocumentsViewState extends State<DocumentsView> {
  DocumentCategory? _filter;
  _DocumentSort _sort = _DocumentSort.newest;
  final _searchController = TextEditingController();
  String _query = '';

  /// Answered requests are history, not work. Folded away by default so the
  /// section says what is outstanding and nothing else.
  bool _showClosedRequests = false;

  @override
  void initState() {
    super.initState();
    // A patient usually arrives here from a "new document from your care team"
    // alert, so the document they were told about may not be in the cached
    // session yet. Pull the list rather than make them wait for the next sync.
    // Failure is silent on purpose: whatever the session already loaded stays
    // on screen, which is more useful than an error over a full list.
    DocumentsState.instance.refresh().catchError((_) {});
    // Same reasoning for requests: a claim or a decline that landed while the
    // app was closed is exactly what they came here to check.
    DocumentRequestsState.instance.refresh().catchError((_) {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _countFor(DocumentCategory c, List<MedicalDocument> all) =>
      all.where((d) => d.category == c).length;

  /// Filter, search, then sort — in that order, so the count under the section
  /// label always describes what is actually on screen.
  List<MedicalDocument> _visible(List<MedicalDocument> all) {
    final q = _query.trim().toLowerCase();
    final items = all.where((d) {
      if (_filter != null && d.category != _filter) return false;
      if (q.isEmpty) return true;
      return d.title.toLowerCase().contains(q) ||
          d.category.label.toLowerCase().contains(q) ||
          (d.description?.toLowerCase().contains(q) ?? false) ||
          d.uploadedBy.toLowerCase().contains(q);
    }).toList();

    items.sort(switch (_sort) {
      _DocumentSort.newest => (a, b) => b.uploadedAt.compareTo(a.uploadedAt),
      _DocumentSort.oldest => (a, b) => a.uploadedAt.compareTo(b.uploadedAt),
      _DocumentSort.title => (a, b) => a.title.toLowerCase().compareTo(
        b.title.toLowerCase(),
      ),
      _DocumentSort.category => (a, b) {
        final byCategory = a.category.label.compareTo(b.category.label);
        return byCategory != 0
            ? byCategory
            : b.uploadedAt.compareTo(a.uploadedAt);
      },
    });

    return items;
  }

  @override
  Widget build(BuildContext context) {
    return PatientScaffold(
      currentRoute: RouteNames.patientDocuments,
      title: 'Documents',
      subtitle: 'Lab results, prescriptions, imaging and reports',
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
        // Both stores drive this screen, and a request being answered changes
        // both at once — the document appears and the request closes.
        animation: Listenable.merge([
          DocumentsState.instance,
          DocumentRequestsState.instance,
        ]),
        builder: (context, _) {
          final all = DocumentsState.instance.all;
          final items = _visible(all);
          final tier = ResponsiveBuilder.of(context);

          final openRequests = DocumentRequestsState.instance.open;
          final closedRequests = DocumentRequestsState.instance.closed;
          final overdueCount = DocumentRequestsState.instance.overdue.length;

          final labCount = _countFor(DocumentCategory.labResult, all);
          final rxCount = _countFor(DocumentCategory.prescription, all);
          final imagingCount = _countFor(DocumentCategory.imaging, all);
          final reportCount = _countFor(DocumentCategory.vitalReport, all);
          final mostRecent = all.isEmpty
              ? null
              : all
                    .map((d) => d.uploadedAt)
                    .reduce((a, b) => a.isAfter(b) ? a : b);

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
                  reportCount: reportCount,
                  mostRecent: mostRecent,
                  openRequestCount: openRequests.length,
                  overdueRequestCount: overdueCount,
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
                        onTap: () => UploadDocumentSheet.show(context),
                      ),
                      // The other direction, and the reason this screen is
                      // no longer a one-way street.
                      PatientQuickAction(
                        icon: AppIcons.send,
                        label: 'Request',
                        badge: openRequests.isEmpty
                            ? null
                            : '${openRequests.length}',
                        badgeColor: AppColors.warning,
                        onTap: () => RequestDocumentSheet.show(context),
                      ),
                      _CategoryQuickAction(
                        category: DocumentCategory.labResult,
                        label: 'Labs',
                        count: labCount,
                        selected: _filter == DocumentCategory.labResult,
                        onTap: () => _toggleFilter(DocumentCategory.labResult),
                      ),
                      _CategoryQuickAction(
                        category: DocumentCategory.prescription,
                        label: 'Rx',
                        count: rxCount,
                        selected: _filter == DocumentCategory.prescription,
                        onTap: () =>
                            _toggleFilter(DocumentCategory.prescription),
                      ),
                      _CategoryQuickAction(
                        category: DocumentCategory.vitalReport,
                        label: 'Reports',
                        count: reportCount,
                        selected: _filter == DocumentCategory.vitalReport,
                        onTap: () =>
                            _toggleFilter(DocumentCategory.vitalReport),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ---------------------------------------------------------
              // Waiting on the care team
              // ---------------------------------------------------------
              if (openRequests.isNotEmpty) ...[
                StaggeredEntry(
                  index: 3,
                  child: SectionLabel(
                    title: 'Waiting on your care team',
                    icon: AppIcons.time,
                    trailing: '${openRequests.length}',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final r in openRequests)
                  StaggeredEntry(
                    index: 3,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: DocumentRequestCard(request: r),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
              ],

              // ---------------------------------------------------------
              // Search + sort
              // ---------------------------------------------------------
              if (all.isNotEmpty) ...[
                StaggeredEntry(
                  index: 4,
                  child: AppTextField(
                    hint: 'Search by name, type or who filed it',
                    controller: _searchController,
                    prefixIcon: AppIcons.search,
                    suffixIcon: _query.isEmpty ? null : AppIcons.close,
                    onSuffixTap: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                StaggeredEntry(
                  index: 4,
                  child: _FilterRow(
                    all: all,
                    filter: _filter,
                    sort: _sort,
                    onFilter: (c) => setState(() => _filter = c),
                    onSort: (s) => setState(() => _sort = s),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // ---------------------------------------------------------
              // The record
              // ---------------------------------------------------------
              StaggeredEntry(
                index: 5,
                child: SectionLabel(
                  title: _sectionTitle(),
                  icon: AppIcons.document,
                  trailing: items.isEmpty ? null : '${items.length}',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              if (items.isEmpty)
                StaggeredEntry(index: 6, child: _emptyState(all.isEmpty))
              else if (tier.isDesktop)
                StaggeredEntry(
                  index: 6,
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: AppSpacing.md,
                          crossAxisSpacing: AppSpacing.md,
                          childAspectRatio: 1.1,
                        ),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _DocumentTile(doc: items[i]),
                  ),
                )
              else
                ...items.asMap().entries.map(
                  (e) => StaggeredEntry(
                    index: e.key + 6,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _DocumentTile(doc: e.value, compact: true),
                    ),
                  ),
                ),

              // ---------------------------------------------------------
              // Answered requests
              // ---------------------------------------------------------
              if (closedRequests.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                SectionLabel(
                  title: 'Past requests',
                  icon: AppIcons.history,
                  trailing: '${closedRequests.length}',
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_showClosedRequests)
                  for (final r in closedRequests)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: DocumentRequestCard(request: r),
                    )
                else
                  _ShowClosedButton(
                    count: closedRequests.length,
                    onTap: () => setState(() => _showClosedRequests = true),
                  ),
              ],

              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }

  void _toggleFilter(DocumentCategory c) =>
      setState(() => _filter = _filter == c ? null : c);

  String _sectionTitle() {
    if (_query.isNotEmpty) return 'Search results';
    return _filter?.label ?? 'All documents';
  }

  Widget _emptyState(bool recordIsEmpty) {
    // Three different nothings, and telling them apart is the difference
    // between a dead end and a next step: an empty record, a filter with no
    // matches, and a search that found none.
    if (recordIsEmpty) {
      return EmptyStateView(
        icon: AppIcons.document,
        title: 'Nothing filed yet',
        message:
            'Upload a document you already have, or ask your care team for '
            'one you need.',
        actionLabel: 'Upload',
        onAction: () => UploadDocumentSheet.show(context),
        secondaryActionLabel: 'Request',
        onSecondaryAction: () => RequestDocumentSheet.show(context),
      );
    }

    if (_query.isNotEmpty) {
      return EmptyStateView(
        icon: AppIcons.search,
        title: 'No matches',
        message: 'Nothing in your records matches "$_query".',
        actionLabel: 'Clear search',
        onAction: () {
          _searchController.clear();
          setState(() => _query = '');
        },
      );
    }

    return EmptyStateView(
      icon: _filter?.icon ?? AppIcons.document,
      title: 'No ${_filter?.label.toLowerCase() ?? 'documents'}',
      message:
          'Ask your care team for one, or clear the filter to see '
          'everything you have.',
      actionLabel: 'Request one',
      onAction: () =>
          RequestDocumentSheet.show(context, initialCategory: _filter),
      secondaryActionLabel: 'Show all',
      onSecondaryAction: () => setState(() => _filter = null),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

class _DocumentsHero extends StatelessWidget {
  const _DocumentsHero({
    required this.totalCount,
    required this.labCount,
    required this.rxCount,
    required this.imagingCount,
    required this.reportCount,
    required this.mostRecent,
    required this.openRequestCount,
    required this.overdueRequestCount,
  });

  final int totalCount;
  final int labCount;
  final int rxCount;
  final int imagingCount;
  final int reportCount;
  final DateTime? mostRecent;
  final int openRequestCount;
  final int overdueRequestCount;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: AppPalette.infoSoft(context),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Icon(
                  AppIcons.document,
                  color: AppColors.info,
                  size: 20,
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
                        height: 1.25,
                      ),
                    ),
                    if (mostRecent != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Last added · ${DateFormat.yMMMd().format(mostRecent!)}',
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

          // The waiting line goes above the counts on purpose: a patient with
          // an outstanding request came here to check on it, not to count
          // what they already have.
          if (openRequestCount > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            _WaitingBanner(
              openCount: openRequestCount,
              overdueCount: overdueRequestCount,
            ),
          ],

          if (totalCount > 0) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                PatientHeroStat(
                  label: 'Labs',
                  value: '$labCount',
                  accent: DocumentCategory.labResult.color,
                ),
                PatientHeroStatDivider(),
                PatientHeroStat(
                  label: 'Rx',
                  value: '$rxCount',
                  accent: DocumentCategory.prescription.color,
                ),
                PatientHeroStatDivider(),
                PatientHeroStat(
                  label: 'Imaging',
                  value: '$imagingCount',
                  accent: DocumentCategory.imaging.color,
                ),
                PatientHeroStatDivider(),
                PatientHeroStat(
                  label: 'Reports',
                  value: '$reportCount',
                  accent: DocumentCategory.vitalReport.color,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WaitingBanner extends StatelessWidget {
  const _WaitingBanner({required this.openCount, required this.overdueCount});

  final int openCount;
  final int overdueCount;

  @override
  Widget build(BuildContext context) {
    final overdue = overdueCount > 0;
    final color = overdue ? AppColors.critical : AppColors.warning;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          Icon(
            overdue ? AppIcons.alert : AppIcons.time,
            size: 16,
            color: color,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              overdue
                  ? '$overdueCount of $openCount request'
                        '${openCount == 1 ? '' : 's'} is past the date you needed it'
                  : '$openCount request${openCount == 1 ? '' : 's'} with your '
                        'care team',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filters
// ---------------------------------------------------------------------------

class _CategoryQuickAction extends StatelessWidget {
  const _CategoryQuickAction({
    required this.category,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final DocumentCategory category;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PatientQuickAction(
      icon: category.icon,
      label: label,
      badge: count > 0 ? '$count' : null,
      badgeColor: category.color,
      selected: selected,
      onTap: onTap,
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.all,
    required this.filter,
    required this.sort,
    required this.onFilter,
    required this.onSort,
  });

  final List<MedicalDocument> all;
  final DocumentCategory? filter;
  final _DocumentSort sort;
  final ValueChanged<DocumentCategory?> onFilter;
  final ValueChanged<_DocumentSort> onSort;

  @override
  Widget build(BuildContext context) {
    // Only categories the patient actually has, plus whatever is selected. A
    // row of nine chips where six can only ever show "no documents" is a
    // filter bar that filters nothing.
    final present = DocumentCategory.values
        .where((c) => all.any((d) => d.category == c) || c == filter)
        .toList();

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: filter == null,
                  onTap: () => onFilter(null),
                ),
                for (final c in present)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: _FilterChip(
                      label: c.label,
                      selected: filter == c,
                      color: c.color,
                      onTap: () => onFilter(filter == c ? null : c),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        PopupMenuButton<_DocumentSort>(
          tooltip: 'Sort',
          initialValue: sort,
          onSelected: onSort,
          itemBuilder: (_) => [
            for (final s in _DocumentSort.values)
              PopupMenuItem(value: s, child: Text(s.label)),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              border: Border.all(color: AppPalette.border(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(AppIcons.filter, size: 15),
                const SizedBox(width: 4),
                Text(
                  sort.label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
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

class _ShowClosedButton extends StatelessWidget {
  const _ShowClosedButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
            AppIcons.expandMore,
            size: 18,
            color: AppPalette.textMuted(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Show $count answered request${count == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppPalette.textMuted(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Document tile
// ---------------------------------------------------------------------------

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
    final theme = Theme.of(context);
    final badge = doc.source.badge;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          doc.title,
          style: theme.textTheme.titleMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '${doc.category.label} · ${doc.sizeLabel}',
          style: theme.textTheme.bodySmall,
        ),
        Text(
          DateFormat.yMMMd().format(doc.uploadedAt),
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
          ),
        ),
        // Where a document came from decides what the patient can do with it —
        // their own upload they can delete, anything else they cannot — so it
        // is worth saying on the row rather than only inside the viewer.
        if (badge != null || doc.removalRequested) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: 2,
            children: [
              if (badge != null)
                _SourceBadge(
                  label: badge,
                  color: doc.source == DocumentSource.report
                      ? AppColors.brandIndigo
                      : AppColors.doctorGreen,
                ),
              if (doc.removalRequested)
                _SourceBadge(
                  label: 'Removal requested',
                  color: AppColors.warning,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 10.5,
        ),
      ),
    );
  }
}
