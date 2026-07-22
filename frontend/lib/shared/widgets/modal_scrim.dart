import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Full-screen modal scrim with blur on native and tinted gradient on web.
class ModalScrim extends StatelessWidget {
  const ModalScrim({
    super.key,
    this.color,
    this.onTap,
  });

  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scrim = color ??
        (isDark ? AppColors.darkOverlay : AppColors.overlay);

    Widget layer;
    if (kIsWeb) {
      final ink = isDark ? AppColors.darkInk : AppPalette.ink(context);
      layer = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              ink.withOpacity(isDark ? 0.55 : 0.18),
              ink.withOpacity(isDark ? 0.78 : 0.42),
            ],
          ),
        ),
      );
    } else {
      layer = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: ColoredBox(color: scrim),
        ),
      );
    }

    if (onTap == null) return layer;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: layer,
    );
  }
}
