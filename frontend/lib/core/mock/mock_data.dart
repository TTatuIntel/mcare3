import 'dart:math';

import '../../shared/constants/route_names.dart';
import '../../shared/models/app_user.dart';
import '../../shared/models/appointment.dart';
import '../../shared/models/care_provider.dart';
import '../../shared/models/document.dart';
import '../../shared/models/medication.dart';
import '../../shared/models/message.dart';
import '../../shared/models/notification_item.dart';
import '../../shared/models/patient_profile.dart';
import '../../shared/models/sos.dart';
import '../../shared/models/support_ticket.dart';
import '../../shared/models/user_role.dart';
import '../../shared/models/vital.dart';
import '../../shared/models/vital_report_request.dart';

class MockData {
  MockData._();

  static AppUser samplePatient() => const AppUser(
        id: 'u_001',
        uniqueId: 'MCR-001284',
        firstName: 'Amara',
        lastName: 'Okonkwo',
        email: 'amara.okonkwo@example.com',
        phone: '+254 712 000 000',
        role: UserRole.patient,
      );

  static AppUser sampleDoctor() => const AppUser(
        id: 'u_dr_001',
        uniqueId: 'MCR-DR-0231',
        firstName: 'Kojo',
        lastName: 'Mensah',
        email: 'dr.mensah@mcare.health',
        phone: '+254 720 444 100',
        role: UserRole.doctor,
      );

  static AppUser sampleAdmin() => const AppUser(
        id: 'u_ad_001',
        uniqueId: 'MCR-AD-0014',
        firstName: 'Nia',
        lastName: 'Chebet',
        email: 'admin@mcare.health',
        phone: '+254 720 111 010',
        role: UserRole.admin,
      );

  static AppUser sampleAssistant() => const AppUser(
        id: 'u_ma_001',
        uniqueId: 'MCR-MA-0058',
        firstName: 'Tendai',
        lastName: 'Moyo',
        email: 'assistant@mcare.health',
        phone: '+254 720 222 020',
        role: UserRole.mcareAssistant,
      );

  static AppUser sampleExternalDoctor() => const AppUser(
        id: 'u_ext_001',
        uniqueId: 'MCR-EX-0007',
        firstName: 'Rohan',
        lastName: 'Patel',
        email: 'rohan.external@partnerhealth.com',
        phone: '',
        role: UserRole.externalDoctor,
      );

  /// Vitals the patient's care team has assigned and locked. The patient
  /// can still add optional vitals on top, but cannot untrack these.
  static List<VitalKey> seedAssignedVitals() => const [
        VitalKey.bloodPressure,
        VitalKey.bloodGlucose,
      ];

  static List<VitalReading> seedVitals() {
    final rng = Random(42);
    final now = DateTime.now();
    final out = <VitalReading>[];

    void addSeries({
      required VitalKey vital,
      required double base,
      double? baseSecondary,
      required double jitter,
      int perDay = 2,
      int days = 30,
    }) {
      final range = VitalRanges.defaults[vital]!;
      for (var d = 0; d < days; d++) {
        for (var i = 0; i < perDay; i++) {
          final v = base + (rng.nextDouble() - 0.5) * jitter * 2;
          final s = baseSecondary == null
              ? null
              : baseSecondary + (rng.nextDouble() - 0.5) * jitter;
          final ts =
              now.subtract(Duration(days: d, hours: (i * 12) + rng.nextInt(3)));
          out.add(
            VitalReading(
              id: 'v_${vital.name}_${d}_$i',
              vital: vital,
              value: double.parse(v.toStringAsFixed(1)),
              secondaryValue:
                  s == null ? null : double.parse(s.toStringAsFixed(1)),
              recordedAt: ts,
              risk: range.assess(v),
            ),
          );
        }
      }
    }

    addSeries(
        vital: VitalKey.bloodPressure, base: 118, baseSecondary: 78, jitter: 16);
    addSeries(vital: VitalKey.heartRate, base: 76, jitter: 18);
    addSeries(vital: VitalKey.bloodOxygen, base: 97, jitter: 4, perDay: 1);
    addSeries(vital: VitalKey.bloodGlucose, base: 102, jitter: 30, perDay: 3);

    out.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return out;
  }

  static List<AppNotification> seedNotifications() {
    final now = DateTime.now();
    return [
      AppNotification(
        id: 'n1',
        kind: NotificationKind.vitalAlert,
        title: 'Blood glucose is high',
        body: '168 mg/dL recorded at 8:12 AM — above your target range.',
        createdAt: now.subtract(const Duration(minutes: 14)),
        actionRoute: RouteNames.patientVitalDetail,
        actionArguments: VitalKey.bloodGlucose,
      ),
      AppNotification(
        id: 'n2',
        kind: NotificationKind.appointment,
        title: 'Appointment tomorrow',
        body: 'Dr. Mensah at 3:00 PM — virtual visit.',
        createdAt: now.subtract(const Duration(hours: 3)),
        actionRoute: RouteNames.patientAppointmentDetail,
        actionArguments: 'a1',
      ),
      AppNotification(
        id: 'n3',
        kind: NotificationKind.medication,
        title: 'Time for Metformin',
        body: '500 mg with breakfast.',
        createdAt: now.subtract(const Duration(hours: 6)),
        read: true,
        actionRoute: RouteNames.patientMedications,
      ),
      AppNotification(
        id: 'n4',
        kind: NotificationKind.message,
        title: 'New message from Dr. Mensah',
        body: 'Please share this week\'s glucose readings before our visit.',
        createdAt: now.subtract(const Duration(days: 1)),
        read: true,
        actionRoute: RouteNames.patientChatThread,
        actionArguments: 'c1',
      ),
      AppNotification(
        id: 'n5',
        kind: NotificationKind.vitalAlert,
        title: 'Blood oxygen improved',
        body: 'SpO₂ returned to 97% — alert cleared after new reading.',
        createdAt: now.subtract(const Duration(days: 2)),
        read: true,
        resolved: true,
        resolvedAt: now.subtract(const Duration(days: 1, hours: 6)),
        actionRoute: RouteNames.patientVitalDetail,
        actionArguments: VitalKey.bloodOxygen,
      ),
    ];
  }

  static List<VitalReportRequest> seedVitalReportRequests() {
    final now = DateTime.now();
    return [
      VitalReportRequest(
        id: 'vr_demo_1',
        from: now.subtract(const Duration(days: 45)),
        to: now.subtract(const Duration(days: 15)),
        vitals: const [
          VitalKey.bloodPressure,
          VitalKey.bloodGlucose,
          VitalKey.heartRate,
        ],
        createdAt: now.subtract(const Duration(days: 3)),
        status: VitalReportStatus.pending,
        currentResponder: UserRole.mcareAssistant,
        lastEscalatedAt: now.subtract(const Duration(days: 1)),
        note: 'For cardiology follow-up',
      ),
    ];
  }

  static List<Medication> seedMedications() {
    final now = DateTime.now();
    return [
      Medication(
        id: 'm1',
        name: 'Metformin',
        dosage: '500 mg',
        frequency: 'Twice daily',
        form: 'Tablet',
        instructions: 'Take with food',
        prescribedBy: 'Dr. Kojo Mensah',
        startDate: now.subtract(const Duration(days: 120)),
        refillsLeft: 2,
      ),
      Medication(
        id: 'm2',
        name: 'Lisinopril',
        dosage: '10 mg',
        frequency: 'Once daily',
        form: 'Tablet',
        instructions: 'Take in the morning',
        prescribedBy: 'Dr. Sarah Adeyemi',
        startDate: now.subtract(const Duration(days: 90)),
        refillsLeft: 1,
        expiryDate: now.add(const Duration(days: 10)),
      ),
      Medication(
        id: 'm3',
        name: 'Atorvastatin',
        dosage: '20 mg',
        frequency: 'Once daily at night',
        form: 'Tablet',
        prescribedBy: 'Dr. Sarah Adeyemi',
        startDate: now.subtract(const Duration(days: 60)),
        active: true,
        refillsLeft: 3,
      ),
      Medication(
        id: 'm4',
        name: 'Vitamin D',
        dosage: '1000 IU',
        frequency: 'Once daily',
        form: 'Capsule',
        instructions: 'Take with breakfast',
        prescribedBy: 'Self-reported',
        startDate: now.subtract(const Duration(days: 14)),
        source: MedicationSource.patientAdded,
      ),
    ];
  }

  static List<MedicationDose> seedAllDoses() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime at(int dayOffset, int h, int m) =>
        today.add(Duration(days: dayOffset, hours: h, minutes: m));

    return [
      // Today
      MedicationDose(
        id: 'd1',
        medicationId: 'm1',
        name: 'Metformin',
        dosage: '500 mg',
        scheduledAt: at(0, 8, 0),
        status: DoseStatus.taken,
        takenAt: at(0, 8, 12),
        instructions: 'Take with food',
      ),
      MedicationDose(
        id: 'd2',
        medicationId: 'm2',
        name: 'Lisinopril',
        dosage: '10 mg',
        scheduledAt: at(0, 9, 0),
        status: DoseStatus.taken,
        takenAt: at(0, 9, 5),
      ),
      MedicationDose(
        id: 'd3',
        medicationId: 'm1',
        name: 'Metformin',
        dosage: '500 mg',
        scheduledAt: at(0, 20, 0),
        status: DoseStatus.pending,
        instructions: 'Take with food',
      ),
      MedicationDose(
        id: 'd4',
        medicationId: 'm3',
        name: 'Atorvastatin',
        dosage: '20 mg',
        scheduledAt: at(0, 22, 0),
        status: DoseStatus.pending,
      ),
      // Yesterday
      MedicationDose(
        id: 'd5',
        medicationId: 'm1',
        name: 'Metformin',
        dosage: '500 mg',
        scheduledAt: at(-1, 8, 0),
        status: DoseStatus.taken,
        takenAt: at(-1, 8, 30),
      ),
      MedicationDose(
        id: 'd6',
        medicationId: 'm1',
        name: 'Metformin',
        dosage: '500 mg',
        scheduledAt: at(-1, 20, 0),
        status: DoseStatus.missed,
      ),
    ];
  }

  /// Today's doses only — used by dashboard widgets.
  static List<MedicationDose> seedDosesToday() {
    final now = DateTime.now();
    return seedAllDoses()
        .where((d) =>
            d.scheduledAt.year == now.year &&
            d.scheduledAt.month == now.month &&
            d.scheduledAt.day == now.day)
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  static List<Appointment> seedAppointments() {
    final now = DateTime.now();
    return [
      Appointment(
        id: 'a1',
        doctorId: 'dr_mensah',
        doctorName: 'Dr. Kojo Mensah',
        doctorSpecialty: 'Endocrinology',
        scheduledAt: now.add(const Duration(days: 1, hours: 3)),
        type: AppointmentType.virtual,
        status: AppointmentStatus.confirmed,
        reason: 'Follow-up: glucose management',
        locationOrLink: 'https://meet.mcare.app/visit-a1',
      ),
      Appointment(
        id: 'a2',
        doctorId: 'dr_adeyemi',
        doctorName: 'Dr. Sarah Adeyemi',
        doctorSpecialty: 'Cardiology',
        scheduledAt: now.add(const Duration(days: 6)),
        type: AppointmentType.inPerson,
        status: AppointmentStatus.scheduled,
        reason: 'Annual heart check',
        locationOrLink: 'Nairobi Heart Clinic, Room 4B',
      ),
      Appointment(
        id: 'a3',
        doctorId: 'dr_mensah',
        doctorName: 'Dr. Kojo Mensah',
        doctorSpecialty: 'Endocrinology',
        scheduledAt: now.subtract(const Duration(days: 14)),
        type: AppointmentType.phone,
        status: AppointmentStatus.completed,
        reason: 'Medication review',
      ),
      Appointment(
        id: 'a4',
        doctorId: 'dr_adeyemi',
        doctorName: 'Dr. Sarah Adeyemi',
        doctorSpecialty: 'Cardiology',
        scheduledAt: now.subtract(const Duration(days: 30)),
        type: AppointmentType.inPerson,
        status: AppointmentStatus.cancelled,
        reason: 'Rescheduled check-up',
        cancellationReason: 'Patient requested reschedule',
      ),
    ];
  }

  static List<MedicalDocument> seedDocuments() {
    final now = DateTime.now();
    return [
      MedicalDocument(
        id: 'doc1',
        title: 'HbA1c Lab Result',
        category: DocumentCategory.labResult,
        fileType: DocumentFileType.pdf,
        sizeBytes: 245760,
        uploadedAt: now.subtract(const Duration(days: 5)),
        uploadedBy: 'Amara Okonkwo',
        description: 'Quarterly diabetes panel',
        sharedWithDoctorId: 'dr_mensah',
      ),
      MedicalDocument(
        id: 'doc2',
        title: 'Metformin Prescription',
        category: DocumentCategory.prescription,
        fileType: DocumentFileType.pdf,
        sizeBytes: 98304,
        uploadedAt: now.subtract(const Duration(days: 12)),
        uploadedBy: 'Dr. Kojo Mensah',
      ),
      MedicalDocument(
        id: 'doc3',
        title: 'Chest X-ray report',
        category: DocumentCategory.imaging,
        fileType: DocumentFileType.pdf,
        sizeBytes: 1048576,
        uploadedAt: now.subtract(const Duration(days: 45)),
        uploadedBy: 'Amara Okonkwo',
        description: 'Annual screening',
        sharedWithDoctorId: 'dr_adeyemi',
      ),
      MedicalDocument(
        id: 'doc4',
        title: 'Discharge Summary',
        category: DocumentCategory.discharge,
        fileType: DocumentFileType.pdf,
        sizeBytes: 156672,
        uploadedAt: now.subtract(const Duration(days: 90)),
        uploadedBy: 'Nairobi General Hospital',
      ),
    ];
  }

  static List<Conversation> seedConversations() {
    final now = DateTime.now();
    return [
      Conversation(
        id: 'c1',
        participant: const ChatParticipant(
          id: 'dr_mensah',
          name: 'Dr. Kojo Mensah',
          role: 'doctor',
          specialty: 'Endocrinology',
          avatarColorSeed: 1,
          online: true,
        ),
        lastMessage: ChatMessage(
          id: 'm_last1',
          conversationId: 'c1',
          senderId: 'dr_mensah',
          body: 'Please share this week\'s glucose readings before our visit.',
          sentAt: now.subtract(const Duration(hours: 2)),
        ),
        unreadCount: 1,
      ),
      Conversation(
        id: 'c2',
        participant: const ChatParticipant(
          id: 'dr_adeyemi',
          name: 'Dr. Sarah Adeyemi',
          role: 'doctor',
          specialty: 'Cardiology',
          avatarColorSeed: 2,
        ),
        lastMessage: ChatMessage(
          id: 'm_last2',
          conversationId: 'c2',
          senderId: 'me',
          body: 'Thank you — I\'ll see you next week.',
          sentAt: now.subtract(const Duration(days: 3)),
          read: true,
        ),
        unreadCount: 0,
      ),
    ];
  }

  static Map<String, List<ChatMessage>> seedMessageThreads() {
    final now = DateTime.now();
    return {
      'c1': [
        ChatMessage(
          id: 'm1',
          conversationId: 'c1',
          senderId: 'dr_mensah',
          body: 'Hi Amara, how have your morning readings been this week?',
          sentAt: now.subtract(const Duration(days: 1, hours: 4)),
          read: true,
        ),
        ChatMessage(
          id: 'm2',
          conversationId: 'c1',
          senderId: 'me',
          body: 'Mostly in range except Tuesday morning — 168 mg/dL.',
          sentAt: now.subtract(const Duration(days: 1, hours: 3)),
          read: true,
        ),
        ChatMessage(
          id: 'm3',
          conversationId: 'c1',
          senderId: 'dr_mensah',
          body: 'Please share this week\'s glucose readings before our visit.',
          sentAt: now.subtract(const Duration(hours: 2)),
        ),
      ],
      'c2': [
        ChatMessage(
          id: 'm4',
          conversationId: 'c2',
          senderId: 'dr_adeyemi',
          body: 'Your latest BP trend looks stable. Keep up the good work.',
          sentAt: now.subtract(const Duration(days: 4)),
          read: true,
        ),
        ChatMessage(
          id: 'm5',
          conversationId: 'c2',
          senderId: 'me',
          body: 'Thank you — I\'ll see you next week.',
          sentAt: now.subtract(const Duration(days: 3)),
          read: true,
        ),
      ],
    };
  }

  /// Doctor inbox — participant is the patient.
  static List<Conversation> seedDoctorConversations() {
    final now = DateTime.now();
    return [
      Conversation(
        id: 'dc1',
        participant: const ChatParticipant(
          id: 'p_001',
          name: 'Amara Okonkwo',
          role: 'patient',
          avatarColorSeed: 3,
          online: true,
        ),
        lastMessage: ChatMessage(
          id: 'dm1',
          conversationId: 'dc1',
          senderId: 'p_001',
          body: 'Could you send my 30-day glucose summary?',
          sentAt: now.subtract(const Duration(hours: 5)),
        ),
        unreadCount: 1,
      ),
      Conversation(
        id: 'dc2',
        participant: const ChatParticipant(
          id: 'p_005',
          name: 'Esther Wambui',
          role: 'patient',
          avatarColorSeed: 5,
        ),
        lastMessage: ChatMessage(
          id: 'dm2',
          conversationId: 'dc2',
          senderId: 'me',
          body: 'I\'ll review your BP readings before our visit.',
          sentAt: now.subtract(const Duration(days: 1)),
          read: true,
        ),
        unreadCount: 0,
      ),
    ];
  }

  static Map<String, List<ChatMessage>> seedDoctorMessageThreads() {
    final now = DateTime.now();
    return {
      'dc1': [
        ChatMessage(
          id: 'dm1a',
          conversationId: 'dc1',
          senderId: 'p_001',
          body: 'My morning glucose was 168 mg/dL yesterday.',
          sentAt: now.subtract(const Duration(days: 1)),
          read: true,
        ),
        ChatMessage(
          id: 'dm1b',
          conversationId: 'dc1',
          senderId: 'me',
          body: 'Thanks — I\'ll include that in your report request.',
          sentAt: now.subtract(const Duration(hours: 8)),
          read: true,
        ),
        ChatMessage(
          id: 'dm1',
          conversationId: 'dc1',
          senderId: 'p_001',
          body: 'Could you send my 30-day glucose summary?',
          sentAt: now.subtract(const Duration(hours: 5)),
        ),
      ],
      'dc2': [
        ChatMessage(
          id: 'dm2',
          conversationId: 'dc2',
          senderId: 'me',
          body: 'I\'ll review your BP readings before our visit.',
          sentAt: now.subtract(const Duration(days: 1)),
          read: true,
        ),
      ],
    };
  }

  static List<CareProvider> seedCareProviders() {
    return const [
      CareProvider(
        id: 'dr_mensah',
        name: 'Dr. Kojo Mensah',
        specialty: 'Endocrinology',
        facility: 'Nairobi Diabetes Centre',
        yearsExperience: 12,
        rating: 4.9,
        totalReviews: 128,
        bio: 'Specialises in Type 2 diabetes and metabolic disorders.',
        assigned: true,
      ),
      CareProvider(
        id: 'dr_adeyemi',
        name: 'Dr. Sarah Adeyemi',
        specialty: 'Cardiology',
        facility: 'Nairobi Heart Clinic',
        yearsExperience: 15,
        rating: 4.8,
        totalReviews: 96,
        assigned: true,
      ),
      CareProvider(
        id: 'dr_kimani',
        name: 'Dr. James Kimani',
        specialty: 'General Practice',
        facility: 'Westlands Medical',
        yearsExperience: 8,
        rating: 4.7,
        totalReviews: 54,
        bio: 'Primary care and chronic disease management.',
      ),
      CareProvider(
        id: 'dr_wanjiku',
        name: 'Dr. Grace Wanjiku',
        specialty: 'Nephrology',
        facility: 'City Kidney Institute',
        yearsExperience: 10,
        rating: 4.6,
        totalReviews: 41,
      ),
    ];
  }

  static List<CareRequest> seedCareRequests() {
    return [
      CareRequest(
        id: 'cr1',
        providerId: 'dr_kimani',
        providerName: 'Dr. James Kimani',
        providerSpecialty: 'General Practice',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        status: CareRequestStatus.pending,
        reason: 'Need a primary care provider for routine check-ups',
      ),
    ];
  }

  static List<SupportTicket> seedSupportTickets() {
    final now = DateTime.now();
    return [
      SupportTicket(
        id: 't1',
        subject: 'Cannot upload PDF document',
        description: 'The upload spinner never completes on my phone.',
        category: TicketCategory.technical,
        priority: TicketPriority.normal,
        status: TicketStatus.inProgress,
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(hours: 5)),
        assignedTo: 'Support Team',
        replies: [
          TicketReply(
            id: 'tr1',
            author: 'mCare Support',
            body: 'Thanks for reporting this. Can you tell us your device model?',
            sentAt: now.subtract(const Duration(hours: 5)),
            isStaff: true,
          ),
        ],
      ),
      SupportTicket(
        id: 't2',
        subject: 'Question about glucose targets',
        description: 'What range should I aim for between meals?',
        category: TicketCategory.medical,
        priority: TicketPriority.low,
        status: TicketStatus.resolved,
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now.subtract(const Duration(days: 8)),
        replies: [
          TicketReply(
            id: 'tr2',
            author: 'mCare Support',
            body:
                'Please discuss specific targets with Dr. Mensah — we\'ve flagged this for your care team.',
            sentAt: now.subtract(const Duration(days: 8)),
            isStaff: true,
          ),
        ],
      ),
    ];
  }

  static List<EmergencyContact> seedEmergencyContacts() {
    return const [
      EmergencyContact(
        id: 'ec1',
        name: 'James Okonkwo',
        relationship: 'Spouse',
        phone: '+254 722 111 222',
        email: 'james.o@example.com',
        priority: 1,
      ),
      EmergencyContact(
        id: 'ec2',
        name: 'Chioma Okonkwo',
        relationship: 'Sister',
        phone: '+254 733 333 444',
        priority: 2,
      ),
    ];
  }

  static List<SosEvent> seedSosHistory() {
    return [
      SosEvent(
        id: 'sos1',
        kind: EmergencyKind.fall,
        triggeredAt: DateTime.now().subtract(const Duration(days: 120)),
        status: SosStatus.resolved,
        locationLabel: 'Home — Westlands, Nairobi',
        respondedBy: 'Dr. Adeyemi (care team)',
      ),
    ];
  }

  static PatientHealthProfile seedHealthProfile() {
    return PatientHealthProfile(
      bloodType: BloodType.oPos,
      gender: Gender.female,
      dateOfBirth: DateTime(1988, 3, 15),
      heightCm: 165,
      weightKg: 68,
      allergies: const ['Penicillin'],
      chronicConditions: const ['Type 2 Diabetes', 'Hypertension'],
      currentMedications: const ['Metformin', 'Lisinopril', 'Atorvastatin'],
      address: 'Westlands, Nairobi, Kenya',
      locationConsent: true,
      noKnownAllergies: false,
      noCurrentMedications: false,
    );
  }
}
