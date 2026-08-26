import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/models/user_role.dart';
import '../../shared/navigation/root_navigator.dart';
import '../../shared/services/admin_sos_service.dart';
import '../../shared/services/doctor_session_service.dart';
import '../../shared/alerts/urgent_alert_dialog.dart';
import '../../shared/widgets/app_toast.dart';
import '../api/api_client.dart';
import '../api/fcm_api.dart';
import '../env/app_env.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// Registers FCM tokens and routes SOS push payloads to the in-app alert UI.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  FirebaseMessaging? _messaging;
  String? _token;
  bool _initialized = false;

  String? get token => _token;

  Future<void> init() async {
    if (_initialized || !AppEnv.firebaseEnabled) return;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      _messaging = FirebaseMessaging.instance;

      final settings = await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      if (kIsWeb) {
        await _messaging!.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpened);

      _messaging!.onTokenRefresh.listen((t) async {
        _token = t;
        await _registerToken(t);
      });

      _token = await _messaging!.getToken(
        vapidKey: kIsWeb && AppEnv.firebaseVapidKey.isNotEmpty
            ? AppEnv.firebaseVapidKey
            : null,
      );

      if (_token != null && ApiClient.instance.token != null) {
        await _registerToken(_token!);
      }

      _initialized = true;
    } catch (e) {
      debugPrint('Push init skipped: $e');
    }
  }

  Future<void> registerAfterLogin() async {
    if (!_initialized) await init();
    if (_token == null && _messaging != null) {
      _token = await _messaging!.getToken(
        vapidKey: kIsWeb && AppEnv.firebaseVapidKey.isNotEmpty
            ? AppEnv.firebaseVapidKey
            : null,
      );
    }
    if (_token != null) {
      await _registerToken(_token!);
    }
  }

  Future<void> unregisterOnLogout() async {
    final t = _token;
    if (t != null) {
      try {
        await FcmApi.instance.unregister(t);
      } catch (_) {}
    }
    _token = null;
  }

  Future<void> _registerToken(String token) async {
    if (!AppEnv.backendEnabled || ApiClient.instance.token == null) return;
    try {
      await FcmApi.instance.register(token: token, platform: _platformLabel());
    } catch (e) {
      debugPrint('FCM register failed: $e');
    }
  }

  String? _platformLabel() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return null;
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final kind = message.data['kind'] as String?;
    switch (kind) {
      case 'sos':
      case 'sos_resolved':
        _handleSosPush(message.data);
      case 'alert':
      case 'vital_critical':
        _handleAlertPush(message.data);
      case 'appointment':
        _handleAppointmentPush(message.data);
      case 'message':
        _handleMessagePush(message.data);
    }
  }

  void _onMessageOpened(RemoteMessage message) {
    final kind = message.data['kind'] as String?;
    switch (kind) {
      case 'sos':
      case 'sos_resolved':
        _handleSosPush(message.data, fromTap: true);
      case 'alert':
      case 'vital_critical':
        _handleAlertPush(message.data);
      case 'appointment':
        _handleAppointmentPush(message.data);
      case 'message':
        _handleMessagePush(message.data);
    }
  }

  Future<void> _handleSosPush(
    Map<String, dynamic> data, {
    bool fromTap = false,
  }) async {
    final user = AuthState.instance.user;
    if (user == null) return;

    if (user.role == UserRole.doctor) {
      await DoctorSessionService.instance.syncFromApi();
    } else if (user.role == UserRole.admin ||
        user.role == UserRole.mcareAssistant) {
      await AdminSosService.instance.syncFromApi();
    } else {
      return;
    }

    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    if (data['kind'] == 'sos') {
      // AlertCenter owns scope, ring policy, and de-duplication now, so a
      // push and a poll arriving together cannot stack two dialogs.
      UrgentAlertDialog.maybeShow(ctx);
    }
  }

  Future<void> _handleAlertPush(Map<String, dynamic> data) async {
    final user = AuthState.instance.user;
    if (user == null) return;

    if (user.role == UserRole.doctor) {
      await DoctorSessionService.instance.syncFromApi();
    } else if (user.role == UserRole.admin ||
        user.role == UserRole.mcareAssistant) {
      await AdminSosService.instance.syncFromApi();
    } else {
      return;
    }

    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    final isCritical = data['kind'] == 'vital_critical';
    final patientName = data['patient_name'] as String?;
    final message = patientName != null
        ? '$patientName · ${isCritical ? 'Critical alert' : 'New alert'}'
        : (isCritical ? 'Critical patient alert' : 'New patient alert');

    AppToast.show(
      ctx,
      message: message,
      kind: isCritical ? AppToastKind.error : AppToastKind.warning,
    );
  }

  Future<void> _handleAppointmentPush(Map<String, dynamic> data) async {
    final user = AuthState.instance.user;
    if (user == null || user.role != UserRole.doctor) return;
    await DoctorSessionService.instance.syncFromApi();

    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    final patientName = data['patient_name'] as String?;
    AppToast.info(
      ctx,
      patientName != null
          ? 'Appointment updated · $patientName'
          : 'Appointment updated',
    );
  }

  Future<void> _handleMessagePush(Map<String, dynamic> data) async {
    final user = AuthState.instance.user;
    if (user == null || user.role != UserRole.doctor) return;
    await DoctorSessionService.instance.syncFromApi();
  }
}
