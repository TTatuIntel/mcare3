import '../../shared/theme/app_layout.dart';
import '../../shared/widgets/app_button.dart';

/// Auth form aliases — delegates to [AppLayout] for app-wide uniformity.
abstract final class AuthFormLayout {
  static const double fieldGap = AppLayout.fieldGap;
  static const double sectionGap = AppLayout.sectionGap;
  static const double controlHeight = AppLayout.controlHeight;
  static const AppButtonSize buttonSize = AppButtonSize.md;
  static const bool denseFields = AppLayout.compactFields;
}
