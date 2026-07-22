import 'package:flutter/widgets.dart';

enum ScreenTier { mobile, tablet, desktop }

class Breakpoints {
  Breakpoints._();
  static const double mobile = 600;
  static const double tablet = 1024;
  static const double wide = 1440;
}

/// Reports the current `ScreenTier`. Use this to branch layout — never logic.
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, ScreenTier tier) builder;

  static ScreenTier of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < Breakpoints.mobile) return ScreenTier.mobile;
    if (width < Breakpoints.tablet) return ScreenTier.tablet;
    return ScreenTier.desktop;
  }

  @override
  Widget build(BuildContext context) => builder(context, of(context));
}

extension ScreenTierX on ScreenTier {
  bool get isMobile => this == ScreenTier.mobile;
  bool get isTablet => this == ScreenTier.tablet;
  bool get isDesktop => this == ScreenTier.desktop;
  bool get isHandheld => this == ScreenTier.mobile || this == ScreenTier.tablet;
}
