import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../admin/reports/patient_report_builder_sheet.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/patient_chart_api.dart';
import '../../../core/env/app_env.dart';
import '../../../core/realtime/realtime_refresh_mixin.dart';
import '../../../core/web/web_platform.dart' as web_platform;
import '../../auth/auth_state.dart';
import '../../constants/route_names.dart';
import '../../models/patient_profile.dart';
import '../../models/sos.dart';
import '../../models/user_role.dart';
import '../../state/staff_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../app_button.dart';
import '../app_icons.dart';
import '../app_text_field.dart';
import '../app_toast.dart';
import '../empty_state.dart';
import '../patient_page_blocks.dart';
import '../period_filter_bar.dart';
import 'patient_chart_widgets.dart';

/// The clinical chart: what is going on with this patient, over a period the
/// reader chooses.
///
/// This replaced a profile card that showed the account — name, ID, a health
/// score, a list of conditions. Everything a clinician actually opens a chart
/// for (the last readings and their shape, what the patient is taking, who is
/// on the care team, who to call, where they are, what has been written down)
/// lived on other screens, which is a long way to travel with an emergency
/// running. Every section here answers from the same window, so changing the
/// period changes the whole chart at once rather than one panel of it.
class PatientChartBody extends StatefulWidget {
  const PatientChartBody({
    super.key,
    required this.patientId,
    required this.fallbackName,
    this.header,
  });

  final String patientId;
  final String fallbackName;

  /// Rendered above the chart — the emergency this chart was opened from.
  final Widget? header;

  @override
  State<PatientChartBody> createState() => _PatientChartBodyState();
}

class _PatientChartBodyState extends State<PatientChartBody>
    with RealtimeRefreshMixin<PatientChartBody> {
  ChartPeriod _period = ChartPeriod.month;
  PatientChart? _chart;
  bool _loading = true;
  String? _error;

  /// Anchors for the summary strip. A count at the top of a long chart that
  /// does not take you to what it counted is a count you then have to go and
  /// find, so every stat chip opens and scrolls to its own section.
  final Map<String, GlobalKey<ChartSectionState>> _sections = {
    for (final name in const [
      'vitals',
      'alerts',
      'medications',
      'appointments',
      'notes',
    ])
      name: GlobalKey<ChartSectionState>(),
  };

  void _jumpToSection(String name) {
    final key = _sections[name];
    key?.currentState?.open();
    // After the expansion frame, so the scroll lands on the opened section
    // rather than where its collapsed header used to be.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key?.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.02,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    // After the first frame so opening the sheet is never blocked on a fetch.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    // A chart open during an emergency is a chart being changed underneath
    // the reader — a new reading, an alert, a handover, a note.
    watchRealtime(const {
      'vitals',
      'alerts',
      'medications',
      'appointments',
      'sos',
      'care',
      'reports',
      'documents',
      'profile',
    }, () => _load(quiet: true));
  }

  Future<void> _load({bool quiet = false}) async {
    if (!mounted) return;
    if (!quiet) setState(() => _loading = true);
    try {
      final chart = await PatientChartApi.instance.fetch(
        widget.patientId,
        _period,
      );
      if (!mounted) return;
      setState(() {
        if (chart != null) _chart = chart;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the chart.';
      });
    }
  }

  Future<void> _setPeriod(ChartPeriod period) async {
    if (period == _period) return;
    setState(() => _period = period);
    await _load();
  }

  // ------------------------------------------------------------ reach out
  Future<void> _call(String phone) async {
    if (kIsWeb) {
      web_platform.openWindow('tel:${phone.replaceAll(' ', '')}', '_self');
      return;
    }
    await Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    AppToast.success(context, 'Number copied — $phone');
  }

  Future<void> _openMap(String url) async {
    if (kIsWeb) {
      web_platform.openWindow(url, '_blank');
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    AppToast.success(context, 'Map link copied.');
  }

  Future<void> _addNote(String title, String body, bool publish) async {
    final note = await PatientChartApi.instance.addNote(
      widget.patientId,
      title: title,
      body: body,
      publish: publish,
    );
    if (!mounted || note == null) return;
    setState(() => _chart = _chart?.withNote(note));
    AppToast.success(
      context,
      publish ? 'Note saved and shared.' : 'Note saved to the chart.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final chart = _chart;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.header != null) ...[
          widget.header!,
          const SizedBox(height: AppSpacing.md),
        ],
        PeriodFilterBar(
          period: _period,
          onChanged: _setPeriod,
          busy: _loading,
          title: 'Chart period',
          subtitle:
              'Vitals, alerts, medication and notes all answer from this '
              'window.',
        ),
        const SizedBox(height: AppSpacing.sm),
        if (chart == null && _loading)
          const _ChartSkeleton()
        else if (chart == null)
          _ChartError(message: _error, onRetry: _load)
        else ...[
          if (_error != null) ...[
            _StaleNotice(onRetry: _load),
            const SizedBox(height: AppSpacing.sm),
          ],
          _ChartContent(
            chart: chart,
            fallbackName: widget.fallbackName,
            sections: _sections,
            onJump: _jumpToSection,
            onCall: _call,
            onMap: _openMap,
            onAddNote: _addNote,
          ),
        ],
      ],
    );
  }
}

// --------------------------------------------------------------- content

class _ChartContent extends StatelessWidget {
  const _ChartContent({
    required this.chart,
    required this.fallbackName,
    required this.sections,
    required this.onJump,
    required this.onCall,
    required this.onMap,
    required this.onAddNote,
  });

  final PatientChart chart;
  final String fallbackName;

  /// Keyed by the same names the summary strip jumps to.
  final Map<String, GlobalKey<ChartSectionState>> sections;
  final ValueChanged<String> onJump;
  final Future<void> Function(String phone) onCall;
  final Future<void> Function(String url) onMap;
  final Future<void> Function(String title, String body, bool publish)
  onAddNote;

  String get _name => chart.name.trim().isEmpty ? fallbackName : chart.name;

  String _range() =>
      '${DateFormat.yMMMd().format(chart.from)} — '
      '${DateFormat.yMMMd().format(chart.to)}';

  @override
  Widget build(BuildContext context) {
    final s = chart.summary;
    final health = chart.health;
    final role = AuthState.instance.user?.role;
    final canCreateReport =
        role == UserRole.doctor ||
        role == UserRole.admin ||
        role == UserRole.mcareAssistant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _IdentityCard(chart: chart, name: _name),
        const SizedBox(height: AppSpacing.md),
        _VitalityCard(chart: chart),
        const SizedBox(height: AppSpacing.sm),
        _StatStrip(chart: chart, onJump: onJump),
        const SizedBox(height: AppSpacing.sm),
        _QuickActions(
          phone: chart.phone,
          mapsUrl: chart.location.mapsUrl,
          onCall: onCall,
          onMap: onMap,
        ),
        const SizedBox(height: AppSpacing.md),

        // Vitals lead: an emergency is read off the numbers first.
        ChartSection(
          key: sections['vitals'],
          title: 'Vitals & trends',
          icon: AppIcons.vitals,
          accent: AppColors.info,
          count: chart.vitals.length,
          initiallyExpanded: true,
          summary: s.readings == 0
              ? 'Nothing recorded in this period'
              : '${s.readings} reading${s.readings == 1 ? '' : 's'}'
                    '${s.inRangePct == null ? '' : ' · ${s.inRangePct}% in range'}',
          child: chart.vitals.isEmpty
              ? const ChartEmpty('No vitals recorded in this period.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final vital in chart.vitals)
                      ChartVitalTile(vital: vital),
                  ],
                ),
        ),

        ChartSection(
          key: sections['alerts'],
          title: 'Alerts & emergencies',
          icon: AppIcons.alert,
          accent: s.alertsCritical > 0 || s.sosOpen > 0
              ? AppColors.critical
              : AppColors.warning,
          count: s.alerts + s.sos,
          initiallyExpanded: s.sosOpen > 0 || s.alertsCritical > 0,
          summary: s.alerts + s.sos == 0
              ? 'Nothing raised in this period'
              : '${s.alerts} alert${s.alerts == 1 ? '' : 's'}'
                    '${s.alertsCritical > 0 ? ' (${s.alertsCritical} critical)' : ''}'
                    ' · ${s.sos} SOS'
                    '${s.sosOpen > 0 ? ' · ${s.sosOpen} still open' : ''}',
          child: chart.alerts.isEmpty && chart.sos.isEmpty
              ? const ChartEmpty('No alerts or emergencies in this period.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final e in chart.sos) ChartEntryTile(entry: e),
                    for (final e in chart.alerts) ChartEntryTile(entry: e),
                  ],
                ),
        ),

        ChartSection(
          key: sections['medications'],
          title: 'Medications',
          icon: AppIcons.medication,
          accent: AppColors.doctorGreen,
          count: chart.medications.length,
          initiallyExpanded: s.medicationsActive > 0,
          summary: chart.medications.isEmpty
              ? 'Nothing prescribed'
              : '${s.medicationsActive} active'
                    '${s.adherencePct == null ? '' : ' · ${s.adherencePct}% of doses taken'}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (s.dosesScheduled > 0) ...[
                _AdherenceBar(
                  pct: s.adherencePct ?? 0,
                  taken: s.dosesTaken,
                  scheduled: s.dosesScheduled,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (chart.medications.isEmpty)
                const ChartEmpty('No medications on record for this period.')
              else
                for (final e in chart.medications) ChartEntryTile(entry: e),
            ],
          ),
        ),

        ChartSection(
          title: 'Next of kin',
          icon: AppIcons.users,
          accent: AppColors.critical,
          count: chart.nextOfKin.length,
          initiallyExpanded: chart.nextOfKin.isNotEmpty,
          summary: chart.nextOfKin.isEmpty
              ? 'Nobody listed — nobody to call'
              : chart.nextOfKin
                    .map((c) => '${c.name} (${c.relationship})')
                    .take(2)
                    .join(' · '),
          child: chart.nextOfKin.isEmpty
              ? const ChartEmpty(
                  'No emergency contact on file. Ask the patient to add one.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final contact in chart.nextOfKin)
                      _ContactTile(contact: contact, onCall: onCall),
                  ],
                ),
        ),

        ChartSection(
          title: 'Care team',
          icon: AppIcons.careTeam,
          accent: AppColors.doctorGreen,
          count: chart.careTeam.length,
          summary: chart.careTeam.isEmpty
              ? 'Nobody assigned to this patient'
              : chart.careTeam.map((m) => m.name).take(2).join(' · '),
          child: chart.careTeam.isEmpty
              ? const ChartEmpty(
                  'No provider is assigned. Hand this patient to someone from '
                  'the emergency response.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final member in chart.careTeam)
                      ChartEntryTile(
                        entry: ChartEntry(
                          id: member.name,
                          title: member.name,
                          subtitle: [
                            member.role,
                            if (member.specialty != null) member.specialty!,
                          ].join(' · '),
                          at: member.assignedAt,
                          trailing: 'Assigned',
                          tone: 'success',
                          detail: member.assignedBy == null
                              ? null
                              : 'Assigned by ${member.assignedBy}',
                        ),
                      ),
                  ],
                ),
        ),

        ChartSection(
          title: 'Location',
          icon: AppIcons.location,
          accent: AppColors.info,
          summary:
              chart.location.lastSeenLabel ??
              chart.location.address ??
              'No location on record',
          child: _LocationPanel(location: chart.location, onMap: onMap),
        ),

        ChartSection(
          title: 'Personal & account',
          icon: AppIcons.profile,
          summary: [
            if (chart.uniqueId != null) chart.uniqueId!,
            if (chart.phone != null) chart.phone!,
          ].join(' · '),
          child: Column(
            children: [
              if (chart.email != null)
                PatientCompactInfoRow(label: 'Email', value: chart.email!),
              if (chart.phone != null)
                PatientCompactInfoRow(label: 'Phone', value: chart.phone!),
              if (chart.uniqueId != null)
                PatientCompactInfoRow(
                  label: 'Patient ID',
                  value: chart.uniqueId!,
                ),
              if (chart.status != null)
                PatientCompactInfoRow(label: 'Status', value: chart.status!),
              if (chart.joinedAt != null)
                PatientCompactInfoRow(
                  label: 'Joined',
                  value: DateFormat.yMMMd().format(chart.joinedAt!),
                ),
              if (chart.location.address != null)
                PatientCompactInfoRow(
                  label: 'Address',
                  value: chart.location.address!,
                ),
            ],
          ),
        ),

        ChartSection(
          title: 'Health profile',
          icon: AppIcons.records,
          summary: health == null
              ? 'No health profile completed'
              : '${health.ageYears} yrs · ${health.gender.label} · '
                    '${health.bloodType.label} · BMI '
                    '${health.bmi.toStringAsFixed(1)}',
          child: health == null
              ? const ChartEmpty(
                  'The patient has not completed their health profile.',
                )
              : Column(
                  children: [
                    PatientCompactInfoRow(
                      label: 'Age',
                      value: '${health.ageYears} years',
                    ),
                    PatientCompactInfoRow(
                      label: 'Gender',
                      value: health.gender.label,
                    ),
                    PatientCompactInfoRow(
                      label: 'Blood type',
                      value: health.bloodType.label,
                    ),
                    PatientCompactInfoRow(
                      label: 'BMI',
                      value:
                          '${health.bmi.toStringAsFixed(1)} (${health.bmiCategory})',
                    ),
                    PatientCompactInfoRow(
                      label: 'Height / Weight',
                      value:
                          '${health.heightCm.toStringAsFixed(0)} cm · '
                          '${health.weightKg.toStringAsFixed(0)} kg',
                    ),
                    PatientCompactInfoRow(
                      label: 'Conditions',
                      value: health.chronicConditions.isEmpty
                          ? 'None recorded'
                          : health.chronicConditions.join(', '),
                    ),
                    PatientCompactInfoRow(
                      label: 'Allergies',
                      value: health.noKnownAllergies
                          ? 'None known'
                          : health.allergies.isEmpty
                          ? 'Not recorded'
                          : health.allergies.join(', '),
                    ),
                    PatientCompactInfoRow(
                      label: 'Self-reported meds',
                      value: health.noCurrentMedications
                          ? 'None'
                          : health.currentMedications.isEmpty
                          ? 'Not recorded'
                          : health.currentMedications.join(', '),
                    ),
                  ],
                ),
        ),

        ChartSection(
          key: sections['appointments'],
          title: 'Appointments',
          icon: AppIcons.appointment,
          count: chart.appointments.length,
          summary: chart.appointments.isEmpty
              ? 'None in this period'
              : '${s.appointmentsKept} kept · ${s.appointmentsMissed} missed',
          child: chart.appointments.isEmpty
              ? const ChartEmpty('No appointments in this period.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final e in chart.appointments)
                      ChartEntryTile(entry: e),
                  ],
                ),
        ),

        ChartSection(
          title: 'Meal plans',
          icon: AppIcons.meals,
          count: chart.meals.length,
          summary: chart.meals.isEmpty
              ? 'None assigned in this period'
              : '${s.meals} plan${s.meals == 1 ? '' : 's'} assigned',
          child: chart.meals.isEmpty
              ? const ChartEmpty('No meal plans assigned in this period.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final e in chart.meals) ChartEntryTile(entry: e),
                  ],
                ),
        ),

        ChartSection(
          title: 'Documents',
          icon: AppIcons.document,
          count: chart.documents.length,
          summary: chart.documents.isEmpty
              ? 'None uploaded in this period'
              : '${s.documents} file${s.documents == 1 ? '' : 's'}',
          child: chart.documents.isEmpty
              ? const ChartEmpty('No documents uploaded in this period.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final e in chart.documents) ChartEntryTile(entry: e),
                  ],
                ),
        ),

        ChartSection(
          key: sections['notes'],
          title: 'Notes & reports',
          icon: AppIcons.notes,
          count: chart.notes.length,
          initiallyExpanded: false,
          summary: chart.notes.isEmpty
              ? 'Nothing written in this period'
              : '${s.notes} note${s.notes == 1 ? '' : 's'} — newest: '
                    '${chart.notes.first.title}',
          trailingAction: canCreateReport
              ? AppButton(
                  label: role == UserRole.doctor
                      ? 'Write a clinical report'
                      : 'Issue a report from this record',
                  icon: AppIcons.report,
                  variant: AppButtonVariant.secondary,
                  expand: true,
                  onPressed: () {
                    if (role == UserRole.doctor) {
                      Navigator.of(context).pushNamed(
                        RouteNames.doctorReportEditor,
                        arguments: _name,
                      );
                      return;
                    }
                    PatientReportBuilderSheet.show(
                      context,
                      patientId: chart.patientId,
                      patientName: _name,
                    );
                  },
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (chart.notes.isEmpty)
                const ChartEmpty(
                  'Nothing written in this period. A note written here is '
                  'the note a report will carry.',
                )
              else
                for (final e in chart.notes) ChartEntryTile(entry: e),
              const SizedBox(height: AppSpacing.sm),
              _NoteComposer(onSave: onAddNote),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.xs),
        Text(
          'Chart period ${_range()}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            fontSize: 9.5,
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ header cards

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.chart, required this.name});

  final PatientChart chart;
  final String name;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    return parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : parts.first[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final health = chart.health;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppPalette.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Row(
        children: [
          Container(
            height: 46,
            width: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.doctorGreen, Color(0xFF1B5E3A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Text(
              _initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  [
                    if (chart.uniqueId != null) chart.uniqueId!,
                    if (health != null) '${health.ageYears} yrs',
                    if (health != null) health.gender.label,
                    if (health != null) health.bloodType.label,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Health score, and how much of the chosen period sat in range.
///
/// Two numbers rather than one, because they answer different questions: the
/// score is the standing risk carried by the profile, the percentage is what
/// actually happened in the window.
class _VitalityCard extends StatelessWidget {
  const _VitalityCard({required this.chart});

  final PatientChart chart;

  Color _scoreColor(int score) {
    if (score >= 70) return AppColors.success;
    if (score >= 55) return AppColors.info;
    if (score >= 40) return AppColors.warning;
    return AppColors.critical;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final health = chart.health;
    final inRange = chart.summary.inRangePct;

    if (health == null && inRange == null) {
      return const SizedBox.shrink();
    }

    final score = health?.healthScore ?? inRange ?? 0;
    final accent = _scoreColor(score);
    final conditions = health?.chronicConditions.length ?? 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          ChartScoreRing(value: score, color: accent),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      health == null ? 'In range' : 'Health score',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    if (health != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusPill,
                          ),
                        ),
                        child: Text(
                          health.healthCategory.toUpperCase(),
                          style: TextStyle(
                            color: accent,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (inRange != null)
                      '$inRange% of readings in range this period'
                    else
                      'No readings taken this period',
                    if (conditions > 0)
                      '$conditions chronic '
                          '${conditions == 1 ? 'condition' : 'conditions'}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.ink(context),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The period in six numbers, on two wrapped lines instead of three rows of
/// boxed tiles.
///
/// The tiles this replaces spelled each label in full caps over its number
/// over a caption, which cost most of a phone screen before the chart itself
/// began — and none of it was actionable. Each chip now carries its count
/// against its own icon, keeps the one qualifier that mattered (critical,
/// open, missed) as a dot and a tooltip, and opens the section it counts.
class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.chart, required this.onJump});

  final PatientChart chart;
  final ValueChanged<String> onJump;

  @override
  Widget build(BuildContext context) {
    final s = chart.summary;
    final missed = s.appointmentsMissed;
    final adherence = s.adherencePct;

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        ChartStatChip(
          label: 'readings',
          value: '${s.readings}',
          icon: AppIcons.vitals,
          accent: AppColors.info,
          flag: s.inRangePct != null && s.inRangePct! < 100
              ? '${s.inRangePct}% in range'
              : null,
          tooltip: s.readings == 0
              ? 'No readings in this period'
              : '${s.readings} readings'
                    '${s.inRangePct == null ? '' : ' · ${s.inRangePct}% in range'}',
          onTap: () => onJump('vitals'),
        ),
        ChartStatChip(
          label: 'alerts',
          value: '${s.alerts}',
          icon: AppIcons.alert,
          accent: s.alertsCritical > 0
              ? AppColors.critical
              : AppColors.warning,
          flag: s.alertsCritical > 0 ? '${s.alertsCritical} critical' : null,
          tooltip: s.alerts == 0
              ? 'No alerts in this period'
              : '${s.alerts} alerts'
                    '${s.alertsCritical > 0 ? ' · ${s.alertsCritical} critical' : ''}',
          onTap: () => onJump('alerts'),
        ),
        ChartStatChip(
          label: 'SOS',
          value: '${s.sos}',
          icon: AppIcons.sos,
          accent: s.sosOpen > 0 ? AppColors.critical : AppColors.success,
          flag: s.sosOpen > 0 ? '${s.sosOpen} still open' : null,
          tooltip: s.sos == 0
              ? 'No emergencies in this period'
              : '${s.sos} SOS'
                    '${s.sosOpen > 0 ? ' · ${s.sosOpen} still open' : ' · all closed'}',
          onTap: () => onJump('alerts'),
        ),
        ChartStatChip(
          label: 'meds',
          value: '${s.medicationsActive}',
          icon: AppIcons.medication,
          accent: AppColors.doctorGreen,
          flag: adherence != null && adherence < 80 ? '$adherence% taken' : null,
          tooltip: s.medicationsActive == 0
              ? 'Nothing active in this period'
              : '${s.medicationsActive} active'
                    '${adherence == null ? '' : ' · $adherence% of doses taken'}',
          onTap: () => onJump('medications'),
        ),
        ChartStatChip(
          label: 'appts',
          value: '${s.appointments}',
          icon: AppIcons.appointment,
          accent: missed > 0 ? AppColors.warning : AppColors.info,
          flag: missed > 0 ? '$missed missed' : null,
          tooltip: s.appointments == 0
              ? 'No appointments in this period'
              : '${s.appointments} appointments · ${s.appointmentsKept} kept'
                    ' · $missed missed',
          onTap: () => onJump('appointments'),
        ),
        ChartStatChip(
          label: 'notes',
          value: '${s.notes}',
          icon: AppIcons.notes,
          accent: AppColors.adminPurple,
          tooltip: '${s.notes} notes · ${s.documents} documents',
          onTap: () => onJump('notes'),
        ),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.phone,
    required this.mapsUrl,
    required this.onCall,
    required this.onMap,
  });

  final String? phone;
  final String? mapsUrl;
  final Future<void> Function(String phone) onCall;
  final Future<void> Function(String url) onMap;

  @override
  Widget build(BuildContext context) {
    final hasPhone = phone != null && phone!.trim().isNotEmpty;
    if (!hasPhone && mapsUrl == null) return const SizedBox.shrink();

    return Row(
      children: [
        if (hasPhone)
          Expanded(
            child: AppButton(
              label: kIsWeb ? 'Call patient' : 'Copy number',
              icon: AppIcons.phone,
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: () => onCall(phone!),
            ),
          ),
        if (hasPhone && mapsUrl != null) const SizedBox(width: AppSpacing.sm),
        if (mapsUrl != null)
          Expanded(
            child: AppButton(
              label: kIsWeb ? 'Open location' : 'Copy map link',
              icon: AppIcons.location,
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: () => onMap(mapsUrl!),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------- section bits

class _AdherenceBar extends StatelessWidget {
  const _AdherenceBar({
    required this.pct,
    required this.taken,
    required this.scheduled,
  });

  final int pct;
  final int taken;
  final int scheduled;

  @override
  Widget build(BuildContext context) {
    final color = pct >= 80
        ? AppColors.success
        : pct >= 50
        ? AppColors.warning
        : AppColors.critical;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Doses taken',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '$taken of $scheduled · $pct%',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: color.withValues(alpha: 0.14),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.onCall});

  final EmergencyContact contact;
  final Future<void> Function(String phone) onCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    contact.relationship,
                    contact.phone,
                    if (contact.email != null) contact.email!,
                  ].where((s) => s.trim().isNotEmpty).join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
          if (contact.phone.trim().isNotEmpty)
            IconButton(
              tooltip: kIsWeb ? 'Call' : 'Copy number',
              icon: const Icon(AppIcons.phone, size: 18),
              color: AppColors.critical,
              onPressed: () => onCall(contact.phone),
            ),
        ],
      ),
    );
  }
}

class _LocationPanel extends StatelessWidget {
  const _LocationPanel({required this.location, required this.onMap});

  final ChartLocation location;
  final Future<void> Function(String url) onMap;

  @override
  Widget build(BuildContext context) {
    final url = location.mapsUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (location.address != null)
          PatientCompactInfoRow(label: 'Address', value: location.address!),
        if (location.lastSeenLabel != null)
          PatientCompactInfoRow(
            label: location.source == 'sos' ? 'Last SOS fix' : 'Last seen',
            value: location.lastSeenLabel!,
          ),
        if (location.at != null)
          PatientCompactInfoRow(
            label: 'Recorded',
            value: DateFormat.yMMMd().add_jm().format(location.at!),
          ),
        if (location.address == null && location.lastSeenLabel == null)
          const ChartEmpty(
            'No address on file and no GPS fix from an emergency.',
          ),
        if (!location.consent)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Location sharing is off in the patient’s settings — a fix is '
              'only available from an SOS they raised.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (url != null) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: kIsWeb ? 'Open on the map' : 'Copy map link',
            icon: AppIcons.location,
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: () => onMap(url),
          ),
        ],
      ],
    );
  }
}

/// Writes a note onto the chart, against the period being read.
class _NoteComposer extends StatefulWidget {
  const _NoteComposer({required this.onSave});

  final Future<void> Function(String title, String body, bool publish) onSave;

  @override
  State<_NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends State<_NoteComposer> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _publish = false;
  bool _saving = false;
  bool _open = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      AppToast.warn(
        context,
        'A note needs a title and something written in it.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(title, body, _publish);
      if (!mounted) return;
      _title.clear();
      _body.clear();
      setState(() {
        _publish = false;
        _open = false;
      });
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not save the note.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return AppButton(
        label: 'Write a note',
        icon: AppIcons.edit,
        variant: AppButtonVariant.secondary,
        expand: true,
        onPressed: () => setState(() => _open = true),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _title,
          label: 'Note title',
          hint: 'What this note is about',
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          controller: _body,
          label: 'Note',
          hint: 'What was found, done, or decided',
          maxLines: 4,
        ),
        const SizedBox(height: AppSpacing.xs),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _publish,
          onChanged: _saving ? null : (v) => setState(() => _publish = v),
          title: Text(
            'Share with the patient',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          subtitle: Text(
            'Shared notes are the ones an issued report can carry.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Cancel',
                variant: AppButtonVariant.ghost,
                expand: true,
                onPressed: _saving ? null : () => setState(() => _open = false),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                label: 'Save note',
                icon: AppIcons.check,
                expand: true,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- states

class _ChartSkeleton extends StatelessWidget {
  const _ChartSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Container(
              height: i == 0 ? 74 : 58,
              decoration: BoxDecoration(
                color: AppPalette.surfaceAlt(context),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppPalette.border(context)),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Reading the chart…',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
          ),
        ),
      ],
    );
  }
}

class _ChartError extends StatelessWidget {
  const _ChartError({required this.message, required this.onRetry});

  final String? message;
  final Future<void> Function({bool quiet}) onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EmptyStateView(
          icon: AppIcons.alert,
          title: 'Could not load the chart',
          message: message ?? 'The record could not be read just now.',
          compact: true,
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Retry',
          icon: AppIcons.refresh,
          onPressed: () => onRetry(),
        ),
      ],
    );
  }
}

/// The chart on screen is the last one the server confirmed. Saying so is the
/// difference between stale data and wrong data.
class _StaleNotice extends StatelessWidget {
  const _StaleNotice({required this.onRetry});

  final Future<void> Function({bool quiet}) onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 17,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Showing the last chart that loaded — could not refresh.',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          TextButton(onPressed: () => onRetry(), child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Cached identity so the sheet can open with something before the fetch
/// lands. Kept deliberately thin: a stale chart would be worse than a slow
/// one, so only the name is trusted from cache.
String cachedPatientName(String patientId, String fallback) {
  if (!AppEnv.backendEnabled) return fallback;
  return StaffState.instance.patientClinicalDetail(patientId)?.name ??
      StaffState.instance.patientById(patientId)?.name ??
      fallback;
}
