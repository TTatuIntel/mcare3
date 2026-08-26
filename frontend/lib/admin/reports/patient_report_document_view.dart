import 'package:flutter/material.dart';

import '../../shared/models/patient_report_request.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/dossier/dossier_blocks.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';

/// Renders an assembled patient report exactly as it was disclosed.
///
/// The body comes from the server's frozen snapshot, so re-opening an issued
/// report shows what actually went out rather than the record as it stands
/// today. Consent and signature provenance is printed alongside the content —
/// a reader can always see who approved the disclosure and who signed it.
class PatientReportDocumentView {
  PatientReportDocumentView._();

  static Future<void> show(
    BuildContext context, {
    required PatientReportDocument document,
  }) {
    return GlassSheet.show<void>(
      context,
      title: document.title,
      subtitle: document.patientName ?? 'Patient report',
      maxWidth: 760,
      child: _DocumentBody(document: document),
    );
  }
}

class _DocumentBody extends StatelessWidget {
  const _DocumentBody({required this.document});

  final PatientReportDocument document;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Provenance(document: document),
        const SizedBox(height: AppSpacing.lg),
        for (final block in document.sections) ...[
          _Block(block: block),
          const SizedBox(height: AppSpacing.md),
        ],
        if (document.sections.isEmpty)
          Text(
            'This report contains no sections.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        _Footer(document: document),
      ],
    );
  }
}

/// Header block: who it is about, who prepared it, and the approval chain.
class _Provenance extends StatelessWidget {
  const _Provenance({required this.document});
  final PatientReportDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.doctorGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: AppColors.doctorGreen.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                AppIcons.report,
                size: 18,
                color: AppColors.doctorGreen,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  document.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          DossierRow(label: 'Patient', value: document.patientName),
          DossierRow(label: 'Patient ID', value: document.patientUniqueId),
          DossierRow(label: 'Purpose', value: document.purpose),
          DossierRow(label: 'Recipient', value: document.recipient),
          DossierRow(label: 'Prepared by', value: document.preparedBy),
          DossierRow(
            label: 'Generated',
            value: dossierDateTime(document.generatedAt),
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.block});
  final ReportBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            block.title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        GlassCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: block.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    block.emptyMessage,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              : switch (block.kind) {
                  'table' => _Table(block: block),
                  'notes' => _Notes(block: block),
                  _ => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final f in block.fields)
                        DossierRow(label: f.label, value: f.value),
                    ],
                  ),
                },
        ),
      ],
    );
  }
}

/// Wide tables scroll inside their own card rather than stretching the sheet.
class _Table extends StatelessWidget {
  const _Table({required this.block});
  final ReportBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: DataTable(
        headingRowHeight: 34,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 46,
        horizontalMargin: 0,
        columnSpacing: AppSpacing.lg,
        headingTextStyle: theme.textTheme.labelSmall?.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppPalette.textMuted(context),
          letterSpacing: 0.4,
        ),
        dataTextStyle: theme.textTheme.labelSmall?.copyWith(
          fontSize: 11,
          color: AppPalette.ink(context),
        ),
        columns: [for (final c in block.columns) DataColumn(label: Text(c))],
        rows: [
          for (final row in block.rows)
            DataRow(
              cells: [
                for (var i = 0; i < block.columns.length; i++)
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        i < row.length ? row[i] : '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Notes extends StatelessWidget {
  const _Notes({required this.block});
  final ReportBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < block.notes.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Divider(height: 1, color: AppPalette.border(context)),
            const SizedBox(height: AppSpacing.sm),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  block.notes[i]['title'] ?? 'Note',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    block.notes[i]['author'],
                    block.notes[i]['at'],
                  ].where((e) => e != null && e.isNotEmpty).join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontSize: 10,
                  ),
                ),
                if ((block.notes[i]['body'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    block.notes[i]['body']!,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The approval chain, printed where a signature block would go on paper.
class _Footer extends StatelessWidget {
  const _Footer({required this.document});
  final PatientReportDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppPalette.surfaceMuted(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'AUTHORISATION',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: AppPalette.textMuted(context),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          DossierRow(
            label: 'Patient consent',
            value: document.consentGrantedAt == null
                ? 'Not required for these sections'
                : '${dossierDateTime(document.consentGrantedAt)} '
                      '(${dossierHumanize(document.consentMethod)})',
            valueColor: document.consentGrantedAt == null
                ? null
                : AppColors.success,
          ),
          DossierRow(
            label: 'Signed by',
            value: document.signatureName ?? 'Not required',
            valueColor: document.signatureName == null
                ? null
                : AppColors.success,
            emphasise: document.signatureName != null,
          ),
          DossierRow(
            label: 'Signed at',
            value: dossierDateTime(document.signedAt),
          ),
          if (document.signatureNote != null)
            DossierRow(label: 'Note', value: document.signatureNote),
        ],
      ),
    );
  }
}
