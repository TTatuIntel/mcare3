import 'package:flutter/material.dart';

import '../../../core/api/auth_api.dart';
import '../../auth/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/glass_card.dart';

class AccountSecuritySettingsSection extends StatelessWidget {
  const AccountSecuritySettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthState.instance.user;
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(AppIcons.lock),
            title: const Text('Signed-in devices'),
            subtitle: const Text(
              'Review and revoke remembered browser or mobile sessions.',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              useSafeArea: true,
              isScrollControlled: true,
              builder: (_) => const _SessionManagerSheet(),
            ),
          ),
          Divider(color: AppPalette.border(context)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              user?.emailVerified == true
                  ? Icons.verified_user_outlined
                  : Icons.mark_email_unread_outlined,
              color: user?.emailVerified == true
                  ? AppColors.success
                  : AppColors.warning,
            ),
            title: Text(
              user?.emailVerified == true
                  ? 'Email verified'
                  : 'Email verification required',
            ),
            subtitle: Text(user?.email ?? 'No email address'),
          ),
        ],
      ),
    );
  }
}

class _SessionManagerSheet extends StatefulWidget {
  const _SessionManagerSheet();

  @override
  State<_SessionManagerSheet> createState() => _SessionManagerSheetState();
}

class _SessionManagerSheetState extends State<_SessionManagerSheet> {
  late Future<List<Map<String, dynamic>>> _sessions;
  String? _revoking;

  @override
  void initState() {
    super.initState();
    _sessions = AuthApi.instance.sessions();
  }

  void _reload() {
    setState(() => _sessions = AuthApi.instance.sessions());
  }

  Future<void> _revoke(Map<String, dynamic> session) async {
    final id = session['id']?.toString();
    if (id == null || session['current'] == true) return;
    setState(() => _revoking = id);
    try {
      await AuthApi.instance.revokeSession(id);
      if (!mounted) return;
      AppToast.success(context, 'Device session signed out.');
      _reload();
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not revoke that session.');
    } finally {
      if (mounted) setState(() => _revoking = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Signed-in devices', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const Text(
            'Sessions expire automatically. Revoke any browser or device you no longer recognize.',
          ),
          const SizedBox(height: AppSpacing.md),
          Flexible(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _sessions,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: _reload,
                      child: const Text('Could not load sessions · Retry'),
                    ),
                  );
                }
                final sessions = snapshot.data ?? const [];
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => Divider(color: AppPalette.border(context)),
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final current = session['current'] == true;
                    final id = session['id']?.toString();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(current ? Icons.smartphone_rounded : Icons.devices_rounded),
                      title: Text(session['name']?.toString() ?? 'mCare device'),
                      subtitle: Text(
                        current
                            ? 'This device'
                            : 'Expires ${session['expires_at'] ?? 'automatically'}',
                      ),
                      trailing: current
                          ? const Chip(label: Text('Current'))
                          : IconButton(
                              tooltip: 'Sign out device',
                              onPressed: _revoking == id ? null : () => _revoke(session),
                              icon: _revoking == id
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.logout_rounded),
                            ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
