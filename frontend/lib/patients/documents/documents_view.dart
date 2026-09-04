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
import '../../core/realtime/realtime_refresh_mixin.dart';
import '../../shared/models/vital_report_request.dart';
import '../../shared/state/vital_report_state.dart';
import '../consents/patient_report_consents_view.dart';
import '../vitals/request_vital_report_sheet.dart';
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
  const DocumentsView({super.key, this.openDocumentId});

  /// A document to open as soon as the list can show it.
  ///
  /// Set when the patient arrives from a "your report is ready" notification.
  /// Landing them on the list and leaving them to find the thing they were
  /// just told about is the difference between being notified and being
  /// delivered to.
  final String? openDocumentId;

  @override
  State<DocumentsView> createState() => _DocumentsViewState();
}

class _DocumentsViewState extends State<DocumentsView>
    with RealtimeRefreshMixin<DocumentsView> {
  DocumentCategory? _filter;

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

    // Usually already cached, in which case the reader never sees the list.
    _openRequestedDocument();
  }

  /// Whether the document named on arrival has already been shown. Opening it
  /// twice — on the next realtime refresh, say — would reopen a sheet the
  /// reader had deliberately closed.
  bool _handledDeepLink = false;

  /// Opens the document the caller arrived for, once it exists locally.
  ///
  /// The row may not be in the cached session yet: a report signed a moment
  /// ago is exactly the case this exists for. So it is tried after the refresh
  /// as well as before it, and gives up quietly if the document never appears
  /// rather than blocking the screen behind an error.
  void _openRequestedDocument() {
    final wanted = widget.openDocumentId;
    if (wanted == null || _handledDeepLink || !mounted) return;

    final matches = DocumentsState.instance.all.where((d) => d.id == wanted);
    if (matches.isEmpty) return;

    _handledDeepLink = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) DocumentViewerSheet.show(context, matches.first);
    });
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

    // The document the patient came for may only have arrived in this pull.
    _openRequestedDocument();
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
          // A vital report can now be asked for from this screen, so the queue
          // it lands in has to drive this screen too.
          VitalReportState.instance,
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
          // Both report categories. A patient counting the reports they hold
          // does not care whether a vital report or a record disclosure made
          // it — and after the second category was added, counting only the
          // first would have shown "0 Reports" to someone holding one.
          final reportCount = all.where((d) => d.category.isIssuedReport).length;
          final openVitalReports = VitalReportState.instance.pending;
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
                  openRequestCount: openRequests.length + openVitalReports.length,
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

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
                    onReportsOnly: _toggleReportsFilter,
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
                // Grouped by when it arrived, so a record that grows for years
                // still reads as "what came in recently" followed by history,
                // rather than one undifferentiated run of rows. Grouping is
                // suppressed under the sorts where it would be meaningless —
                // A-Z and by-type order by something other than time, and
                // date headings over those would be noise.
                ..._buildGroupedTiles(items),

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

  void _toggleReportsFilter() => setState(() {
    _reportsOnly = !_reportsOnly;
    _filter = null;
  });

  /// The list, under time headings where time is what it is ordered by.
  List<Widget> _buildGroupedTiles(List<MedicalDocument> items) {
    final grouped = _sort == _DocumentSort.newest || _sort == _DocumentSort.oldest;

    if (!grouped) {
      return [
        for (final (i, doc) in items.indexed)
          StaggeredEntry(
            index: i + 6,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _DocumentTile(doc: doc, compact: true),
            ),
          ),
      ];
    }

    final widgets = <Widget>[];
    String? lastGroup;
    var index = 6;

    for (final doc in items) {
      final group = _groupLabelFor(doc.uploadedAt);
      if (group != lastGroup) {
        lastGroup = group;
        widgets.add(
          Padding(
            padding: EdgeInsets.only(
              top: widgets.isEmpty ? 0 : AppSpacing.sm,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              group,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
        );
      }

      widgets.add(
        StaggeredEntry(
          index: index++,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _DocumentTile(doc: doc, compact: true),
          ),
        ),
      );
    }

    return widgets;
  }

  /// Coarse on purpose: a heading per day would out-number the rows under it.
  String _groupLabelFor(DateTime when) {
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(when.year, when.month, when.day)).inDays;

    if (days <= 0) return 'TODAY';
    if (days == 1) return 'YESTERDAY';
    if (days < 7) return 'THIS WEEK';
    if (days < 30) return 'THIS MONTH';
    if (now.year == when.year) return DateFormat.yMMMM().format(when).toUpperCase();
    return DateFormat.y().format(when);
  }

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

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.all,
    required this.filter,
    required this.reportsOnly,
    required this.sort,
    required this.onFilter,
    required this.onReportsOnly,
    required this.onSort,
  });

  final List<MedicalDocument> all;
  final DocumentCategory? filter;

  /// Reports span two categories, so they cannot be one [filter] value.
  final bool reportsOnly;

  final _DocumentSort sort;
  final ValueChanged<DocumentCategory?> onFilter;
  final VoidCallback onReportsOnly;
  final ValueChanged<_DocumentSort> onSort;

  @override
  Widget build(BuildContext context) {
    final reportCount = all.where((d) => d.category.isIssuedReport).length;

    // Only categories the patient actually has, plus whatever is selected. A
    // row of nine chips where six can only ever show "no documents" is a
    // filter bar that filters nothing. Reports get one chip covering both of
    // their categories, so they are not listed twice.
    final present = DocumentCategory.values
        .where(
          (c) =>
              !c.isIssuedReport &&
              (all.any((d) => d.category == c) || c == filter),
        )
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
                  count: all.length,
                  selected: filter == null && !reportsOnly,
                  onTap: () => onFilter(null),
                ),
                if (reportCount > 0 || reportsOnly)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: _FilterChip(
                      label: 'Reports',
                      count: reportCount,
                      selected: reportsOnly,
                      color: DocumentCategory.vitalReport.color,
                      onTap: onReportsOnly,
                    ),
                  ),
                for (final c in present)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: _FilterChip(
                      label: c.label,
                      count: all.where((d) => d.category == c).length,
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
    this.count,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// How many documents this chip would leave on screen. Shown because a
  /// filter that silently leads to an empty list is a dead end the patient
  /// only discovers by tapping it.
  final int? count;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.brandIndigo;
    final n = count;

    return FilterChip(
      label: Text(n == null ? label : '$label  $n'),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: c.withValues(alpha: 0.15),
      checkmarkColor: c,
      side: selected ? BorderSide(color: c.withValues(alpha: 0.45)) : null,
      labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        color: selected ? c : AppPalette.ink(context),
      ),
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
