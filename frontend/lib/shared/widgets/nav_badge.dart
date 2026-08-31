import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Count bubble for navigation surfaces — the bottom nav, the desktop rail and
/// the hub tiles. Same red and the same 9+ cap as the header bell, so one
/// number never reads two ways depending on where it is shown.
class NavBadge extends StatelessWidget {
  const NavBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: AppColors.critical,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppPalette.surface(context), width: 1.5),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1.3,
        ),
      ),
    );
  }
}
