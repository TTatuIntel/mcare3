import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api/auth_api.dart';
import '../core/api/external_access_api.dart';
import '../core/env/app_env.dart';
import '../shared/auth/auth_state.dart';
import '../shared/constants/route_names.dart';
import '../shared/models/document.dart';
import '../shared/theme/app_colors.dart';
import '../shared/theme/app_spacing.dart';
import '../shared/widgets/app_loading_view.dart';
import '../shared/widgets/app_button.dart';
import '../shared/widgets/app_icons.dart';
import '../shared/widgets/app_toast.dart';
import '../shared/widgets/bubble_background.dart';
import '../shared/widgets/empty_state.dart';
import '../shared/widgets/glass_card.dart';
import '../shared/widgets/pre_login_top_bar.dart';
import '../shared/widgets/staff_blocks.dart';

/// Token-scoped external-doctor portal.
/// Route: `/external` (with optional `?token=...`).
///
/// Outside clinicians can review the patient chart and:
/// - record vitals
/// - assign medications
/// - upload documents / reports
/// - submit a consultation note
class ExternalDoctorView extends StatefulWidget {
  const ExternalDoctorView({super.key, this.token});
  final String? token;

  @override
  State<ExternalDoctorView> createState() => _ExternalDoctorViewState();
}

class _ExternalDoctorViewState extends State<ExternalDoctorView> {
  final _note = TextEditingController();
  final _code = TextEditingController();
  final _doctorName = TextEditingController();
  final _vitalValue = TextEditingController();
  final _vitalSecondary = TextEditingController();
  final _medName = TextEditingController();
  final _medDosage = TextEditingController();
  final _medFrequency = TextEditingController();
  final _medInstructions = TextEditingController();
  final _docTitle = TextEditingController();
  final _docDescription = TextEditingController();

  Map<String, dynamic>? _portal;
  bool _loading = true;
  bool _resolvingCode = false;
  bool _savingVital = false;
  bool _savingMed = false;
  bool _savingDoc = false;
  String? _error;
  String? _token;
  String? _selectedVitalKey;
  DocumentCategory _docCategory = DocumentCategory.consultationNote;
  PlatformFile? _pickedFile;
  String? _pickedFileName;

  @override
  void initState() {
    super.initState();
    _token = widget.token;
    _loadPortal();
  }

  Future<void> _loadPortal() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _error = null;
      });
      return;
    }
    try {
      if (AppEnv.backendEnabled) {
        final data = await AuthApi.instance.externalPortal(token);
        if (!mounted) return;
        setState(() {
          _portal = data;
          _loading = false;
          _error = data == null ? 'Invalid or expired link.' : null;
        });
        return;
      }
      setState(() {
        _portal = _demoPortal(token);
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load consultation portal.';
        });
      }
    }
  }

  Future<void> _resolveCode() async {
    final code = _code.text.trim();
    if (code.length < 6) {
      AppToast.warn(context, 'Enter the full access code.');
      return;
    }
    setState(() => _resolvingCode = true);
    try {
      final token = await ExternalAccessApi.instance.resolveCode(code);
      if (!mounted) return;
      if (token == null || token.isEmpty) {
        AppToast.error(context, 'This access code is invalid or has expired.');
        setState(() => _resolvingCode = false);
        return;
      }
      setState(() {
        _token = token;
        _loading = true;
        _resolvingCode = false;
      });
      await _loadPortal();
    } catch (_) {
      if (mounted) {
        setState(() => _resolvingCode = false);
        AppToast.error(context, 'This access code is invalid or has expired.');
      }
    }
  }

  Future<void> _recordVital() async {
    final token = _token;
    final key = _selectedVitalKey;
    final value = double.tryParse(_vitalValue.text.trim());
    if (token == null || key == null) {
      AppToast.warn(context, 'Choose which vital you are recording.');
      return;
    }
    if (value == null) {
      AppToast.warn(context, 'Enter a numeric value.');
      return;
    }
    setState(() => _savingVital = true);
    try {
      if (AppEnv.backendEnabled) {
        await ExternalAccessApi.instance.recordVital(
          token,
          vitalKey: key,
          value: value,
          secondaryValue: double.tryParse(_vitalSecondary.text.trim()),
          doctorName: _doctorName.text.trim(),
        );
      }
      if (!mounted) return;
      _vitalValue.clear();
      _vitalSecondary.clear();
      AppToast.success(
          context, 'Vital recorded — the care team has been alerted.');
      await _loadPortal();
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not record the vital.');
    } finally {
      if (mounted) setState(() => _savingVital = false);
    }
  }

  Future<void> _assignMedication() async {
    final token = _token;
    final name = _medName.text.trim();
    final dosage = _medDosage.text.trim();
    final frequency = _medFrequency.text.trim();
    if (token == null) return;
    if (name.isEmpty || dosage.isEmpty || frequency.isEmpty) {
      AppToast.warn(context, 'Name, dosage, and frequency are required.');
      return;
    }
    setState(() => _savingMed = true);
    try {
      if (AppEnv.backendEnabled) {
        await ExternalAccessApi.instance.assignMedication(
          token,
          name: name,
          dosage: dosage,
          frequency: frequency,
          instructions: _medInstructions.text.trim(),
          doctorName: _doctorName.text.trim(),
        );
      }
      if (!mounted) return;
      _medName.clear();
      _medDosage.clear();
      _medFrequency.clear();
      _medInstructions.clear();
      AppToast.success(context, 'Medication assigned to the patient chart.');
      await _loadPortal();
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not assign the medication.');
    } finally {
      if (mounted) setState(() => _savingMed = false);
    }
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    setState(() {
      _pickedFile = file;
      _pickedFileName = file.name;
      if (_docTitle.text.trim().isEmpty) {
        final nameWithoutExt = file.name.contains('.')
            ? file.name.substring(0, file.name.lastIndexOf('.'))
            : file.name;
        _docTitle.text = nameWithoutExt;
      }
    });
  }

  Future<void> _uploadDocument() async {
    final token = _token;
    final file = _pickedFile;
    final title = _docTitle.text.trim();
    if (token == null) return;
    if (title.isEmpty) {
      AppToast.warn(context, 'Enter a document title.');
      return;
    }
    if (file == null) {
      AppToast.warn(context, 'Choose a file to upload.');
      return;
    }
    final ext = (file.extension ?? '').toLowerCase();
    final fileType = switch (ext) {
      'pdf' => 'pdf',
      'jpg' || 'jpeg' || 'png' => 'image',
      'doc' || 'docx' => 'doc',
      _ => 'other',
    };
    setState(() => _savingDoc = true);
    try {
      if (AppEnv.backendEnabled) {
        await ExternalAccessApi.instance.uploadDocument(
          token,
          file: file,
          title: title,
          category: _docCategory.name,
          fileType: fileType,
          description: _docDescription.text.trim(),
          doctorName: _doctorName.text.trim(),
        );
      }
      if (!mounted) return;
      _docTitle.clear();
      _docDescription.clear();
      setState(() {
        _pickedFile = null;
        _pickedFileName = null;
      });
      AppToast.success(context, 'Document uploaded to the patient chart.');
      await _loadPortal();
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not upload the document.');
    } finally {
      if (mounted) setState(() => _savingDoc = false);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    _code.dispose();
    _doctorName.dispose();
    _vitalValue.dispose();
    _vitalSecondary.dispose();
    _medName.dispose();
    _medDosage.dispose();
    _medFrequency.dispose();
    _medInstructions.dispose();
    _docTitle.dispose();
    _docDescription.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = AppPalette.scaffoldBg(context);
    final patientData =
        (_portal?['patient'] as Map?)?.cast<String, dynamic>();
    final patientName = patientData?['name'] as String?;
    final allergies = ((patientData?['allergies'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
    final expiresRaw = _portal?['expires_at'] as String?;
    final expires = expiresRaw != null
        ? DateTime.tryParse(expiresRaw) ??
            DateTime.now().add(const Duration(hours: 23))
        : DateTime.now().add(const Duration(hours: 23));
    return Scaffold(
      backgroundColor: surface,
      body: BubbleBackground(
        surfaceColor: surface,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PreLoginTopBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GlassCard(
                            frosted: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      height: 40,
                                      width: 40,
                                      decoration: BoxDecoration(
                                        color: AppColors.info.withOpacity(0.14),
                                        borderRadius: BorderRadius.circular(
                                            AppSpacing.radiusMd),
                                      ),
                                      child: Icon(AppIcons.link,
                                          color: AppColors.info),
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'External consultation portal',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          Text(
                                            'Token expires ${DateFormat.MMMd().add_jm().format(expires)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                    color: AppColors
                                                        .textMutedAA),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  _token == null
                                      ? 'Open the link you were given, or enter the patient\'s access code below.'
                                      : 'Access scoped to one patient session. Review the record, record vitals, assign medication, and upload reports.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          if (_token == null)
                            GlassCard(
                              frosted: true,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text('Enter access code',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    'Ask the patient for their 8-character '
                                    'emergency access code (e.g. AB2D-9XKM).',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  TextField(
                                    controller: _code,
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    decoration: const InputDecoration(
                                      hintText: 'XXXX-XXXX',
                                    ),
                                    onSubmitted: (_) => _resolveCode(),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  AppButton(
                                    label: 'Open patient record',
                                    icon: AppIcons.link,
                                    loading: _resolvingCode,
                                    onPressed: _resolveCode,
                                  ),
                                ],
                              ),
                            )
                          else if (_loading)
                            const AppLoadingView(itemCount: 3)
                          else if (_error != null)
                            GlassCard(
                              frosted: true,
                              child: EmptyStateView(
                                icon: AppIcons.link,
                                title: 'Portal unavailable',
                                message: _error!,
                                compact: true,
                              ),
                            )
                          else if (patientName == null)
                            GlassCard(
                              frosted: true,
                              child: EmptyStateView(
                                icon: AppIcons.user,
                                title: 'No patient context',
                                message:
                                    'The token did not match an active consultation session.',
                                compact: true,
                              ),
                            )
                          else ...[
                            GlassCard(
                              frosted: true,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Patient summary',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(patientName),
                                  if (patientData?['condition'] != null &&
                                      (patientData!['condition'] as String)
                                          .isNotEmpty)
                                    Text(
                                      patientData['condition'] as String,
                                      style: TextStyle(
                                          color: AppPalette.textMuted(context)),
                                    ),
                                  if (patientData?['blood_type'] != null)
                                    Text(
                                      'Blood type: ${patientData!['blood_type']}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    allergies.isEmpty
                                        ? (patientData?['no_known_allergies'] ==
                                                true
                                            ? 'Allergies: none known'
                                            : 'Allergies: not recorded')
                                        : 'Allergies: ${allergies.join(', ')}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: allergies.isEmpty
                                              ? AppPalette.textMuted(context)
                                              : AppColors.critical,
                                          fontWeight: allergies.isEmpty
                                              ? FontWeight.w400
                                              : FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            GlassCard(
                              frosted: true,
                              child: TextField(
                                controller: _doctorName,
                                decoration: const InputDecoration(
                                  labelText: 'Your name (Dr. …)',
                                  hintText:
                                      'Shown on notes, vitals, meds, and uploads',
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            StaffListCard(
                              title: 'Recent vitals',
                              children:
                                  ((_portal?['vitals'] as List?) ?? const [])
                                      .take(5)
                                      .map(
                                (raw) {
                                  final v =
                                      (raw as Map).cast<String, dynamic>();
                                  return StaffListRow(
                                    icon: AppIcons.vitals,
                                    title:
                                        (v['vital'] ?? 'Vital') as String,
                                    subtitle: (v['display_value'] ??
                                            v['value'] ??
                                            '')
                                        .toString(),
                                    pill: (v['risk'] ?? '') as String,
                                  );
                                },
                              ).toList(),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            StaffListCard(
                              title: 'Active medications',
                              children: ((_portal?['medications'] as List?) ??
                                      const [])
                                  .take(8)
                                  .map(
                                (raw) {
                                  final m =
                                      (raw as Map).cast<String, dynamic>();
                                  return StaffListRow(
                                    icon: AppIcons.medication,
                                    title: (m['name'] ?? 'Medication')
                                        as String,
                                    subtitle:
                                        '${m['dosage'] ?? ''} · ${m['frequency'] ?? ''}',
                                    pill: (m['prescribed_by'] ?? '') as String,
                                  );
                                },
                              ).toList(),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            StaffListCard(
                              title: 'Recent documents',
                              children: ((_portal?['documents'] as List?) ??
                                      const [])
                                  .take(6)
                                  .map(
                                (raw) {
                                  final d =
                                      (raw as Map).cast<String, dynamic>();
                                  return StaffListRow(
                                    icon: AppIcons.document,
                                    title:
                                        (d['title'] ?? 'Document') as String,
                                    subtitle:
                                        (d['category'] ?? d['uploaded_by'] ?? '')
                                            .toString(),
                                  );
                                },
                              ).toList(),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _RecordFindingsCard(
                              catalog:
                                  ((_portal?['catalog'] as List?) ?? const [])
                                      .map((e) =>
                                          (e as Map).cast<String, dynamic>())
                                      .toList(),
                              selectedKey: _selectedVitalKey,
                              onKeyChanged: (k) =>
                                  setState(() => _selectedVitalKey = k),
                              value: _vitalValue,
                              secondaryValue: _vitalSecondary,
                              saving: _savingVital,
                              onSubmit: _recordVital,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _AssignMedicationCard(
                              name: _medName,
                              dosage: _medDosage,
                              frequency: _medFrequency,
                              instructions: _medInstructions,
                              saving: _savingMed,
                              onSubmit: _assignMedication,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _UploadDocumentCard(
                              title: _docTitle,
                              description: _docDescription,
                              category: _docCategory,
                              onCategoryChanged: (c) =>
                                  setState(() => _docCategory = c),
                              fileName: _pickedFileName,
                              onPick: _pickDocument,
                              saving: _savingDoc,
                              onSubmit: _uploadDocument,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            GlassCard(
                              frosted: true,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text('Consultation note',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: AppSpacing.sm),
                                  TextField(
                                    controller: _note,
                                    maxLines: 6,
                                    minLines: 4,
                                    decoration: const InputDecoration(
                                      hintText:
                                          'Findings, recommendations, follow-up plan…',
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  AppButton(
                                    label: 'Submit note',
                                    icon: AppIcons.send,
                                    onPressed: () async {
                                      if (_note.text.trim().isEmpty) {
                                        AppToast.warn(context,
                                            'Add a note before submitting.');
                                        return;
                                      }
                                      final token = _token;
                                      if (token != null &&
                                          AppEnv.backendEnabled) {
                                        try {
                                          await AuthApi.instance.externalNote(
                                            token,
                                            note: _note.text.trim(),
                                            doctorName:
                                                _doctorName.text.trim(),
                                          );
                                        } catch (_) {
                                          if (context.mounted) {
                                            AppToast.error(context,
                                                'Could not submit note.');
                                          }
                                          return;
                                        }
                                      }
                                      _note.clear();
                                      if (context.mounted) {
                                        AppToast.success(context,
                                            'Note submitted to the care team.');
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          Center(
                            child: TextButton(
                              onPressed: () {
                                AuthState.instance.signOut();
                                Navigator.of(context).pushNamedAndRemoveUntil(
                                  RouteNames.home,
                                  (_) => false,
                                );
                              },
                              child: const Text('End session'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Map<String, dynamic> _demoPortal(String token) => {
        'patient': {
          'name': 'Amara Okonkwo',
          'unique_id': 'MCR-10042',
          'age': 34,
          'conditions': ['Type 2 diabetes', 'Hypertension'],
          'condition': 'Type 2 diabetes · Hypertension',
          'allergies': ['Penicillin'],
          'blood_type': 'O+',
        },
        'summary':
            'External consult link (demo). Token: ${token.substring(0, token.length.clamp(0, 8))}…',
        'vitals': [
          {
            'vital': 'Blood glucose',
            'display_value': '142 mg/dL',
            'risk': 'elevated'
          },
          {
            'vital': 'Blood pressure',
            'display_value': '138/86 mmHg',
            'risk': 'elevated'
          },
        ],
        'medications': [
          {
            'name': 'Metformin',
            'dosage': '500 mg',
            'frequency': 'Twice daily',
            'prescribed_by': 'Dr. Mensah',
          },
        ],
        'documents': [
          {
            'title': 'Latest HbA1c lab',
            'category': 'labResult',
            'uploaded_by': 'Care team',
          },
        ],
        'catalog': [
          {
            'vital_key': 'bloodPressure',
            'label': 'Blood pressure',
            'unit': 'mmHg'
          },
          {
            'vital_key': 'bloodGlucose',
            'label': 'Blood glucose',
            'unit': 'mg/dL'
          },
          {'vital_key': 'heartRate', 'label': 'Heart rate', 'unit': 'bpm'},
        ],
        'notes': const <Map<String, dynamic>>[],
      };
}

class _RecordFindingsCard extends StatelessWidget {
  const _RecordFindingsCard({
    required this.catalog,
    required this.selectedKey,
    required this.onKeyChanged,
    required this.value,
    required this.secondaryValue,
    required this.saving,
    required this.onSubmit,
  });

  final List<Map<String, dynamic>> catalog;
  final String? selectedKey;
  final ValueChanged<String?> onKeyChanged;
  final TextEditingController value;
  final TextEditingController secondaryValue;
  final bool saving;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBp = selectedKey == 'bloodPressure';
    String unitFor(String? key) {
      for (final v in catalog) {
        if (v['vital_key'] == key) return (v['unit'] ?? '') as String;
      }
      return '';
    }

    return GlassCard(
      frosted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Record vitals', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Readings you record are added to the patient\'s chart and '
            'trigger real-time alerts to their care team when out of range.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppPalette.textMuted(context)),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: selectedKey,
            decoration: const InputDecoration(labelText: 'Vital'),
            items: [
              for (final v in catalog)
                DropdownMenuItem(
                  value: v['vital_key'] as String,
                  child: Text('${v['label']}'
                      '${(v['unit'] as String? ?? '').isNotEmpty ? ' (${v['unit']})' : ''}'),
                ),
            ],
            onChanged: onKeyChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: value,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: isBp ? 'Systolic' : 'Value',
                    suffixText: unitFor(selectedKey),
                  ),
                ),
              ),
              if (isBp) ...[
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    controller: secondaryValue,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Diastolic'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Record vital',
            icon: AppIcons.vitals,
            loading: saving,
            onPressed: onSubmit,
          ),
        ],
      ),
    );
  }
}

class _AssignMedicationCard extends StatelessWidget {
  const _AssignMedicationCard({
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.instructions,
    required this.saving,
    required this.onSubmit,
  });

  final TextEditingController name;
  final TextEditingController dosage;
  final TextEditingController frequency;
  final TextEditingController instructions;
  final bool saving;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      frosted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Assign medication', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Adds an active prescription to the patient chart and notifies them.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppPalette.textMuted(context)),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Medication name'),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: dosage,
                  decoration: const InputDecoration(labelText: 'Dosage'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  controller: frequency,
                  decoration: const InputDecoration(labelText: 'Frequency'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: instructions,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: 'Instructions (optional)',
              hintText: 'Take with food, avoid alcohol…',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Assign medication',
            icon: AppIcons.medication,
            loading: saving,
            onPressed: onSubmit,
          ),
        ],
      ),
    );
  }
}

class _UploadDocumentCard extends StatelessWidget {
  const _UploadDocumentCard({
    required this.title,
    required this.description,
    required this.category,
    required this.onCategoryChanged,
    required this.fileName,
    required this.onPick,
    required this.saving,
    required this.onSubmit,
  });

  final TextEditingController title;
  final TextEditingController description;
  final DocumentCategory category;
  final ValueChanged<DocumentCategory> onCategoryChanged;
  final String? fileName;
  final VoidCallback onPick;
  final bool saving;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      frosted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Upload document / report', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Lab results, imaging, discharge summaries, and consultation reports.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppPalette.textMuted(context)),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<DocumentCategory>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in DocumentCategory.values)
                DropdownMenuItem(
                  value: c,
                  child: Text(_categoryLabel(c)),
                ),
            ],
            onChanged: (v) {
              if (v != null) onCategoryChanged(v);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: description,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(AppIcons.upload),
            label: Text(fileName ?? 'Choose PDF, image, or Word file'),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Upload document',
            icon: AppIcons.document,
            loading: saving,
            onPressed: onSubmit,
          ),
        ],
      ),
    );
  }

  static String _categoryLabel(DocumentCategory c) => switch (c) {
        DocumentCategory.labResult => 'Lab result',
        DocumentCategory.prescription => 'Prescription',
        DocumentCategory.imaging => 'Imaging',
        DocumentCategory.discharge => 'Discharge summary',
        DocumentCategory.consultationNote => 'Consultation note',
        DocumentCategory.other => 'Other',
      };
}
