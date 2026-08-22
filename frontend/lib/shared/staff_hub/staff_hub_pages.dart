import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_page_route.dart';
import '../widgets/section_label.dart';
import '../widgets/staff_filter_chip.dart';
import 'staff_hub_components.dart';
import 'staff_hub_models.dart';

typedef StaffRouteOpener = void Function(String route);

class StaffHubHomePage extends StatelessWidget {
  const StaffHubHomePage({
    super.key,
    required this.snapshot,
    required this.openRoute,
    required this.openSection,
  });

  final StaffHubSnapshot snapshot;
  final StaffRouteOpener openRoute;
  final ValueChanged<StaffHubSection> openSection;

  @override
  Widget build(BuildContext context) {
    final role = snapshot.role;
    final accent = role.accent;
    final requestCount = snapshot.workItems
        .where(
          (item) =>
              item.type == StaffWorkItemType.approval ||
              item.type == StaffWorkItemType.careRequest ||
              item.type == StaffWorkItemType.assignment,
        )
        .fold(0, (sum, item) => sum + item.count);
    final urgentCount = snapshot.urgentCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StaffHubPermissionNotice(role: role),
        if (role == UserRole.mcareAssistant)
          const SizedBox(height: AppSpacing.lg),
        const StaffHubSectionHeading(
          title: 'Choose a task',
          subtitle: 'A short path to the work that needs attention.',
        ),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth < 920;
            final tasks = <Widget>[
              StaffHubTaskCard(
                title: 'Urgent care',
                description: 'Critical alerts and active emergency work',
                icon: AppIcons.alert,
                color: AppColors.critical,
                count: urgentCount,
                horizontal: horizontal,
                onTap: () => openSection(StaffHubSection.work),
              ),
              if (snapshot.peopleLinks.isNotEmpty)
                StaffHubTaskCard(
                  title: 'People',
                  description: 'Directories available to your role',
                  icon: AppIcons.users,
                  color: accent,
                  count: snapshot.peopleLinks.length,
                  horizontal: horizontal,
                  onTap: () => openSection(StaffHubSection.people),
                ),
              if (snapshot.canManageRequests)
                StaffHubTaskCard(
                  title: 'Requests',
                  description: 'Approvals, assignments and delegated requests',
                  icon: AppIcons.approval,
                  color: AppColors.info,
                  count: requestCount,
                  horizontal: horizontal,
                  onTap: () => openSection(StaffHubSection.work),
                ),
              StaffHubTaskCard(
                title: 'Platform',
                description: 'Settings, tools and permitted system controls',
                icon: AppIcons.system,
                color: AppColors.tempTeal,
                horizontal: horizontal,
                onTap: () => openSection(StaffHubSection.more),
              ),
            ];

            if (horizontal) {
              final spacing = AppSpacing.sm;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < tasks.length; i++) ...[
                    tasks[i],
                    if (i < tasks.length - 1) SizedBox(height: spacing),
                  ],
                ],
              );
            }

            return GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: AppSpacing.lg,
              crossAxisSpacing: AppSpacing.lg,
              childAspectRatio: 1.05,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: tasks,
            );
          },
        ),
        const SizedBox(height: AppSpacing.xxl),
        StaffHubSectionHeading(
          title: 'Next actions',
          subtitle: snapshot.workItems.isEmpty
              ? 'No open items are visible in your current scope.'
              : 'Counts come from the current signed-in session.',
          trailing: snapshot.workItems.length > 3
              ? TextButton(
                  onPressed: () => openSection(StaffHubSection.work),
                  child: const Text('View all'),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        if (snapshot.workItems.isEmpty)
          const StaffHubEmptyState(
            title: 'No open work',
            message:
                'This view will update when the current session receives new items.',
          )
        else
          StaffHubSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < snapshot.workItems.take(3).length; i++) ...[
                  StaffHubWorkRow(
                    item: snapshot.workItems[i],
                    accent: accent,
                    compact: MediaQuery.sizeOf(context).width < 560,
                    onTap: () => openRoute(snapshot.workItems[i].route),
                  ),
                  if (i < snapshot.workItems.take(3).length - 1)
                    Divider(height: 1, color: AppPalette.border(context)),
                ],
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        StaffHubSurface(
          onTap: () => openSection(StaffHubSection.work),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.tempTeal.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Icon(AppIcons.vitals, color: AppColors.tempTeal),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Operations overview',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${snapshot.openWorkCount} open work items · ${snapshot.activePatients} active patients',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(AppIcons.chevronRight, color: AppPalette.textMuted(context)),
            ],
          ),
        ),
      ],
    );
  }
}

class StaffHubWorkPage extends StatefulWidget {
  const StaffHubWorkPage({
    super.key,
    required this.snapshot,
    required this.openRoute,
  });

  final StaffHubSnapshot snapshot;
  final StaffRouteOpener openRoute;

  @override
  State<StaffHubWorkPage> createState() => _StaffHubWorkPageState();
}

class _StaffHubWorkPageState extends State<StaffHubWorkPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  StaffWorkUrgency? _urgency;
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters => _urgency != null || _query.isNotEmpty;

  int _countFor(StaffWorkUrgency? urgency) {
    if (urgency == null) return widget.snapshot.workItems.length;
    return widget.snapshot.workItems.where((i) => i.urgency == urgency).length;
  }

  List<StaffWorkItem> _computeVisible() {
    Iterable<StaffWorkItem> stream = widget.snapshot.workItems;
    if (_urgency != null) {
      stream = stream.where((item) => item.urgency == _urgency);
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      stream = stream.where(
        (item) =>
            item.title.toLowerCase().contains(q) ||
            item.description.toLowerCase().contains(q),
      );
    }
    return stream.toList();
  }

  void _clearFilters() {
    setState(() {
      _urgency = null;
      _query = '';
      _searchCtrl.clear();
    });
  }

  String get _urgencyKey => switch (_urgency) {
        null => 'all',
        StaffWorkUrgency.critical => 'urgent',
        StaffWorkUrgency.attention => 'attention',
        StaffWorkUrgency.routine => 'routine',
      };

  void _setUrgency(String key) {
    setState(() {
      _urgency = switch (key) {
        'urgent' => StaffWorkUrgency.critical,
        'attention' => StaffWorkUrgency.attention,
        'routine' => StaffWorkUrgency.routine,
        _ => null,
      };
    });
  }

  String _sectionTitle() => switch (_urgency) {
        null => 'Open work',
        StaffWorkUrgency.critical => 'Urgent',
        StaffWorkUrgency.attention => 'Needs attention',
        StaffWorkUrgency.routine => 'Routine',
      };

  @override
  Widget build(BuildContext context) {
    final total = widget.snapshot.workItems.length;
    final visible = _computeVisible();

    final options = [
      StaffFilterOption(
        value: 'all',
        label: 'All · ${_countFor(null)}',
      ),
      StaffFilterOption(
        value: 'urgent',
        label: 'Urgent · ${_countFor(StaffWorkUrgency.critical)}',
        color: AppColors.critical,
      ),
      StaffFilterOption(
        value: 'attention',
        label: 'Watch · ${_countFor(StaffWorkUrgency.attention)}',
        color: AppColors.warning,
      ),
      StaffFilterOption(
        value: 'routine',
        label: 'Routine · ${_countFor(StaffWorkUrgency.routine)}',
        color: AppColors.info,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StaffHubSectionHeading(
          title: 'Work queue',
          subtitle:
              '${widget.snapshot.openWorkCount} open items across the workspaces you can access.',
        ),
        const SizedBox(height: AppSpacing.lg),
        StaggeredEntry(
          index: 0,
          child: _WorkSearchField(
            controller: _searchCtrl,
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        StaggeredEntry(
          index: 1,
          child: StaffFilterChipBar(
            options: options,
            selected: _urgencyKey,
            onSelected: _setUrgency,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        StaggeredEntry(
          index: 2,
          child: SectionLabel(
            title: _sectionTitle(),
            icon: AppIcons.alert,
            trailing: '${visible.length}/$total',
            actionLabel: _hasActiveFilters ? 'Clear' : null,
            onAction: _hasActiveFilters ? _clearFilters : null,
          ),
        ),
        StaggeredEntry(
          index: 3,
          child: visible.isEmpty
              ? StaffHubEmptyState(
                  title: 'Nothing in this view',
                  message: _hasActiveFilters
                      ? 'Try clearing the search or picking another chip.'
                      : 'Return when the session updates.',
                )
              : StaffHubSurface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < visible.length; i++) ...[
                        StaffHubWorkRow(
                          item: visible[i],
                          accent: widget.snapshot.role.accent,
                          compact:
                              MediaQuery.sizeOf(context).width < 560,
                          onTap: () =>
                              widget.openRoute(visible[i].route),
                        ),
                        if (i < visible.length - 1)
                          Divider(
                            height: 1,
                            color: AppPalette.border(context),
                          ),
                      ],
                    ],
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'The hub is read-only. Decisions and clinical actions open the existing secured workflow.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppPalette.textMuted(context)),
        ),
      ],
    );
  }
}

class _WorkSearchField extends StatelessWidget {
  const _WorkSearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      decoration: InputDecoration(
        hintText: 'Search work queue…',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close_rounded, size: 19),
              ),
        isDense: true,
      ),
    );
  }
}

class StaffHubPeoplePage extends StatelessWidget {
  const StaffHubPeoplePage({
    super.key,
    required this.snapshot,
    required this.openRoute,
  });

  final StaffHubSnapshot snapshot;
  final StaffRouteOpener openRoute;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StaffHubSectionHeading(
          title: 'People',
          subtitle: 'Directories and access tools available to this account.',
        ),
        const SizedBox(height: AppSpacing.lg),
        if (snapshot.peopleLinks.isEmpty)
          const StaffHubEmptyState(
            icon: AppIcons.permissions,
            title: 'No people workspaces delegated',
            message:
                'Ask an administrator if your responsibilities require directory access.',
          )
        else
          _LinkGrid(links: snapshot.peopleLinks, openRoute: openRoute),
      ],
    );
  }
}

class StaffHubMorePage extends StatelessWidget {
  const StaffHubMorePage({
    super.key,
    required this.snapshot,
    required this.openRoute,
  });

  final StaffHubSnapshot snapshot;
  final StaffRouteOpener openRoute;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StaffHubSectionHeading(
          title: 'More',
          subtitle:
              'Communication, platform tools, settings and account controls.',
        ),
        const SizedBox(height: AppSpacing.lg),
        StaffHubPermissionNotice(role: snapshot.role),
        if (snapshot.role == UserRole.mcareAssistant)
          const SizedBox(height: AppSpacing.lg),
        _LinkGrid(links: snapshot.moreLinks, openRoute: openRoute),
      ],
    );
  }
}

class _LinkGrid extends StatelessWidget {
  const _LinkGrid({required this.links, required this.openRoute});

  final List<StaffHubLink> links;
  final StaffRouteOpener openRoute;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 2 : 1;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - AppSpacing.md) / columns;
        // A Wrap lets each card grow for larger accessibility text instead of
        // forcing copy into a fixed grid aspect ratio. At the reference mobile
        // width this remains the same compact single-column card list.
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final link in links)
              SizedBox(
                width: width,
                child: StaffHubLinkTile(
                  link: link,
                  onTap: () => openRoute(link.route),
                ),
              ),
          ],
        );
      },
    );
  }
}

