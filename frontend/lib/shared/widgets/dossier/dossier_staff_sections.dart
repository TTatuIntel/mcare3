import 'package:flutter/material.dart';

import '../../auth/auth_state.dart';
import '../../models/user_dossier.dart';
import '../../models/user_role.dart';
import '../../theme/app_colors.dart';
import '../app_icons.dart';
import 'dossier_blocks.dart';

/// Staff halves of the dossier plus the two segments every role shares.
///
/// A doctor's record is built to answer the same questions a patient's does:
/// who are they, how did they get here, what have they actually been doing,
/// and what can they do on the platform.

// ---------------------------------------------------------------------------
// Staff overview — application, credentials, and platform authority
// ---------------------------------------------------------------------------

List<Widget> buildStaffOverviewSections(BuildContext context, UserDossier d) {
  final app = d.application;
  final practice = d.practice;
  final access = d.access;

  return [
    DossierCard(
      title: 'Application & credentials',
      icon: AppIcons.approval,
      emptyMessage: 'No application details recorded.',
      children: app.hasContent
          ? [
              DossierRow(label: 'Applied', value: dossierDate(app.appliedAt)),
              DossierRow(label: 'Specialty', value: app.specialty),
              DossierRow(label: 'License no.', value: app.licenseNumber),
              DossierRow(
                label: 'Credential file',
                value: app.hasCredentialDocument
                    ? (app.credentialDocumentName ?? 'On file')
                    : null,
                valueColor:
                    app.hasCredentialDocument ? AppColors.success : null,
              ),
              if (app.approvedAt != null) ...[
                DossierRow(
                  label: 'Approved',
                  value: dossierDate(app.approvedAt),
                  valueColor: AppColors.success,
                  emphasise: true,
                ),
                DossierRow(label: 'Approved by', value: app.approvedByName),
                DossierRow(label: 'Approval note', value: app.approvalNote),
              ],
              if (app.rejectedAt != null) ...[
                DossierRow(
                  label: 'Rejected',
                  value: dossierDate(app.rejectedAt),
                  valueColor: AppColors.critical,
                  emphasise: true,
                ),
                DossierRow(label: 'Reason', value: app.rejectionReason),
              ],
              if (app.inviteSentAt != null) ...[
                DossierRow(
                  label: 'Invite sent',
                  value: dossierDate(app.inviteSentAt),
                ),
                DossierRow(
                  label: 'Invite status',
                  value: app.inviteAcceptedAt != null
                      ? 'Accepted ${dossierDate(app.inviteAcceptedAt)}'
                      : app.invitePending
                          ? 'Pending — expires '
                              '${dossierDate(app.inviteExpiresAt)}'
                          : 'Expired',
                  valueColor: app.inviteAcceptedAt != null
                      ? AppColors.success
                      : AppColors.warning,
                ),
              ],
            ]
          : const [],
    ),
    if (practice?.provider != null)
      DossierCard(
        title: 'Practice profile',
        icon: AppIcons.careTeam,
        children: [
          DossierRow(label: 'Facility', value: practice!.facility),
          DossierRow(
            label: 'Experience',
            value: practice.yearsExperience == null
                ? null
                : '${practice.yearsExperience} years',
          ),
          DossierRow(
            label: 'Rating',
            value: practice.rating == null
                ? null
                : '${practice.rating!.toStringAsFixed(1)} '
                    '(${practice.totalReviews ?? 0} reviews)',
          ),
          DossierRow(
            label: 'Languages',
            value: practice.languages.isEmpty
                ? null
                : practice.languages.join(', '),
          ),
          DossierRow(label: 'Bio', value: practice.bio),
        ],
      ),
    DossierCard(
      title: 'Platform permissions',
      icon: AppIcons.permissions,
      trailing: access?.implicitAll == true
          ? 'Full access'
          : '${access?.granted.length ?? 0} granted',
      emptyMessage: 'No permissions granted — this account cannot act yet.',
      children: [
        if (access != null && access.implicitAll)
          const DossierRow(
            label: 'Scope',
            value: 'Administrator — holds every permission implicitly',
            valueColor: AppColors.adminPurple,
            emphasise: true,
          ),
        if (access != null && access.granted.isNotEmpty)
          DossierChips(
            labels: access.granted.map(_permissionLabel).toList(),
            color: AppColors.adminPurple,
          ),
      ],
    ),
  ];
}

// ---------------------------------------------------------------------------
// Staff work — caseload and output
// ---------------------------------------------------------------------------

List<Widget> buildStaffWorkSections(BuildContext context, UserDossier d) {
  final p = d.practice;
  final access = d.access;

  if (p == null) {
    return const [
      DossierCard(
        title: 'Work',
        icon: AppIcons.assignments,
        emptyMessage: 'No workload recorded for this account.',
        children: [],
      ),
    ];
  }

  final isDoctor = d.isDoctor;

  return [
    DossierCard(
      title: 'Output',
      icon: AppIcons.analytics,
      children: [
        if (isDoctor) ...[
          DossierRow(
            label: 'Active caseload',
            value: '${p.caseloadActive} patient'
                '${p.caseloadActive == 1 ? '' : 's'}',
            emphasise: true,
          ),
          DossierRow(
            label: 'Past caseload',
            value: '${p.caseloadEnded} ended',
          ),
          DossierRow(
            label: 'Patients alerting',
            value: '${p.patientsAlerting}',
            valueColor:
                p.patientsAlerting > 0 ? AppColors.critical : null,
          ),
          DossierRow(
            label: 'Prescriptions',
            value: '${p.prescriptionsActive} active of '
                '${p.prescriptionsIssued} issued',
          ),
          DossierRow(
            label: 'Meal plans',
            value: '${p.mealPlansAssigned} assigned',
          ),
          DossierRow(
            label: 'Reports',
            value: '${p.reportsPublished} published of '
                '${p.reportsAuthored} written',
          ),
          DossierRow(
            label: 'Appointments',
            value: '${p.appointmentsUpcoming} upcoming of '
                '${p.appointmentsTotal} total',
          ),
          DossierRow(
            label: 'Care requests',
            value: '${p.careRequestsPending} pending of '
                '${p.careRequestsHandled} received',
            valueColor:
                p.careRequestsPending > 0 ? AppColors.warning : null,
          ),
        ] else ...[
          DossierRow(
            label: 'Tickets assigned',
            value: '${access?.supportTicketsAssigned ?? 0}',
          ),
          DossierRow(
            label: 'Actions logged',
            value: '${d.activity.where((a) => a.isActor).length}',
          ),
          DossierRow(
            label: 'Permissions',
            value: access?.implicitAll == true
                ? 'All (administrator)'
                : '${access?.granted.length ?? 0} of '
                    '${access?.available.length ?? 0}',
          ),
        ],
      ],
    ),
    if (isDoctor)
      DossierCard(
        title: 'Current caseload',
        icon: AppIcons.patients,
        trailing: '${p.caseload.length}',
        emptyMessage: 'No patients assigned to this doctor.',
        children: [
          for (final c in p.caseload.take(20))
            DossierRecordRow(
              icon: AppIcons.user,
              iconColor: AppColors.brandIndigo,
              title: _s(c['patient_name']) ?? 'Patient',
              subtitle: [
                _s(c['patient_unique_id']),
                _s(c['assigned_reason']),
              ].whereType<String>().join(' · '),
              badge: dossierHumanize(_s(c['role'])),
              badgeColor: AppColors.doctorGreen,
              meta: dossierDate(_d(c['assigned_at'])),
            ),
        ],
      ),
    if (isDoctor)
      DossierCard(
        title: 'Recent appointments',
        icon: AppIcons.appointment,
        trailing: '${p.recentAppointments.length}',
        emptyMessage: 'No appointments booked.',
        children: [
          for (final a in p.recentAppointments.take(12))
            DossierRecordRow(
              icon: AppIcons.appointment,
              iconColor: AppColors.bpPurple,
              title: _s(a['patient_name']) ?? 'Patient',
              subtitle: [
                dossierHumanize(_s(a['type'])),
                _s(a['reason']),
              ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
              badge: dossierHumanize(_s(a['status'])),
              badgeColor: switch (_s(a['status'])) {
                'completed' => AppColors.success,
                'cancelled' || 'missed' => AppColors.critical,
                _ => AppColors.info,
              },
              meta: dossierDateTime(_d(a['scheduled_at'])),
            ),
        ],
      ),
    if (isDoctor)
      DossierCard(
        title: 'Reports authored',
        icon: AppIcons.report,
        trailing: '${p.recentReports.length}',
        emptyMessage: 'No reports written.',
        children: [
          for (final r in p.recentReports.take(12))
            DossierRecordRow(
              icon: AppIcons.report,
              iconColor: AppColors.doctorGreen,
              title: _s(r['title']) ?? 'Report',
              subtitle: _s(r['patient_name']),
              badge: r['published'] == true ? 'Published' : 'Draft',
              badgeColor: r['published'] == true
                  ? AppColors.success
                  : AppColors.textMutedAA,
              meta: dossierDate(_d(r['created_at'])),
            ),
        ],
      ),
    if (access != null && access.grants.isNotEmpty)
      DossierCard(
        title: 'Permission grants',
        icon: AppIcons.permissions,
        trailing: '${access.grants.length}',
        children: [
          for (final g in access.grants)
            DossierRecordRow(
              icon: AppIcons.permissions,
              iconColor: AppColors.adminPurple,
              title: _permissionLabel('${g['key']}'),
              subtitle: _s(g['granted_by_name']) == null
                  ? null
                  : 'granted by ${_s(g['granted_by_name'])}',
              meta: dossierDate(_d(g['granted_at'])),
            ),
        ],
      ),
  ];
}

// ---------------------------------------------------------------------------
// Account — the same for every role
// ---------------------------------------------------------------------------

List<Widget> buildAccountSections(BuildContext context, UserDossier d) {
  final a = d.account;
  final s = d.security;
  final app = d.application;

  // Session fingerprints are only meaningful to a full admin.
  final showSessions = AuthState.instance.user?.role == UserRole.admin;

  return [
    DossierCard(
      title: 'Identity',
      icon: AppIcons.user,
      children: [
        DossierRow(label: 'Full name', value: a.name),
        DossierRow(label: 'mCare ID', value: a.uniqueId),
        DossierRow(label: 'Role', value: a.role.label),
        DossierRow(label: 'Email', value: a.email),
        DossierRow(label: 'Phone', value: a.phone),
        DossierRow(
          label: 'Profile',
          value: a.profileComplete ? 'Complete' : 'Incomplete',
          valueColor:
              a.profileComplete ? AppColors.success : AppColors.warning,
        ),
      ],
    ),
    DossierCard(
      title: 'Account dates',
      icon: AppIcons.calendar,
      children: [
        DossierRow(
          label: a.role == UserRole.patient ? 'Account opened' : 'Applied',
          value: dossierDate(a.createdAt),
          emphasise: true,
        ),
        DossierRow(
          label: 'Account age',
          value: a.accountAgeDays == null ? null : '${a.accountAgeDays} days',
        ),
        DossierRow(
          label: 'Email verified',
          value: a.emailVerified
              ? (dossierDate(a.emailVerifiedAt) ?? 'Yes')
              : 'Not verified',
          valueColor: a.emailVerified ? AppColors.success : AppColors.warning,
        ),
        if (app.approvedAt != null)
          DossierRow(
            label: 'Approved',
            value: '${dossierDate(app.approvedAt)}'
                '${app.approvedByName == null ? '' : ' by ${app.approvedByName}'}',
            valueColor: AppColors.success,
          ),
        if (app.rejectedAt != null)
          DossierRow(
            label: 'Rejected',
            value: dossierDate(app.rejectedAt),
            valueColor: AppColors.critical,
          ),
        DossierRow(
          label: 'Record updated',
          value: dossierDate(a.updatedAt),
        ),
      ],
    ),
    DossierCard(
      title: 'Sign-in & security',
      icon: AppIcons.lock,
      children: [
        DossierRow(
          label: 'Last sign-in',
          value: s.lastLoginAt == null
              ? 'Never signed in'
              : '${dossierDateTime(s.lastLoginAt)} '
                  '(${dossierRelative(s.lastLoginAt!)})',
          emphasise: true,
          valueColor: s.lastLoginAt == null ? AppColors.warning : null,
        ),
        DossierRow(label: 'Total sign-ins', value: '${s.loginCount}'),
        DossierRow(label: 'Sign-in methods', value: s.signInMethods),
        DossierRow(
          label: 'Last IP',
          value: s.lastLoginIp,
        ),
        DossierRow(
          label: 'Failed attempts',
          value: '${s.failedLoginAttempts}',
          valueColor:
              s.failedLoginAttempts > 0 ? AppColors.warning : null,
        ),
        DossierRow(
          label: 'Lockout',
          value: s.isLocked
              ? 'Locked until ${dossierDateTime(s.lockedUntil)}'
              : 'Not locked',
          valueColor: s.isLocked ? AppColors.critical : AppColors.success,
          emphasise: s.isLocked,
        ),
        DossierRow(
          label: 'Password',
          value: s.mustChangePassword
              ? 'Temporary — must change on next sign-in'
              : 'Set by user',
          valueColor: s.mustChangePassword ? AppColors.warning : null,
        ),
        DossierRow(label: 'Active sessions', value: '${s.activeSessions}'),
        DossierRow(label: 'Push devices', value: '${s.pushDevices}'),
      ],
    ),
    if (showSessions)
      DossierCard(
        title: 'Recent sessions',
        icon: AppIcons.security,
        trailing: '${s.sessions.length}',
        emptyMessage: 'No sessions on record.',
        children: [
          for (final session in s.sessions.take(8))
            DossierRecordRow(
              icon: AppIcons.security,
              iconColor: AppColors.info,
              title: session.name ?? 'Session',
              subtitle: session.createdAt == null
                  ? null
                  : 'started ${dossierDate(session.createdAt)}',
              meta: session.lastUsedAt == null
                  ? 'unused'
                  : dossierRelative(session.lastUsedAt!),
            ),
        ],
      ),
  ];
}

// ---------------------------------------------------------------------------
// Activity — lifecycle timeline plus the audit trail
// ---------------------------------------------------------------------------

List<Widget> buildActivitySections(BuildContext context, UserDossier d) {
  final byOthers = d.activity.where((a) => !a.isActor).toList();
  final byThem = d.activity.where((a) => a.isActor).toList();

  return [
    DossierCard(
      title: 'Account history',
      icon: AppIcons.audit,
      trailing: '${d.timeline.length}',
      children: [DossierTimeline(events: d.timeline, limit: 14)],
    ),
    DossierCard(
      title: 'Actions taken on this account',
      icon: AppIcons.permissions,
      trailing: '${byOthers.length}',
      emptyMessage: 'No staff decisions recorded.',
      children: [
        for (final a in byOthers.take(20))
          DossierRecordRow(
            icon: a.category == 'security' ? AppIcons.security : AppIcons.audit,
            iconColor: a.category == 'security'
                ? AppColors.critical
                : AppColors.info,
            title: dossierHumanize(a.action.replaceAll('.', ' ')),
            subtitle: [a.actor, a.target]
                .whereType<String>()
                .where((e) => e.isNotEmpty)
                .join(' · '),
            meta: dossierRelative(a.at),
          ),
      ],
    ),
    if (!d.isPatient)
      DossierCard(
        title: 'Actions this account performed',
        icon: AppIcons.audit,
        trailing: '${byThem.length}',
        emptyMessage: 'No logged activity.',
        children: [
          for (final a in byThem.take(20))
            DossierRecordRow(
              icon: a.category == 'security'
                  ? AppIcons.security
                  : AppIcons.audit,
              iconColor: a.category == 'security'
                  ? AppColors.critical
                  : AppColors.doctorGreen,
              title: dossierHumanize(a.action.replaceAll('.', ' ')),
              subtitle: a.target,
              meta: dossierRelative(a.at),
            ),
        ],
      ),
  ];
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/// `can_approve_healthworkers` → `Approve healthworkers`.
String _permissionLabel(String key) {
  final trimmed = key.startsWith('can_') ? key.substring(4) : key;
  return dossierHumanize(trimmed);
}

String? _s(dynamic v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

DateTime? _d(dynamic v) =>
    v == null ? null : DateTime.tryParse('$v')?.toLocal();
