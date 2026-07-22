import 'package:flutter/foundation.dart';

/// Tracks when [AppBootstrap.run] has finished so [LandingView] can reveal
/// get-started content without flashing a blank frame.
class LaunchReadiness extends ChangeNotifier {
  LaunchReadiness._();

  static final LaunchReadiness instance = LaunchReadiness._();

  bool bootstrapComplete = false;

  void markBootstrapComplete() {
    if (bootstrapComplete) return;
    bootstrapComplete = true;
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    bootstrapComplete = false;
    notifyListeners();
  }
}
