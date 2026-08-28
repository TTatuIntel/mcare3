import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api/auth_api.dart';
import '../core/api/external_access_api.dart';
import '../core/env/app_env.dart';
import '../core/realtime/external_realtime_channel.dart';
import '../shared/constants/route_names.dart';
import '../shared/models/document.dart';
import '../shared/theme/app_colors.dart';
import '../shared/theme/app_spacing.dart';
import '../shared/widgets/app_button.dart';
import '../shared/widgets/app_icons.dart';
import '../shared/widgets/app_loading_view.dart';
import '../shared/widgets/app_toast.dart';
import '../shared/widgets/bubble_background.dart';
import '../shared/widgets/pre_login_top_bar.dart';
import 'external/external_portal_widgets.dart';

/// Token-scoped, one-patient guest workspace.
///
/// This is intentionally not an external-doctor account or caseload. The
/// patient-created link/code remains the authority for every read and write.
class ExternalDoctorView extends StatefulWidget {
  const ExternalDoctorView({super.key, this.token});

  final String? token;

  @override
  State<ExternalDoctorView> createState() => _ExternalDoctorViewState();
}

enum _RecordSection { summary, vitals, medications, documents }

enum _Finding { vital, note, medication, document }

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
  bool _savingNote = false;
  bool _savingMed = false;
  bool _savingDoc = false;
  String? _error;
  String? _token;
  String? _selectedVitalKey;
  DocumentCategory _docCategory = DocumentCategory.consultationNote;
  PlatformFile? _pickedFile;
  String? _pickedFileName;
  _RecordSection _section = _RecordSection.summary;
  _Finding? _finding;
  final ExternalRealtimeChannel _realtime = ExternalRealtimeChannel();
  Timer? _refreshTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _token = widget.token;
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_token != null && !_loading) _loadPortal();
    });
    _loadPortal();
  }

  Future<void> _loadPortal() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _portal = null;
      });
      return;
    }
    if (_refreshing) return;
    _refreshing = true;
    try {
      if (!AppEnv.backendEnabled && !AppEnv.demoDataEnabled) {
        throw StateError('External clinical access requires the mCare API.');
      }
      final data = AppEnv.backendEnabled
          ? await AuthApi.instance.externalPortal(token)
          : _demoPortal(token);
      if (!mounted) return;
      setState(() {
        _portal = data;
        _loading = false;
        _error = data == null
            ? 'This shared access is no longer available.'
            : null;
      });
      final channel = data?['realtime_channel'] as String?;
      if (channel != null && channel.isNotEmpty) {
        await _realtime.attach(
          token: token,
          channelName: channel,
          onChanged: () => unawaited(_loadPortal()),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _portal = null;
        _loading = false;
        _error = 'This shared access is no longer available.';
      });
      _realtime.detach();
    } finally {
      _refreshing = false;
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
        setState(() => _resolvingCode = false);
        AppToast.error(context, 'This shared access is no longer available.');
        return;
      }
      setState(() {
        _token = token;
        _loading = true;
        _resolvingCode = false;
        _error = null;
      });
      await _loadPortal();
    } catch (_) {
      if (!mounted) return;
      setState(() => _resolvingCode = false);
      AppToast.error(
        context,
        'Could not open the shared record. Check your connection or code.',
      );
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
      AppToast.success(context, 'Vital added to the patient chart.');
      setState(() {
        _finding = null;
        _section = _RecordSection.vitals;
      });
      await _loadPortal();
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not record the vital.');
    } finally {
      if (mounted) setState(() => _savingVital = false);
    }
  }

  Future<void> _submitNote() async {
    final note = _note.text.trim();
    final token = _token;
    if (note.length < 4) {
      AppToast.warn(context, 'Add at least 4 characters before submitting.');
      return;
    }
    if (token == null) return;
    setState(() => _savingNote = true);
    try {
      if (AppEnv.backendEnabled) {
        await AuthApi.instance.externalNote(
          token,
          note: note,
          doctorName: _doctorName.text.trim(),
        );
      }
      if (!mounted) return;
      _note.clear();
      setState(() => _finding = null);
      AppToast.success(
        context,
        'Consultation note added to the patient chart activity.',
      );
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not submit the note.');
    } finally {
      if (mounted) setState(() => _savingNote = false);
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
      AppToast.success(context, 'Medication added to the patient chart.');
      setState(() {
        _finding = null;
        _section = _RecordSection.medications;
      });
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
        _docTitle.text = file.name.contains('.')
            ? file.name.substring(0, file.name.lastIndexOf('.'))
            : file.name;
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
        _finding = null;
        _section = _RecordSection.documents;
      });
      AppToast.success(context, 'Document uploaded to the patient chart.');
      await _loadPortal();
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not upload the document.');
    } finally {
      if (mounted) setState(() => _savingDoc = false);
    }
  }

  void _useAnotherCode() {
    _realtime.detach();
    setState(() {
      _token = null;
      _portal = null;
      _error = null;
      _loading = false;
      _finding = null;
      _section = _RecordSection.summary;
    });
    _code.clear();
  }

  void _endViewing() {
    _realtime.detach();
    _portal = null;
    _token = null;
    _pickedFile = null;
    _pickedFileName = null;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(RouteNames.home, (_) => false);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _realtime.detach();
    for (final controller in [
      _note,
      _code,
      _doctorName,
      _vitalValue,
      _vitalSecondary,
      _medName,
      _medDosage,
      _medFrequency,
      _medInstructions,
      _docTitle,
      _docDescription,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = AppPalette.scaffoldBg(context);
    return Scaffold(
      backgroundColor: surface,
      body: BubbleBackground(
        surfaceColor: surface,
        child: SafeArea(
          child: _token == null
              ? _buildAccessGate(context)
              : _loading
              ? const Column(
                  children: [
                    PreLoginTopBar(),
                    Expanded(child: AppLoadingView(itemCount: 4)),
                  ],
                )
              : _error != null || _patient == null
              ? _buildAccessEnded(context)
              : _buildWorkspace(context),
        ),
      ),
    );
  }

  Map<String, dynamic>? get _patient =>
      (_portal?['patient'] as Map?)?.cast<String, dynamic>();

  DateTime get _expiresAt {
    final raw = _portal?['expires_at'] as String?;
    return raw == null
        ? DateTime.now()
        : DateTime.tryParse(raw) ?? DateTime.now();
  }

  Widget _buildAccessGate(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const PreLoginTopBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: ExternalSurface(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.info.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusLg,
                              ),
                            ),
                            child: const Icon(
                              AppIcons.link,
                              color: AppColors.info,
                              size: 30,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'External clinical access',
                          style: theme.textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Open the one-patient record shared with you. '
                          'Access ends automatically at the patient-selected expiry.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppPalette.textMuted(context),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _BoundaryLine(
                          icon: AppIcons.user,
                          text: 'Limited to one patient record',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _BoundaryLine(
                          icon: AppIcons.time,
                          text: 'Time-limited and patient-controlled',
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          'Enter the access code',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Ask the patient for the code shown with their shared link.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppPalette.textMuted(context),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _code,
                          enabled: !_resolvingCode,
                          textCapitalization: TextCapitalization.characters,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            letterSpacing: 4,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'XXXX-XXXX',
                            labelText: 'Patient access code',
                          ),
                          autofillHints: const [AutofillHints.oneTimeCode],
                          onSubmitted: (_) => _resolveCode(),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AppButton(
                          label: 'Open shared record',
                          icon: AppIcons.link,
                          loading: _resolvingCode,
                          expand: true,
                          onPressed: _resolveCode,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Only use a link or code the patient gave you. '
                          'Do not save or forward it.',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppPalette.textMuted(context),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAccessEnded(BuildContext context) {
    return Column(
      children: [
        const PreLoginTopBar(),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ExternalSurface(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppPalette.warningSoft(context),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusLg,
                          ),
                        ),
                        child: const Icon(
                          AppIcons.lock,
                          color: AppColors.warning,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Shared access unavailable',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error ?? 'This shared access is no longer available.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppPalette.textMuted(context),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'It may have expired or been revoked. Ask the patient '
                        'for a new link or code when appropriate.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppPalette.textMuted(context),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AppButton(
                        label: 'Enter another code',
                        icon: AppIcons.link,
                        expand: true,
                        onPressed: _useAnotherCode,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppButton(
                        label: 'Return to mCare home',
                        variant: AppButtonVariant.ghost,
                        expand: true,
                        onPressed: _endViewing,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final expanded = constraints.maxWidth >= 1080;
        final medium = constraints.maxWidth >= 720;
        final maxWidth = expanded ? 1440.0 : 980.0;
        return Column(
          children: [
            _WorkspaceHeader(
              expiresAt: _expiresAt,
              patientName: (_patient?['name'] ?? 'Shared patient').toString(),
              onEnd: _endViewing,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(
                  constraints.maxWidth < 600 ? AppSpacing.md : AppSpacing.lg,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: expanded
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 250,
                                child: _patientPanel(context),
                              ),
                              const SizedBox(width: AppSpacing.lg),
                              Expanded(child: _mainPanel(context)),
                              const SizedBox(width: AppSpacing.lg),
                              SizedBox(
                                width: 244,
                                child: _actionPanel(context),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (medium)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 250,
                                      child: _patientPanel(context),
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(child: _compactControls(context)),
                                  ],
                                )
                              else ...[
                                _patientPanel(context),
                                const SizedBox(height: AppSpacing.md),
                                _compactControls(context),
                              ],
                              const SizedBox(height: AppSpacing.md),
                              _mainPanel(context, showNavigation: false),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _patientPanel(BuildContext context) {
    final patient = _patient!;
    final allergies = ((patient['allergies'] as List?) ?? const [])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList();
    final explicitNone = patient['no_known_allergies'] == true;
    final details = <String>[
      if ((patient['unique_id'] ?? '').toString().isNotEmpty)
        patient['unique_id'].toString(),
      if (patient['age'] != null) '${patient['age']} years',
      if ((patient['sex'] ?? '').toString().isNotEmpty)
        patient['sex'].toString(),
      if ((patient['blood_type'] ?? '').toString().isNotEmpty)
        'Blood ${patient['blood_type']}',
    ];
    final conditions = _conditionText(patient);
    return ExternalSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Text(
              _initials((patient['name'] ?? 'Patient').toString()),
              style: const TextStyle(
                color: AppColors.info,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            (patient['name'] ?? 'Shared patient').toString(),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              details.join(' · '),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text('Allergies', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          ExternalStatusChip(
            label: allergies.isNotEmpty
                ? allergies.join(', ')
                : explicitNone
                ? 'No known allergies'
                : 'Not recorded',
            icon: allergies.isNotEmpty ? AppIcons.alert : AppIcons.info,
            color: allergies.isNotEmpty ? AppColors.critical : AppColors.info,
          ),
          if (conditions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text('Conditions', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              conditions,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Divider(color: AppPalette.border(context)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(AppIcons.lock, size: 16, color: AppColors.info),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'This access is limited to this patient.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _conditionText(Map<String, dynamic> patient) {
    final condition = (patient['condition'] ?? '').toString().trim();
    if (condition.isNotEmpty) return condition;
    return ((patient['conditions'] as List?) ?? const [])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .join(' · ');
  }

  Widget _compactControls(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _recordNavigation(context),
        const SizedBox(height: AppSpacing.md),
        _actionPanel(context),
      ],
    );
  }

  Widget _recordNavigation(BuildContext context) {
    return ExternalSurface(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final section in _RecordSection.values)
            ChoiceChip(
              selected: _section == section && _finding == null,
              label: Text(_sectionLabel(section)),
              onSelected: (_) {
                setState(() {
                  _section = section;
                  _finding = null;
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _actionPanel(BuildContext context) {
    final actions = <(_Finding, IconData, String)>[
      (_Finding.vital, AppIcons.vitals, 'Record vital'),
      (_Finding.note, AppIcons.edit, 'Consultation note'),
      (_Finding.medication, AppIcons.medication, 'Assign medication'),
      (_Finding.document, AppIcons.upload, 'Upload document'),
    ];
    return ExternalSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a finding', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Choose an action for this shared record.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (var index = 0; index < actions.length; index++) ...[
            AppButton(
              label: actions[index].$3,
              icon: actions[index].$2,
              variant: _finding == actions[index].$1
                  ? AppButtonVariant.primary
                  : AppButtonVariant.secondary,
              expand: true,
              onPressed: () => setState(() => _finding = actions[index].$1),
            ),
            if (index < actions.length - 1)
              const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  Widget _mainPanel(BuildContext context, {bool showNavigation = true}) {
    if (_finding != null) return _findingPanel(context, _finding!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showNavigation) ...[
          _recordNavigation(context),
          const SizedBox(height: AppSpacing.md),
        ],
        ExternalSurface(child: _sectionPanel(context)),
      ],
    );
  }

  Widget _sectionPanel(BuildContext context) => switch (_section) {
    _RecordSection.summary => _summarySection(context),
    _RecordSection.vitals => _vitalsSection(context),
    _RecordSection.medications => _medicationsSection(context),
    _RecordSection.documents => _documentsSection(context),
  };

  Widget _summarySection(BuildContext context) {
    final vitals = _maps(_portal?['vitals']);
    final medications = _maps(_portal?['medications']);
    final documents = _maps(_portal?['documents']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ExternalSectionHeading(
          title: 'Patient summary',
          description: 'Recent information shared for this consultation.',
        ),
        const SizedBox(height: AppSpacing.lg),
        _PreviewGroup(
          title: 'Recent vitals',
          empty: 'No vital readings were shared.',
          children: vitals.take(3).map(_vitalTile).toList(),
          onViewAll: () => setState(() => _section = _RecordSection.vitals),
        ),
        const SizedBox(height: AppSpacing.lg),
        _PreviewGroup(
          title: 'Active medications',
          empty: 'No active medications were shared.',
          children: medications.take(3).map(_medicationTile).toList(),
          onViewAll: () =>
              setState(() => _section = _RecordSection.medications),
        ),
        const SizedBox(height: AppSpacing.lg),
        _PreviewGroup(
          title: 'Recent documents',
          empty: 'No document metadata was shared.',
          children: documents.take(3).map(_documentTile).toList(),
          onViewAll: () => setState(() => _section = _RecordSection.documents),
        ),
      ],
    );
  }

  Widget _vitalsSection(BuildContext context) {
    final items = _maps(_portal?['vitals']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExternalSectionHeading(
          title: 'Vitals',
          description: 'Newest shared readings first.',
          trailing: AppButton(
            label: 'Record vital',
            icon: AppIcons.add,
            size: AppButtonSize.sm,
            onPressed: () => setState(() => _finding = _Finding.vital),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (items.isEmpty)
          const ExternalEmptyPanel(
            icon: AppIcons.vitals,
            title: 'No shared vital readings',
            message: 'A new reading can be added using Record vital.',
          )
        else
          ..._withDividers(context, items.map(_vitalTile).toList()),
      ],
    );
  }

  Widget _medicationsSection(BuildContext context) {
    final items = _maps(_portal?['medications']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExternalSectionHeading(
          title: 'Active medications',
          description: 'Medication information shared for this patient.',
          trailing: AppButton(
            label: 'Assign',
            icon: AppIcons.add,
            size: AppButtonSize.sm,
            onPressed: () => setState(() => _finding = _Finding.medication),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (items.isEmpty)
          const ExternalEmptyPanel(
            icon: AppIcons.medication,
            title: 'No active medications shared',
            message: 'A medication can be added using Assign medication.',
          )
        else
          ..._withDividers(context, items.map(_medicationTile).toList()),
      ],
    );
  }

  Widget _documentsSection(BuildContext context) {
    final items = _maps(_portal?['documents']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExternalSectionHeading(
          title: 'Document details',
          description:
              'This guest view provides metadata only; file preview is unavailable.',
          trailing: AppButton(
            label: 'Upload',
            icon: AppIcons.upload,
            size: AppButtonSize.sm,
            onPressed: () => setState(() => _finding = _Finding.document),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (items.isEmpty)
          const ExternalEmptyPanel(
            icon: AppIcons.document,
            title: 'No document metadata shared',
            message: 'A report can be added using Upload document.',
          )
        else
          ..._withDividers(context, items.map(_documentTile).toList()),
      ],
    );
  }

  Widget _findingPanel(BuildContext context, _Finding finding) {
    return ExternalSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppButton.icon(
                icon: AppIcons.back,
                semanticLabel: 'Close finding form',
                onPressed: () => setState(() => _finding = null),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  _findingLabel(finding),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _doctorName,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Your name (optional)',
              helperText: 'This is an author label, not identity verification.',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          switch (finding) {
            _Finding.vital => _RecordVitalForm(
              catalog: _maps(_portal?['catalog']),
              selectedKey: _selectedVitalKey,
              onKeyChanged: (value) =>
                  setState(() => _selectedVitalKey = value),
              value: _vitalValue,
              secondaryValue: _vitalSecondary,
              saving: _savingVital,
              onSubmit: _recordVital,
            ),
            _Finding.note => _ConsultationNoteForm(
              controller: _note,
              saving: _savingNote,
              onSubmit: _submitNote,
            ),
            _Finding.medication => _AssignMedicationForm(
              name: _medName,
              dosage: _medDosage,
              frequency: _medFrequency,
              instructions: _medInstructions,
              saving: _savingMed,
              onSubmit: _assignMedication,
            ),
            _Finding.document => _UploadDocumentForm(
              title: _docTitle,
              description: _docDescription,
              category: _docCategory,
              onCategoryChanged: (value) =>
                  setState(() => _docCategory = value),
              fileName: _pickedFileName,
              onPick: _pickDocument,
              saving: _savingDoc,
              onSubmit: _uploadDocument,
            ),
          },
        ],
      ),
    );
  }

  ExternalRecordTile _vitalTile(Map<String, dynamic> item) {
    final risk = (item['risk'] ?? '').toString();
    final color = switch (risk.toLowerCase()) {
      'critical' || 'high' => AppColors.critical,
      'warning' || 'elevated' => AppColors.warning,
      'normal' => AppColors.success,
      _ => AppColors.info,
    };
    return ExternalRecordTile(
      icon: AppIcons.vitals,
      title: (item['vital'] ?? item['label'] ?? 'Vital').toString(),
      subtitle: (item['display_value'] ?? item['value'] ?? 'Value not recorded')
          .toString(),
      label: risk.isEmpty ? null : risk,
      labelColor: color,
    );
  }

  ExternalRecordTile _medicationTile(Map<String, dynamic> item) {
    final parts = [
      item['dosage'],
      item['frequency'],
    ].where((value) => (value ?? '').toString().isNotEmpty).join(' · ');
    return ExternalRecordTile(
      icon: AppIcons.medication,
      title: (item['name'] ?? 'Medication').toString(),
      subtitle: parts.isEmpty ? 'Details not recorded' : parts,
      label: (item['prescribed_by'] ?? '').toString().isEmpty
          ? null
          : item['prescribed_by'].toString(),
    );
  }

  ExternalRecordTile _documentTile(Map<String, dynamic> item) {
    final subtitle = [
      item['category'],
      item['uploaded_by'],
    ].where((value) => (value ?? '').toString().isNotEmpty).join(' · ');
    return ExternalRecordTile(
      icon: AppIcons.document,
      title: (item['title'] ?? 'Document').toString(),
      subtitle: subtitle.isEmpty ? 'Document details' : subtitle,
    );
  }

  List<Widget> _withDividers(BuildContext context, List<Widget> children) {
    return [
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0) Divider(color: AppPalette.border(context)),
        children[index],
      ],
    ];
  }

  static List<Map<String, dynamic>> _maps(dynamic value) =>
      ((value as List?) ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'P';
    return parts.length == 1
        ? parts.first.substring(0, 1).toUpperCase()
        : '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static String _sectionLabel(_RecordSection section) => switch (section) {
    _RecordSection.summary => 'Summary',
    _RecordSection.vitals => 'Vitals',
    _RecordSection.medications => 'Medications',
    _RecordSection.documents => 'Documents',
  };

  static String _findingLabel(_Finding finding) => switch (finding) {
    _Finding.vital => 'Record vital',
    _Finding.note => 'Consultation note',
    _Finding.medication => 'Assign medication',
    _Finding.document => 'Upload document',
  };

  static Map<String, dynamic> _demoPortal(String token) => {
    'expires_at': DateTime.now()
        .add(const Duration(hours: 23))
        .toIso8601String(),
    'patient': {
      'name': 'Amara Okonkwo',
      'unique_id': 'MCR-10042',
      'age': 34,
      'conditions': ['Type 2 diabetes', 'Hypertension'],
      'condition': 'Type 2 diabetes · Hypertension',
      'allergies': ['Penicillin'],
      'blood_type': 'O+',
    },
    'summary': 'External consult link (demo): ${token.length} characters',
    'vitals': [
      {
        'vital': 'Blood glucose',
        'display_value': '142 mg/dL',
        'risk': 'elevated',
      },
      {
        'vital': 'Blood pressure',
        'display_value': '138/86 mmHg',
        'risk': 'elevated',
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
        'category': 'Lab result',
        'uploaded_by': 'Care team',
      },
    ],
    'catalog': [
      {'vital_key': 'bloodPressure', 'label': 'Blood pressure', 'unit': 'mmHg'},
      {'vital_key': 'bloodGlucose', 'label': 'Blood glucose', 'unit': 'mg/dL'},
      {'vital_key': 'heartRate', 'label': 'Heart rate', 'unit': 'bpm'},
    ],
  };
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.expiresAt,
    required this.patientName,
    required this.onEnd,
  });

  final DateTime expiresAt;
  final String patientName;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        final identity = Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: const Icon(AppIcons.link, color: AppColors.info),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'External clinical access',
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    patientName,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        );
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AppSpacing.md : AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppPalette.surface(context),
            border: Border(
              bottom: BorderSide(color: AppPalette.border(context)),
            ),
          ),
          child: compact
              ? Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: identity),
                        AppButton.icon(
                          icon: AppIcons.logout,
                          semanticLabel: 'End viewing',
                          onPressed: onEnd,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ExternalStatusChip(
                        label:
                            'Expires ${DateFormat.MMMd().add_jm().format(expiresAt)}',
                        icon: AppIcons.time,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: identity),
                    ExternalStatusChip(
                      label:
                          'Expires ${DateFormat.MMMd().add_jm().format(expiresAt)}',
                      icon: AppIcons.time,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AppButton(
                      label: 'End viewing',
                      icon: AppIcons.logout,
                      size: AppButtonSize.sm,
                      variant: AppButtonVariant.ghost,
                      onPressed: onEnd,
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _BoundaryLine extends StatelessWidget {
  const _BoundaryLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.info),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

class _PreviewGroup extends StatelessWidget {
  const _PreviewGroup({
    required this.title,
    required this.empty,
    required this.children,
    required this.onViewAll,
  });

  final String title;
  final String empty;
  final List<Widget> children;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(onPressed: onViewAll, child: const Text('View all')),
          ],
        ),
        if (children.isEmpty)
          Text(
            empty,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          )
        else
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) Divider(color: AppPalette.border(context)),
            children[index],
          ],
      ],
    );
  }
}

class _RecordVitalForm extends StatelessWidget {
  const _RecordVitalForm({
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
    final isBloodPressure = selectedKey == 'bloodPressure';
    String unitFor(String? key) {
      for (final item in catalog) {
        if (item['vital_key'] == key) return (item['unit'] ?? '').toString();
      }
      return '';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'The server classifies the reading after it is added.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppPalette.textMuted(context)),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: selectedKey,
          decoration: const InputDecoration(labelText: 'Vital'),
          items: [
            for (final item in catalog)
              DropdownMenuItem(
                value: item['vital_key'] as String,
                child: Text(
                  '${item['label']}${(item['unit'] ?? '').toString().isEmpty ? '' : ' (${item['unit']})'}',
                ),
              ),
          ],
          onChanged: onKeyChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final fields = [
              TextField(
                controller: value,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: isBloodPressure ? 'Systolic' : 'Value',
                  suffixText: unitFor(selectedKey),
                ),
              ),
              if (isBloodPressure)
                TextField(
                  controller: secondaryValue,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Diastolic'),
                ),
            ];
            if (fields.length == 1 || constraints.maxWidth < 480) {
              return Column(
                children: [
                  for (var i = 0; i < fields.length; i++) ...[
                    fields[i],
                    if (i < fields.length - 1)
                      const SizedBox(height: AppSpacing.md),
                  ],
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: fields[0]),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: fields[1]),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Add vital to chart',
          icon: AppIcons.vitals,
          loading: saving,
          expand: true,
          onPressed: onSubmit,
        ),
      ],
    );
  }
}

class _ConsultationNoteForm extends StatelessWidget {
  const _ConsultationNoteForm({
    required this.controller,
    required this.saving,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool saving;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          minLines: 5,
          maxLines: 8,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: 'Consultation note',
            hintText: 'Findings, recommendations, and follow-up plan',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Submit consultation note',
          icon: AppIcons.send,
          loading: saving,
          expand: true,
          onPressed: onSubmit,
        ),
      ],
    );
  }
}

class _AssignMedicationForm extends StatelessWidget {
  const _AssignMedicationForm({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: name,
          maxLength: 160,
          decoration: const InputDecoration(labelText: 'Medication name'),
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final dose = TextField(
              controller: dosage,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Dosage'),
            );
            final timing = TextField(
              controller: frequency,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Frequency'),
            );
            return constraints.maxWidth < 480
                ? Column(
                    children: [
                      dose,
                      const SizedBox(height: AppSpacing.md),
                      timing,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: dose),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: timing),
                    ],
                  );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: instructions,
          minLines: 2,
          maxLines: 4,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: 'Instructions (optional)',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Review the patient, medication, dosage, and frequency before submitting.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppPalette.textMuted(context)),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Add medication to chart',
          icon: AppIcons.medication,
          loading: saving,
          expand: true,
          onPressed: onSubmit,
        ),
      ],
    );
  }
}

class _UploadDocumentForm extends StatelessWidget {
  const _UploadDocumentForm({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: title,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Document title'),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<DocumentCategory>(
          initialValue: category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [
            for (final value in DocumentCategory.values)
              DropdownMenuItem(
                value: value,
                child: Text(_categoryLabel(value)),
              ),
          ],
          onChanged: (value) {
            if (value != null) onCategoryChanged(value);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: description,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: fileName ?? 'Choose PDF, image, or Word file',
          icon: AppIcons.attach,
          variant: AppButtonVariant.secondary,
          expand: true,
          onPressed: saving ? null : onPick,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Accepted: PDF, JPG, PNG, DOC, DOCX · maximum 10 MB',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Upload to patient chart',
          icon: AppIcons.upload,
          loading: saving,
          expand: true,
          onPressed: onSubmit,
        ),
      ],
    );
  }

  static String _categoryLabel(DocumentCategory category) => switch (category) {
    DocumentCategory.labResult => 'Lab result',
    DocumentCategory.prescription => 'Prescription',
    DocumentCategory.imaging => 'Imaging',
    DocumentCategory.discharge => 'Discharge summary',
    DocumentCategory.consultationNote => 'Consultation note',
    DocumentCategory.other => 'Other',
  };
}
