import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/external_access_api.dart';
import '../../core/env/app_env.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/loading/loading.dart';

/// Patient-managed external access links & codes.
class ExternalAccessSheet {
  ExternalAccessSheet._();

  static Future<void> show(BuildContext context) {
    return GlassSheet.show(
      context,
      title: 'External doctor access',
      subtitle: 'Create a temp link and share via chat apps',
      child: const _Body(),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _label = TextEditingController();
  final _shareButtonKey = GlobalKey();
  List<ExternalAccessLink> _links = const [];
  bool _loading = true;
  bool _creating = false;
  bool _showCreateForm = false;
  bool _showExpired = false;

  /// Expiry day (local). Clamped to today … today+7.
  late DateTime _expiresOn;

  static const _helpMessage =
      'An outside doctor opens your link (or access code) on the web to '
      'view your record, record vitals, assign medication, and upload '
      'documents. Access expires automatically.';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _expiresOn = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    _load();
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  int get _expiresInHours {
    final end = DateTime(
      _expiresOn.year,
      _expiresOn.month,
      _expiresOn.day,
      23,
      59,
    );
    final hours = end.difference(DateTime.now()).inHours;
    if (hours < 1) return 1;
    if (hours > 168) return 168;
    return hours;
  }

  Future<void> _showHelp() {
    return AppDialog.confirm(
      context,
      title: 'How it works',
      message: _helpMessage,
      confirmLabel: 'Got it',
      cancelLabel: 'Close',
      icon: AppIcons.info,
    );
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = today.add(const Duration(days: 7));
    final initial = _expiresOn.isBefore(today)
        ? today.add(const Duration(days: 1))
        : (_expiresOn.isAfter(last) ? last : _expiresOn);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: last,
      helpText: 'Link expires on',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.info,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _expiresOn = picked);
  }

  Future<void> _load() async {
    try {
      final links = await ExternalAccessApi.instance.list();
      if (!mounted) return;
      setState(() {
        _links = links;
        _loading = false;
        _showCreateForm = links.where((l) => l.active).isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _showCreateForm = true;
      });
    }
  }

  Future<void> _create() async {
    if (!AppEnv.backendEnabled) {
      AppToast.info(context, 'Available when connected to the live backend.');
      return;
    }
    setState(() => _creating = true);
    try {
      final link = await ExternalAccessApi.instance.create(
        label: _label.text.trim(),
        expiresInHours: _expiresInHours,
      );
      if (!mounted) return;
      _label.clear();
      if (link != null) {
        setState(() {
          _links = [link, ..._links];
          _showCreateForm = false;
        });
        AppToast.success(context, 'Link ready — choose an app to share.');
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted) await _share(link);
        });
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not create link: $e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _revoke(ExternalAccessLink link) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Revoke access?',
      message:
          'The link and code "${link.label}" will stop working immediately.',
      confirmLabel: 'Revoke',
      danger: true,
      icon: AppIcons.close,
    );
    if (ok != true || !mounted) return;
    try {
      await ExternalAccessApi.instance.revoke(link.id);
      if (!mounted) return;
      await _load();
      if (mounted) AppToast.success(context, 'Access revoked.');
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not revoke the link.');
    }
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    AppToast.success(context, '$what copied to clipboard.');
  }

  Rect? _shareOrigin() {
    final box =
        _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _share(ExternalAccessLink link) async {
    final expires = DateFormat.MMMd().add_jm().format(link.expiresAt);
    final buffer = StringBuffer();
    if (link.url != null && link.url!.isNotEmpty) {
      buffer.writeln(link.url);
      buffer.writeln();
    }
    buffer.writeln('mCare — temporary access to my health record.');
    buffer.writeln(
        'Open the link to review my chart, record vitals, assign medication, and upload documents.');
    if (link.accessCode != null && link.accessCode!.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Access code: ${link.accessCode}');
    }
    buffer.writeln();
    buffer.write('Expires $expires.');

    final text = buffer.toString();
    try {
      await Share.share(
        text,
        subject: 'mCare access — ${link.label}',
        sharePositionOrigin: _shareOrigin(),
      );
    } catch (_) {
      _copy(text, 'Share message');
    }
  }

  Widget _helpIcon() {
    return IconButton(
      tooltip: 'How it works',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: Icon(AppIcons.info, size: 20, color: AppColors.info),
      onPressed: _showHelp,
    );
  }

  Widget _expiryFilter(ThemeData theme) {
    final label = DateFormat.MMMd().format(_expiresOn);
    return Material(
      color: AppPalette.surfaceAlt(context),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        onTap: _pickExpiryDate,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          child: Row(
            children: [
              Icon(AppIcons.calendar, size: 18, color: AppColors.info),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Expires on',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                AppIcons.expandMore,
                size: 20,
                color: AppPalette.textMuted(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateForm(ThemeData theme, {required bool compactHeader}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compactHeader)
          Row(
            children: [
              Expanded(
                child: Text('New link', style: theme.textTheme.titleSmall),
              ),
              _helpIcon(),
              TextButton(
                onPressed: () => setState(() => _showCreateForm = false),
                child: const Text('Cancel'),
              ),
            ],
          )
        else
          Align(alignment: Alignment.centerRight, child: _helpIcon()),
        AppTextField(
          label: 'Label (optional)',
          hint: 'e.g. City Hospital ER',
          controller: _label,
        ),
        const SizedBox(height: AppSpacing.sm),
        _expiryFilter(theme),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'Create & share',
          icon: AppIcons.share,
          loading: _creating,
          expand: true,
          onPressed: _create,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _links.where((l) => l.active).toList();
    final inactive = _links.where((l) => !l.active).toList();
    final primary = active.isNotEmpty ? active.first : null;
    final olderActive =
        active.length > 1 ? active.skip(1).toList() : const <ExternalAccessLink>[];

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: McareLoadingMark(size: McareMarkSize.small)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (primary != null) ...[
          _LinkCard(
            key: _shareButtonKey,
            link: primary,
            onShare: () => _share(primary),
            onCopyCode: primary.accessCode == null
                ? null
                : () => _copy(primary.accessCode!, 'Access code'),
            onCopyUrl:
                primary.url == null ? null : () => _copy(primary.url!, 'Link'),
            onRevoke: () => _revoke(primary),
            onHelp: _showHelp,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (!_showCreateForm)
            AppButton(
              label: 'Create another',
              icon: AppIcons.add,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              expand: true,
              onPressed: () => setState(() => _showCreateForm = true),
            )
          else
            _buildCreateForm(theme, compactHeader: true),
          if (olderActive.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final link in olderActive)
              _LinkCard(
                link: link,
                compact: true,
                onShare: () => _share(link),
                onCopyCode: link.accessCode == null
                    ? null
                    : () => _copy(link.accessCode!, 'Access code'),
                onCopyUrl:
                    link.url == null ? null : () => _copy(link.url!, 'Link'),
                onRevoke: () => _revoke(link),
              ),
          ],
        ] else
          _buildCreateForm(theme, compactHeader: false),
        if (inactive.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          InkWell(
            onTap: () => setState(() => _showExpired = !_showExpired),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${inactive.length} expired / revoked',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                  ),
                  Icon(
                    _showExpired ? AppIcons.expandLess : AppIcons.expandMore,
                    size: 18,
                    color: AppPalette.textMuted(context),
                  ),
                ],
              ),
            ),
          ),
          if (_showExpired)
            for (final link in inactive)
              _LinkCard(link: link, compact: true),
        ],
      ],
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    super.key,
    required this.link,
    this.compact = false,
    this.onShare,
    this.onCopyCode,
    this.onCopyUrl,
    this.onRevoke,
    this.onHelp,
  });

  final ExternalAccessLink link;
  final bool compact;
  final VoidCallback? onShare;
  final VoidCallback? onCopyCode;
  final VoidCallback? onCopyUrl;
  final VoidCallback? onRevoke;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        link.active ? AppColors.success : AppPalette.textMuted(context);
    final expires = DateFormat.MMMd().add_jm().format(link.expiresAt);
    final canAct = link.active && onShare != null;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(AppIcons.link, size: 16, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  link.label,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onHelp != null)
                IconButton(
                  tooltip: 'How it works',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: Icon(AppIcons.info, size: 18, color: AppColors.info),
                  onPressed: onHelp,
                ),
              Text(
                link.active
                    ? expires
                    : link.revokedAt != null
                        ? 'Revoked'
                        : 'Expired',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppPalette.textMuted(context)),
              ),
            ],
          ),
          if (link.active && link.accessCode != null && !compact) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              link.accessCode!,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
          ],
          if (canAct) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Share with doctor',
              icon: AppIcons.share,
              expand: true,
              size: compact ? AppButtonSize.sm : AppButtonSize.md,
              onPressed: onShare,
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                if (onCopyCode != null)
                  Expanded(
                    child: AppButton(
                      label: 'Code',
                      icon: AppIcons.copy,
                      variant: AppButtonVariant.secondary,
                      expand: true,
                      size: AppButtonSize.sm,
                      onPressed: onCopyCode,
                    ),
                  ),
                if (onCopyCode != null && onCopyUrl != null)
                  const SizedBox(width: AppSpacing.xs),
                if (onCopyUrl != null)
                  Expanded(
                    child: AppButton(
                      label: 'Link',
                      icon: AppIcons.link,
                      variant: AppButtonVariant.secondary,
                      expand: true,
                      size: AppButtonSize.sm,
                      onPressed: onCopyUrl,
                    ),
                  ),
                if (onRevoke != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    tooltip: 'Revoke',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(AppIcons.close,
                        size: 18, color: AppColors.critical),
                    onPressed: onRevoke,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
