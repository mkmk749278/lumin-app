/// FCM push notifications — topic subscriptions + tap routing.
///
/// Topic model (mirrors the engine's `src/push_notifications.py`):
///   * `alerts`  — market alerts (Pulse → Alerts feed)
///   * `signals` — new signals + terminal outcomes
///
/// The engine addresses FCM *topics*, never device tokens, so there is
/// no server-side token registry: enabling/disabling a class is a
/// client-side subscribe/unsubscribe persisted in SharedPreferences
/// (both default ON — subscription is applied on every app start, which
/// also covers FCM's occasional token rotation).
///
/// Web (PWA) channel (2026-07-18): the browser SDK cannot subscribe to
/// topics client-side, so the web path fetches a registration token
/// (`getToken` + VAPID key) and proxies the topic call through the
/// engine's stateless `POST /api/push/{subscribe,unsubscribe}` — which
/// needs the signed-in Bearer, so web push arms *after* auth via
/// [attachRepository] + [syncWebPush], not at boot.  On iOS the browser
/// only grants push at all inside an installed (Add-to-Home-Screen)
/// web app, and the permission prompt must follow a user gesture —
/// [enableWebPush] is that gesture entry point (wired to the install
/// banner + notification settings).
///
/// Display contract:
///   * Background / killed — the engine sends notification-payload
///     messages, so Android renders them without any app code (FCM's
///     default notification channel; per-class muting happens via our
///     topic toggles, which stop delivery entirely — stronger than an
///     OS channel mute).  On web the `firebase-messaging-sw.js` service
///     worker renders them.
///   * Foreground — `onMessage` never auto-displays; we surface a
///     one-line SnackBar with a VIEW action instead of a heads-up so
///     the user isn't double-notified about a screen they're inside.
///   * Tap — `data.route` (`pulse_alerts` | `signals`) lands in
///     [pendingRoute]; NavShell + PulsePage listen and switch tabs.
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository.dart';

/// Web-push VAPID public key (Firebase Console → Cloud Messaging → Web
/// configuration).  Baked at compile time by CI
/// (`--dart-define=LUMIN_FCM_VAPID_KEY=...`); empty in local/dev builds,
/// where web push simply stays unarmed.
const String kFcmVapidKey = String.fromEnvironment('LUMIN_FCM_VAPID_KEY');

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const topicAlerts = 'alerts';
  static const topicSignals = 'signals';

  static const _prefKeyPrefix = 'notif_topic_enabled_';

  /// Routing signal for notification taps.  NavShell listens and
  /// switches to the matching tab; PulsePage additionally flips its
  /// Dashboard/Alerts top tab for `pulse_alerts`.
  final ValueNotifier<String?> pendingRoute = ValueNotifier<String?>(null);

  /// Global messenger so foreground pushes can show a SnackBar from
  /// outside the widget tree.  Wired into MaterialApp by main.dart.
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  bool _initialised = false;

  /// Web only: the repository used to proxy topic calls through the
  /// engine.  Attached by NavShell once the signed-in shell mounts —
  /// the proxy endpoints require the Firebase Bearer, so there is
  /// nothing useful to do with it pre-auth.
  LuminRepository? _repo;

  /// Boot-time init.  Never throws — push is a convenience layer and a
  /// Firebase/Play-Services hiccup must not block app start.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      final messaging = FirebaseMessaging.instance;

      if (!kIsWeb) {
        // Android 13+ runtime permission (needs POST_NOTIFICATIONS in the
        // manifest — injected by the CI build).  On earlier Android this
        // resolves as granted without UI.  NOT requested on web at boot:
        // browsers (Apple especially) require a user gesture, and the
        // topic proxy needs the post-auth Bearer anyway — see
        // [enableWebPush] / [syncWebPush].
        await messaging.requestPermission();

        // Apply persisted topic choices (default: both ON).  Re-running
        // subscribe on every boot is idempotent and re-arms topics after
        // FCM token rotation.
        for (final topic in const [topicAlerts, topicSignals]) {
          if (await isTopicEnabled(topic)) {
            await messaging.subscribeToTopic(topic);
          } else {
            await messaging.unsubscribeFromTopic(topic);
          }
        }
      }

      // Foreground pushes → one-line SnackBar with a VIEW action.
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // Tap on a push while the app was backgrounded.
      FirebaseMessaging.onMessageOpenedApp.listen(_routeFromMessage);

      // Tap on a push that cold-started the app.
      final initial = await messaging.getInitialMessage();
      if (initial != null) _routeFromMessage(initial);
    } catch (e) {
      debugPrint('NotificationService.init failed (non-fatal): $e');
    }
  }

  // ------------------------------------------------------------------
  // Web push arming (PWA channel)
  // ------------------------------------------------------------------

  /// NavShell hands over the live repository once the signed-in shell
  /// mounts, then [syncWebPush] re-arms the engine-side topic
  /// subscriptions for this browser's current token (the web analogue
  /// of the Android boot-loop re-subscribe).  No-op off web.
  void attachRepository(LuminRepository repo) {
    if (!kIsWeb) return;
    _repo = repo;
    // Fire-and-forget: arming push must never block shell mount.
    unawaited(syncWebPush());
  }

  /// True when the browser has already granted notification permission.
  /// Used by the install banner / settings to decide whether to show the
  /// enable step.  Never prompts.
  Future<bool> webPushGranted() async {
    if (!kIsWeb) return true;
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (_) {
      return false;
    }
  }

  /// User-gesture entry point (Apple requires the prompt to follow a
  /// tap): request browser notification permission and, when granted,
  /// arm the topic subscriptions.  Returns whether push ended up armed.
  Future<bool> enableWebPush() async {
    if (!kIsWeb) return true;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return false;
      }
      await syncWebPush();
      return true;
    } catch (e) {
      debugPrint('NotificationService.enableWebPush failed: $e');
      return false;
    }
  }

  /// Re-apply the persisted topic choices through the engine proxy for
  /// this browser's current registration token.  Safe to call anytime:
  /// silently does nothing until permission is granted, the repo is
  /// attached, and a VAPID key was baked into the build.
  Future<void> syncWebPush() async {
    if (!kIsWeb) return;
    final repo = _repo;
    if (repo == null || kFcmVapidKey.isEmpty) return;
    try {
      if (!await webPushGranted()) return;
      final token =
          await FirebaseMessaging.instance.getToken(vapidKey: kFcmVapidKey);
      if (token == null || token.isEmpty) return;
      for (final topic in const [topicAlerts, topicSignals]) {
        if (await isTopicEnabled(topic)) {
          await repo.subscribeWebPushTopic(token: token, topic: topic);
        } else {
          await repo.unsubscribeWebPushTopic(token: token, topic: topic);
        }
      }
    } catch (e) {
      // Non-fatal by design: a failed arm is retried on next shell mount,
      // exactly like the Android boot loop converges after an offline boot.
      debugPrint('NotificationService.syncWebPush failed (non-fatal): $e');
    }
  }

  // ------------------------------------------------------------------
  // Topic preference API (Settings → Notifications)
  // ------------------------------------------------------------------

  Future<bool> isTopicEnabled(String topic) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefKeyPrefix$topic') ?? true;
  }

  /// Flip one topic.  Persist first so the choice survives even when
  /// the FCM call fails offline (the boot-time re-apply converges).
  Future<void> setTopicEnabled(String topic, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefKeyPrefix$topic', enabled);
    try {
      if (kIsWeb) {
        // Engine-proxied on web; getToken is cheap (cached by the SDK).
        final repo = _repo;
        if (repo == null || kFcmVapidKey.isEmpty) return;
        if (!await webPushGranted()) return;
        final token =
            await FirebaseMessaging.instance.getToken(vapidKey: kFcmVapidKey);
        if (token == null || token.isEmpty) return;
        if (enabled) {
          await repo.subscribeWebPushTopic(token: token, topic: topic);
        } else {
          await repo.unsubscribeWebPushTopic(token: token, topic: topic);
        }
        return;
      }
      final messaging = FirebaseMessaging.instance;
      if (enabled) {
        await messaging.subscribeToTopic(topic);
      } else {
        await messaging.unsubscribeFromTopic(topic);
      }
    } catch (e) {
      debugPrint('NotificationService.setTopicEnabled($topic) failed: $e');
    }
  }

  // ------------------------------------------------------------------
  // Message handling
  // ------------------------------------------------------------------

  void _onForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title;
    if (title == null || title.isEmpty) return;
    final route = message.data['route'] as String?;
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: route == null
            ? null
            : SnackBarAction(
                label: 'VIEW',
                onPressed: () => _emitRoute(route),
              ),
      ),
    );
  }

  void _routeFromMessage(RemoteMessage message) {
    final route = message.data['route'] as String?;
    if (route != null && route.isNotEmpty) _emitRoute(route);
  }

  void _emitRoute(String route) {
    // Re-emit even for an identical consecutive route: consumers reset
    // the notifier to null after handling.
    pendingRoute.value = null;
    pendingRoute.value = route;
  }
}
