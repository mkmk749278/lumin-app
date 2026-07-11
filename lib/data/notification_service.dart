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
/// Display contract:
///   * Background / killed — the engine sends notification-payload
///     messages, so Android renders them without any app code (FCM's
///     default notification channel; per-class muting happens via our
///     topic toggles, which stop delivery entirely — stronger than an
///     OS channel mute).
///   * Foreground — `onMessage` never auto-displays; we surface a
///     one-line SnackBar with a VIEW action instead of a heads-up so
///     the user isn't double-notified about a screen they're inside.
///   * Tap — `data.route` (`pulse_alerts` | `signals`) lands in
///     [pendingRoute]; NavShell + PulsePage listen and switch tabs.
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Boot-time init.  Never throws — push is a convenience layer and a
  /// Firebase/Play-Services hiccup must not block app start.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      final messaging = FirebaseMessaging.instance;

      // Android 13+ runtime permission (needs POST_NOTIFICATIONS in the
      // manifest — injected by the CI build).  On earlier Android this
      // resolves as granted without UI.
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
