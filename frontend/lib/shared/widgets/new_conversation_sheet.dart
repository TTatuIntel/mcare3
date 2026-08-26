import 'package:flutter/material.dart';

import '../auth/auth_state.dart';
import '../models/user_role.dart';
import '../state/messages_state.dart';
import '../state/staff_state.dart';
import '../state/staff_models.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';
import 'app_text_field.dart';
import 'app_toast.dart';
import 'glass_sheet.dart';
import 'staff_blocks.dart';
import 'loading/loading.dart';

/// Pick a patient or staff member to start (or reopen) a conversation.
class NewConversationSheet {
  NewConversationSheet._();

  static Future<String?> show(
    BuildContext context, {
    required String threadRouteName,
  }) {
    return GlassSheet.show<String>(
      context,
      title: 'New conversation',
      subtitle: 'Message a patient or care-team member',
      child: _NewConversationBody(threadRouteName: threadRouteName),
    );
  }
}

class _NewConversationBody extends StatefulWidget {
  const _NewConversationBody({required this.threadRouteName});

  final String threadRouteName;

  @override
  State<_NewConversationBody> createState() => _NewConversationBodyState();
}

class _NewConversationBodyState extends State<_NewConversationBody> {
  final _search = TextEditingController();
  bool _loading = false;
  String _filter = 'all';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<DirectoryUser> get _candidates {
    final me = AuthState.instance.user?.id;
    final q = _search.text.trim().toLowerCase();
    return StaffState.instance.users
        .where((u) => u.id != me && u.status == 'active')
        .where((u) {
          if (_filter == 'patients') return u.role == UserRole.patient;
          if (_filter == 'staff') return u.role != UserRole.patient;
          return true;
        })
        .where((u) {
          if (q.isEmpty) return true;
          return u.name.toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q) ||
              u.uniqueId.toLowerCase().contains(q);
        })
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _start(DirectoryUser user) async {
    setState(() => _loading = true);
    try {
      final convId = await MessagesState.instance.startConversationWith(
        userId: user.id,
        name: user.name,
        role: user.role == UserRole.mcareAssistant
            ? 'mcare_assistant'
            : user.role.name,
        specialty: user.specialty,
      );
      if (!mounted) return;
      if (convId == null) {
        AppToast.error(context, 'Could not start conversation.');
        return;
      }
      Navigator.of(context).pop(convId);
      Navigator.of(
        context,
      ).pushNamed(widget.threadRouteName, arguments: convId);
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, 'Could not start conversation.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _candidates;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Search',
          controller: _search,
          prefixIcon: AppIcons.search,
          hint: 'Name, email or ID',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _FilterChip(
              label: 'All',
              selected: _filter == 'all',
              onTap: () => setState(() => _filter = 'all'),
            ),
            const SizedBox(width: AppSpacing.xs),
            _FilterChip(
              label: 'Patients',
              selected: _filter == 'patients',
              onTap: () => setState(() => _filter = 'patients'),
            ),
            const SizedBox(width: AppSpacing.xs),
            _FilterChip(
              label: 'Staff',
              selected: _filter == 'staff',
              onTap: () => setState(() => _filter = 'staff'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: McareLoadingMark(size: McareMarkSize.small)),
          )
        else if (users.isEmpty)
          Text(
            'No matching users. Sync the directory from Users or Patients.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: StaffListCard(
              children: users
                  .map(
                    (u) => StaffListRow(
                      icon: u.role == UserRole.patient
                          ? AppIcons.profile
                          : AppIcons.careTeam,
                      iconColor: u.role.accent,
                      title: u.name,
                      subtitle: '${u.role.label} · ${u.email}',
                      pill: u.uniqueId,
                      onTap: () => _start(u),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.brandIndigo.withValues(alpha: 0.15),
      checkmarkColor: AppColors.brandIndigo,
    );
  }
}
