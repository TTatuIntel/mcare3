import 'user_role.dart';

enum ApprovalStatus { active, pendingApproval, suspended, rejected }

class AppUser {
  const AppUser({
    required this.id,
    required this.uniqueId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    this.phone,
    this.avatarUrl,
    this.specialty,
    this.licenseNumber,
    this.approvalStatus = ApprovalStatus.active,
    this.emailVerified = true,
    this.mustChangePassword = false,
    this.joinedAt,
  });

  final String id;
  final String uniqueId;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final String? specialty;
  final String? licenseNumber;
  final UserRole role;
  final ApprovalStatus approvalStatus;
  final bool emailVerified;
  final bool mustChangePassword;

  /// When the account was created, as the server recorded it. Null for a
  /// session restored from an older stored payload, which is why every reader
  /// has to treat "unknown" as "not new".
  final DateTime? joinedAt;

  /// Whole days since the account was created, or null when unknown.
  int? get daysSinceJoining {
    final joined = joinedAt;
    if (joined == null) return null;
    final days = DateTime.now().difference(joined).inDays;
    return days < 0 ? 0 : days;
  }

  String get fullName => '$firstName $lastName';
  String get initials =>
      (firstName.isNotEmpty ? firstName[0] : '') +
      (lastName.isNotEmpty ? lastName[0] : '');

  /// Staff accounts need name + phone before using clinical/admin tools.
  bool get isProfileComplete {
    if (firstName.trim().isEmpty || lastName.trim().isEmpty) return false;
    final p = phone?.trim() ?? '';
    return p.length >= 7;
  }

  AppUser copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? avatarUrl,
    String? specialty,
    String? licenseNumber,
    ApprovalStatus? approvalStatus,
    bool? emailVerified,
    bool? mustChangePassword,
    DateTime? joinedAt,
  }) => AppUser(
    id: id,
    uniqueId: uniqueId,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    email: email ?? this.email,
    role: role,
    phone: phone ?? this.phone,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    specialty: specialty ?? this.specialty,
    licenseNumber: licenseNumber ?? this.licenseNumber,
    approvalStatus: approvalStatus ?? this.approvalStatus,
    emailVerified: emailVerified ?? this.emailVerified,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    joinedAt: joinedAt ?? this.joinedAt,
  );

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final roleRaw = json['role'] as String? ?? 'patient';
    final role = UserRole.values.firstWhere(
      (r) => r.name == roleRaw || r.name == _roleAlias(roleRaw),
      orElse: () => UserRole.patient,
    );
    final statusRaw = json['approval_status'] as String? ?? 'active';
    final approvalStatus = ApprovalStatus.values.firstWhere(
      (s) => s.name == statusRaw,
      orElse: () => ApprovalStatus.active,
    );
    return AppUser(
      id: json['id'] as String? ?? '',
      uniqueId: json['unique_id'] as String? ?? '',
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      specialty: json['specialty'] as String?,
      licenseNumber: json['license_number'] as String?,
      role: role,
      approvalStatus: approvalStatus,
      emailVerified: json['email_verified'] as bool? ?? true,
      mustChangePassword: json['must_change_password'] as bool? ?? false,
      joinedAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
    );
  }

  static String _roleAlias(String raw) {
    if (raw == 'mcare_assistant') return 'mcareAssistant';
    return raw;
  }
}
