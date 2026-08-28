import 'package:flutter/material.dart';

import '../../core/api/sos_response_api.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_icons.dart';
import '../widgets/glass_sheet.dart';

/// Hands an emergency to a provider — the patient's own care team first.
///
/// Routing an emergency past the people who already know the patient's
/// history, to a stranger who does not, is a clinical regression rather than
/// a neutral choice. So the care team leads the list and is offered by name;
/// everyone else appears underneath, and only when they can actually be
/// reached — offering a suspended account wastes the one thing an emergency
/// does not have.
class SosHandoverSheet {
  SosHandoverSheet._();

  static Future<SosCandidate?> show(
    BuildContext context, {
    required String eventId,
    required String patientName,
  }) {
    return GlassSheet.show<SosCandidate>(
      context,
      title: 'Hand over this emergency',
      subtitle: 'Choose who takes $patientName',
      child: _HandoverBody(eventId: eventId),
    );
  }
}

class _HandoverBody extends StatefulWidget {
  const _HandoverBody({required this.eventId});

  final String eventId;

  @override
  State<_HandoverBody> createState() => _HandoverBodyState();
}

class _HandoverBodyState extends State<_HandoverBody> {
  List<SosCandidate> _careTeam = const [];
  List<SosCandidate> _others = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await SosResponseApi.instance.candidates(widget.eventId);
      if (!mounted) return;
      setState(() {
        _careTeam = result.careTeam;
        _others = result.others;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load providers.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          'Finding who can take this…',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppPalette.textMuted(context),
          ),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final available = _careTeam.where((c) => c.available).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label('Care team'),
        if (_careTeam.isEmpty)
          _Note(
            'This patient has no care team yet. Anyone below can take it.',
            tone: AppColors.warning,
          )
        else ...[
          for (final candidate in _careTeam)
            _CandidateRow(
              candidate: candidate,
              onTap: candidate.available
                  ? () => Navigator.of(context).pop(candidate)
                  : null,
            ),
          if (available.isEmpty)
            _Note(
              'Nobody on the care team is available. Choose another provider '
              'below — this is recorded on the trail.',
              tone: AppColors.warning,
            ),
        ],
        const SizedBox(height: AppSpacing.md),
        _Label('Other active providers'),
        if (_others.isEmpty)
          _Note(
            'No other provider is active right now.',
            tone: AppPalette.textMuted(context),
          )
        else
          for (final candidate in _others)
            _CandidateRow(
              candidate: candidate,
              onTap: () => Navigator.of(context).pop(candidate),
            ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.xs,
      ),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppPalette.textMuted(context),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {required this.tone});
  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: tone,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({required this.candidate, required this.onTap});

  final SosCandidate candidate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final accent = candidate.onCareTeam
        ? AppColors.success
        : Theme.of(context).colorScheme.primary;
    final fg = enabled ? accent : AppPalette.textMuted(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppPalette.surfaceAlt(context),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: enabled
                    ? accent.withValues(alpha: 0.32)
                    : AppPalette.border(context),
              ),
            ),
            child: Row(
              children: [
                Icon(AppIcons.nurse, size: 18, color: fg),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: enabled
                              ? AppPalette.ink(context)
                              : AppPalette.textMuted(context),
                        ),
                      ),
                      Text(
                        [
                          if (candidate.specialty?.isNotEmpty == true)
                            candidate.specialty!,
                          if (candidate.facility?.isNotEmpty == true)
                            candidate.facility!,
                          if (!candidate.available) 'Not available',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (candidate.onCareTeam)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusPill,
                      ),
                    ),
                    child: const Text(
                      'CARE TEAM',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
