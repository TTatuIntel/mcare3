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
<<<<<<< Updated upstream
=======
import '../../core/realtime/realtime_refresh_mixin.dart';
import '../../shared/models/vital_report_request.dart';
import '../../shared/state/vital_report_state.dart';
import '../consents/patient_report_consents_view.dart';
import '../vitals/request_vital_report_sheet.dart';
import 'document_request_card.dart';
>>>>>>> Stashed changes
import 'document_viewer_sheet.dart';
import 'upload_document_sheet.dart';

class DocumentsView extends StatefulWidget {
  const DocumentsView({super.key});

  @override
  State<DocumentsView> createState() => _DocumentsViewState();
}

class _DocumentsViewState extends State<DocumentsView>
    with RealtimeRefreshMixin<DocumentsView> {
  DocumentCategory? _filter;
<<<<<<< Updated upstream
=======

  /// The Reports chip spans two categories, so it cannot be expressed as a
  /// single [_filter] value. Kept as its own flag rather than by widening
  /// [_filter] to a set, which every other chip would then have to reason about
  /// for no benefit.
  bool _reportsOnly = false;

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
    // And the vital reports they asked for from this screen.
    VitalReportState.instance.refresh().catchError((_) {});

    // A one-shot fetch on open is not enough. A patient sitting on this screen
    // while a doctor signs their report — which is the exact moment they are
    // told to come and look — would otherwise watch a list that never changes.
    // The same signal covers a document filed by the care team and a request
    // being claimed or answered.
    watchRealtime({'documents', 'vitals', 'notifications'}, _refreshAll);
  }

  /// Pulls every collection this screen shows.
  ///
  /// Failures are swallowed per-store on purpose: whatever is already on screen
  /// is more useful than an error page over a list the patient can still read.
  Future<void> _refreshAll() async {
    await Future.wait([
      DocumentsState.instance.refresh().catchError((_) {}),
      DocumentRequestsState.instance.refresh().catchError((_) {}),
      VitalReportState.instance.refresh().catchError((_) {}),
    ]);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
>>>>>>> Stashed changes

  int _countFor(DocumentCategory c, List<MedicalDocument> all) =>
      all.where((d) => d.category == c).length;

<<<<<<< Updated upstream
=======
  /// Filter, search, then sort — in that order, so the count under the section
  /// label always describes what is actually on screen.
  List<MedicalDocument> _visible(List<MedicalDocument> all) {
    final q = _query.trim().toLowerCase();
    final items = all.where((d) {
      if (_reportsOnly && !d.category.isIssuedReport) return false;
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

>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
        animation: DocumentsState.instance,
=======
        // Both stores drive this screen, and a request being answered changes
        // both at once — the document appears and the request closes.
        animation: Listenable.merge([
          DocumentsState.instance,
          DocumentRequestsState.instance,
          // A vital report can now be asked for from this screen, so the queue
          // it lands in has to drive this screen too.
          VitalReportState.instance,
        ]),
>>>>>>> Stashed changes
        builder: (context, _) {
          final all = DocumentsState.instance.all;
          final items = DocumentsState.instance.filter(_filter);
          final tier = ResponsiveBuilder.of(context);
          final labCount = _countFor(DocumentCategory.labResult, all);
          final rxCount = _countFor(DocumentCategory.prescription, all);
          final imagingCount = _countFor(DocumentCategory.imaging, all);
<<<<<<< Updated upstream
          final mostRecent = all.isNotEmpty
              ? all
=======
          // Both report categories. A patient counting the reports they hold
          // does not care whether a vital report or a record disclosure made
          // it — and after the second category was added, counting only the
          // first would have shown "0 Reports" to someone holding one.
          final reportCount = all.where((d) => d.category.isIssuedReport).length;
          final openVitalReports = VitalReportState.instance.pending;
          final mostRecent = all.isEmpty
              ? null
              : all
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
=======
                  openRequestCount: openRequests.length + openVitalReports.length,
                  overdueRequestCount: overdueCount,
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
                        icon: DocumentCategory.labResult.icon,
=======
                        icon: AppIcons.send,
                        label: 'Request',
                        badge: openRequests.isEmpty
                            ? null
                            : '${openRequests.length}',
                        badgeColor: AppColors.warning,
                        onTap: () => RequestDocumentSheet.show(context),
                      ),
                      // Asking for a vital report belonged here as much as on
                      // the vitals screen. This is where a patient comes when
                      // they need a document to hand someone — the report they
                      // are most often asked for was the one thing they had to
                      // go somewhere else to request.
                      PatientQuickAction(
                        icon: AppIcons.vitals,
                        label: 'Vitals report',
                        badge: openVitalReports.isEmpty
                            ? null
                            : '${openVitalReports.length}',
                        badgeColor: AppColors.warning,
                        onTap: () => RequestVitalReportSheet.show(context),
                      ),
                      _CategoryQuickAction(
                        category: DocumentCategory.labResult,
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
                      PatientQuickAction(
                        icon: DocumentCategory.imaging.icon,
                        label: 'Imaging',
                        horizontal: true,
                        badge: imagingCount > 0 ? '$imagingCount' : null,
                        badgeColor: DocumentCategory.imaging.color,
                        selected: _filter == DocumentCategory.imaging,
                        onTap: () =>
                            setState(() => _filter = DocumentCategory.imaging),
=======
                      _CategoryQuickAction(
                        category: DocumentCategory.vitalReport,
                        label: 'Reports',
                        count: reportCount,
                        selected: _reportsFilterOn,
                        onTap: _toggleReportsFilter,
>>>>>>> Stashed changes
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
<<<<<<< Updated upstream
=======

              // ---------------------------------------------------------
              // Waiting on the care team
              // ---------------------------------------------------------
              // One section for everything outstanding, whichever queue it
              // sits in. A patient waiting on a referral letter and a patient
              // waiting on a vitals report are asking the same question, and
              // splitting them into two headings made the screen answer it
              // twice.
              if (openRequests.isNotEmpty || openVitalReports.isNotEmpty) ...[
                StaggeredEntry(
                  index: 3,
                  child: SectionLabel(
                    title: 'Waiting on your care team',
                    icon: AppIcons.time,
                    trailing:
                        '${openRequests.length + openVitalReports.length}',
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
                for (final r in openVitalReports)
                  StaggeredEntry(
                    index: 3,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _VitalReportWaitingCard(request: r),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
              ],

              const PatientReportConsentsView(embedded: true),

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
                    reportsOnly: _reportsOnly,
                    sort: _sort,
                    // Clearing the Reports flag here matters: the two filters
                    // intersect, so a chip tapped while Reports was on used to
                    // leave the patient looking at an empty list they had no
                    // way to explain.
                    onFilter: (c) => setState(() {
                      _filter = c;
                      _reportsOnly = false;
                    }),
                    onSort: (s) => setState(() => _sort = s),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // ---------------------------------------------------------
              // The record
              // ---------------------------------------------------------
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
=======

  void _toggleFilter(DocumentCategory c) => setState(() {
    _filter = _filter == c ? null : c;
    _reportsOnly = false;
  });

  bool get _reportsFilterOn => _reportsOnly;

  void _toggleReportsFilter() => setState(() {
    _reportsOnly = !_reportsOnly;
    _filter = null;
  });

  String _sectionTitle() {
    if (_query.isNotEmpty) return 'Search results';
    if (_reportsOnly) return 'Reports';
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

    // A patient filtered to Reports with none yet is asking a different
    // question from one filtered to Labs: the way to get a report is to
    // request one from the care team, not to look harder.
    if (_reportsOnly) {
      return EmptyStateView(
        icon: AppIcons.vitals,
        title: 'No reports yet',
        message:
            'Reports your care team issues you land here automatically — '
            'the moment they are signed off.',
        actionLabel: 'Request a vitals report',
        onAction: () => RequestVitalReportSheet.show(context),
        secondaryActionLabel: 'Show all',
        onSecondaryAction: () => setState(() => _reportsOnly = false),
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
>>>>>>> Stashed changes
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
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 500;
              final leftSide = Row(
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: AppPalette.infoSoft(context),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: const Icon(
                      AppIcons.document,
                      color: AppColors.info,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        headline,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppPalette.ink(context),
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          height: 1.15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              );

              final rightSide = _HeroRecentDocStrip(
                mostRecent: mostRecent,
                totalCount: totalCount,
              );

              if (!isWide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    leftSide,
                    const SizedBox(height: AppSpacing.sm),
                    rightSide,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: leftSide),
                  Container(
                    height: 42,
                    width: 1,
                    color: AppPalette.border(context),
                    margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  ),
                  Expanded(child: rightSide),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: AppPalette.border(context)),
          const SizedBox(height: AppSpacing.sm),
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
      ),
    );
  }
}

class _HeroRecentDocStrip extends StatelessWidget {
  const _HeroRecentDocStrip({
    required this.mostRecent,
    required this.totalCount,
  });

  final DateTime? mostRecent;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.brandIndigo;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => UploadDocumentSheet.show(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Ink(
          width: double.infinity,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
<<<<<<< Updated upstream
          child: Padding(
=======
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
    required this.reportsOnly,
    required this.sort,
    required this.onFilter,
    required this.onSort,
  });

  final List<MedicalDocument> all;
  final DocumentCategory? filter;

  /// The Reports quick action is on, which is a filter this row does not own
  /// but must not contradict by showing "All" as selected.
  final bool reportsOnly;

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
                  selected: filter == null && !reportsOnly,
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
>>>>>>> Stashed changes
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs + 2,
            ),
            child: Row(
              children: [
                Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(AppIcons.add, size: 16, color: accent),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        mostRecent != null
                            ? 'LAST UPLOAD (${DateFormat.yMMMd().format(mostRecent!)})'
                            : 'ADD RECORDS',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.textMuted(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 9.5,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Upload new document',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppPalette.ink(context),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          height: 1.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  AppIcons.chevronRight,
                  size: 14,
                  color: accent,
                ),
              ],
            ),
          ),
        ),
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

<<<<<<< Updated upstream
=======
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
// Outstanding vital report
// ---------------------------------------------------------------------------

/// A vitals report the patient has asked for and not yet been given.
///
/// Deliberately not the same widget as [DocumentRequestCard]: that one is about
/// a file the care team holds and can attach, this one about a report that does
/// not exist yet and is being written. Rendering them identically would promise
/// the patient a document they cannot open.
class _VitalReportWaitingCard extends StatelessWidget {
  const _VitalReportWaitingCard({required this.request});

  final VitalReportRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = request.status;
    final claimedBy = request.claimedByName;

    return GlassCard(
      onTap: () => RequestVitalReportSheet.show(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: status.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(status.icon, color: status.color, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vitals report',
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${DateFormat.yMMMd().format(request.from)} – '
                  '${DateFormat.yMMMd().format(request.to)}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: 2,
                  children: [
                    _SourceBadge(label: status.label, color: status.color),
                    // Who has it matters more than that somebody does: it is
                    // the difference between "nobody has looked at this" and
                    // "it is being written right now".
                    if (claimedBy != null && claimedBy.isNotEmpty)
                      _SourceBadge(
                        label: 'With $claimedBy',
                        color: AppColors.info,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppPalette.textMuted(context)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Document tile
// ---------------------------------------------------------------------------

>>>>>>> Stashed changes
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
