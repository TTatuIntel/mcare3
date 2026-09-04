import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';
import '../../shared/widgets/staff_stat_cards.dart';

class DoctorPatientsView extends StatefulWidget {
  const DoctorPatientsView({super.key});

  @override
  State<DoctorPatientsView> createState() => _DoctorPatientsViewState();
}

class _DoctorPatientsViewState extends State<DoctorPatientsView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      scrollable: true,
      currentRoute: RouteNames.doctorPatients,
      destinations: StaffDestinations.doctor(),
      profileRoute: RouteNames.doctorProfile,
      notificationsRoute: RouteNames.doctorNotifications,
      title: 'Patients',
      subtitle:
          'Assigned caseload · ${DateFormat.MMMEd().format(DateTime.now())}',
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final s = StaffState.instance;
          final all = s.assignedPatientsForDoctor();
          final q = _search.text.trim();
          final list = all.where((p) => s.patientMatchesQuery(p, q)).toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

          final accent = Theme.of(context).colorScheme.primary;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: StaffStatCardsGrid(
                  cards: [
                    StaffStatCardData(
                      value: '${all.length}',
                      label: 'Assigned',
                      detail: q.isEmpty
                          ? 'Patients on your caseload'
                          : '${list.length} match search',
                      icon: AppIcons.patients,
                      accent: accent,
                    ),
                    StaffStatCardData(
                      value: '${list.length}',
                      label: 'Showing',
                      detail: q.isEmpty ? 'All patients' : 'Filtered results',
                      icon: AppIcons.search,
                      accent: accent,
                      onTap: q.isNotEmpty
                          ? () {
                              _search.clear();
                              setState(() {});
                            }
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 1,
                child: SectionLabel(
                  title: 'Search patients',
                  icon: AppIcons.search,
                  actionLabel: q.isNotEmpty ? 'Clear' : null,
                  onAction: q.isNotEmpty
                      ? () {
                          _search.clear();
                          setState(() {});
                        }
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              StaggeredEntry(
                index: 2,
                child: GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        AppIcons.search,
                        size: 18,
                        color: AppPalette.textMuted(context),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _search,
                          style: Theme.of(context).textTheme.bodyMedium,
                          decoration: InputDecoration(
                            hintText: 'Name, email, phone or patient ID',
                            hintStyle: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppPalette.textMuted(context),
                                ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 3,
                child: SectionLabel(
                  title: 'Your patients',
                  icon: AppIcons.patients,
                  trailing: '${list.length}/${all.length}',
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              StaggeredEntry(
                index: 4,
                child: all.isEmpty
                    ? GlassCard(
                        frosted: true,
                        child: const EmptyStateView(
                          icon: AppIcons.patients,
                          title: 'No assigned patients',
                          message:
                              'When patients are assigned to you, they appear here.',
                          compact: true,
                        ),
                      )
                    : list.isEmpty
                    ? GlassCard(
                        frosted: true,
                        child: EmptyStateView(
                          icon: AppIcons.search,
                          title: 'No matches',
                          message:
                              'Try another name, email, phone number or patient ID.',
                          compact: true,
                          actionLabel: 'Clear search',
                          onAction: () {
                            _search.clear();
                            setState(() {});
                          },
                        ),
                      )
                    : StaffListCard(
                        children: list
                            .map(
                              (p) => StaffPatientRow(
                                name: p.name,
                                summary: s.patientListSubtitle(p),
                                risk: p.risk,
                                lastActivity: p.lastReading,
                                unreadAlerts: 0,
                                onTap: () => Navigator.of(context).pushNamed(
                                  RouteNames.doctorPatientChart,
                                  arguments: p.id,
                                ),
                              ),
                            )
                            .toList(),
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
