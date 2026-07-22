/// Maps raw API / network exceptions to short, user-safe copy.
import '../env/app_env.dart';

class ApiErrorMessages {
  ApiErrorMessages._();

  static String sanitize(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return 'Something went wrong. Please try again.';
    }

    final message = raw.trim();
    final lower = message.toLowerCase();

    if (_looksLikeDatabaseFailure(lower)) {
      return 'Database or API server is offline. '
          'Start MySQL and the Laravel API in XAMPP, '
          'or run in demo mode with MCARE_USE_BACKEND=false.';
    }

    if (_looksLikeNetworkFailure(lower)) {
      return 'Cannot reach the mCare server. '
          'Check that the API is running at ${AppEnv.apiBaseUrl}.';
    }

    if (message.length > 160 ||
        lower.contains(' sql:') ||
        lower.contains('sqlstate')) {
      return 'Server error. Please try again in a moment.';
    }

    return message;
  }

  static bool _looksLikeDatabaseFailure(String lower) {
    return lower.contains('sqlstate') ||
        lower.contains('mysql') ||
        lower.contains('connection: mysql') ||
        lower.contains('actively refused') ||
        lower.contains('no connection could be made');
  }

  static bool _looksLikeNetworkFailure(String lower) {
    return lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('connection timed out') ||
        lower.contains('network is unreachable');
  }
}
