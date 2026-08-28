import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../firebase_options.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/user_role.dart';
import '../../shared/navigation/root_navigator.dart';
import '../../shared/alerts/alert_center.dart';
import '../../shared/widgets/app_toast.dart';
import '../realtime/background_session_sync.dart';
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
        _handleAlertPush(message.data, fromTap: true);
      case 'appointment':
        _handleAppointmentPush(message.data, fromTap: true);
      case 'message':
        _handleMessagePush(message.data, fromTap: true);
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

    await BackgroundSessionSync.refresh(role: user.role, urgent: true);

    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    if (_isStaff(user.role) && data['kind'] == 'sos') {
      // AlertCenter owns scope, ring policy and de-duplication, so a push and
      // a poll arriving together surface one notification, not two popups.
      AlertCenter.instance.refresh();
    }

    final route = _routeForPush(data['kind'] as String? ?? 'sos', user.role);
    if (fromTap && route != null) {
      _openRoute(ctx, route, data: data);
    } else if (!_isStaff(user.role)) {
      AppToast.notification(
        ctx,
        title: data['kind'] == 'sos_resolved'
            ? 'Emergency update'
            : 'SOS update',
        message:
            (data['message'] as String?) ??
            'Your emergency status has been updated.',
        onOpen: route == null ? null : () => _openRoute(ctx, route, data: data),
      );
    }
  }

  Future<void> _handleAlertPush(
    Map<String, dynamic> data, {
    bool fromTap = false,
  }) async {
    final user = AuthState.instance.user;
    if (user == null) return;

    await BackgroundSessionSync.refresh(role: user.role, urgent: true);

    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    final isCritical = data['kind'] == 'vital_critical';
    final patientName = data['patient_name'] as String?;
    final message = patientName != null
        ? '$patientName · ${isCritical ? 'Critical alert' : 'New alert'}'
        : (isCritical ? 'Critical patient alert' : 'New patient alert');

    final route = _routeForPush(data['kind'] as String? ?? 'alert', user.role);
    if (fromTap && route != null) {
      _openRoute(ctx, route, data: data);
      return;
    }

    if (_isStaff(user.role)) {
      // The shared urgent banner owns staff alert presentation and prevents a
      // push plus Reverb invalidation from drawing the same alert twice.
      AlertCenter.instance.refresh();
      return;
    }

    AppToast.show(
      ctx,
      title: isCritical ? 'Critical vital alert' : 'Vital alert',
      message: message,
      kind: isCritical ? AppToastKind.error : AppToastKind.warning,
      duration: const Duration(seconds: 7),
      actionLabel: route == null ? null : 'Open',
      onAction: route == null ? null : () => _openRoute(ctx, route, data: data),
    );
  }

  Future<void> _handleAppointmentPush(
    Map<String, dynamic> data, {
    bool fromTap = false,
  }) async {
    final user = AuthState.instance.user;
    if (user == null) return;
    await BackgroundSessionSync.refresh(role: user.role);

    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    final patientName = data['patient_name'] as String?;
    final route = _routeForPush('appointment', user.role);
    if (fromTap && route != null) {
      _openRoute(ctx, route, data: data);
      return;
    }
    AppToast.notification(
      ctx,
      title: 'Appointment updated',
      message: patientName != null
          ? 'Appointment updated · $patientName'
          : 'Appointment updated',
      onOpen: route == null ? null : () => _openRoute(ctx, route, data: data),
    );
  }

  Future<void> _handleMessagePush(
    Map<String, dynamic> data, {
    bool fromTap = false,
  }) async {
    final user = AuthState.instance.user;
    if (user == null) return;
    await BackgroundSessionSync.refresh(role: user.role);

    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final route = _routeForPush('message', user.role);
    if (fromTap && route != null) {
      _openRoute(ctx, route, data: data);
      return;
    }
    AppToast.notification(
      ctx,
      title: 'New message',
      message:
          (data['message'] as String?) ??
          (data['sender_name'] == null
              ? 'A new care message is waiting.'
              : 'Message from ${data['sender_name']}'),
      onOpen: route == null ? null : () => _openRoute(ctx, route, data: data),
    );
  }

  bool _isStaff(UserRole role) =>
      role == UserRole.doctor ||
      role == UserRole.admin ||
      role == UserRole.mcareAssistant;

  String? _routeForPush(String kind, UserRole role) => switch (kind) {
    'sos' || 'sos_resolved' => switch (role) {
      UserRole.patient => RouteNames.patientSos,
      UserRole.doctor => RouteNames.doctorSos,
      UserRole.admin => RouteNames.adminSos,
      UserRole.mcareAssistant => RouteNames.assistantSos,
      _ => null,
    },
    'alert' || 'vital_critical' => switch (role) {
      UserRole.patient => RouteNames.patientVitals,
      UserRole.doctor => RouteNames.doctorAlerts,
      UserRole.admin => RouteNames.adminAlerts,
      UserRole.mcareAssistant => RouteNames.assistantAlerts,
      _ => null,
    },
    'appointment' => switch (role) {
      UserRole.patient => RouteNames.patientAppointments,
      UserRole.doctor => RouteNames.doctorAppointments,
      UserRole.admin => RouteNames.adminCareRequests,
      UserRole.mcareAssistant => RouteNames.assistantCareRequests,
      _ => null,
    },
    'message' => switch (role) {
      UserRole.patient => RouteNames.patientMessages,
      UserRole.doctor => RouteNames.doctorMessages,
      UserRole.admin => RouteNames.adminMessages,
      UserRole.mcareAssistant => RouteNames.assistantMessages,
      _ => null,
    },
    _ => null,
  };

  void _openRoute(
    BuildContext context,
    String route, {
    required Map<String, dynamic> data,
  }) {
    if (!context.mounted) return;
    Navigator.of(context).pushNamed(
      route,
      arguments: {
        if (data['patient_id'] != null) 'patientId': data['patient_id'],
        if (data['event_id'] != null) 'eventId': data['event_id'],
        if (data['alert_id'] != null) 'alertId': data['alert_id'],
      },
    );
  }
}
