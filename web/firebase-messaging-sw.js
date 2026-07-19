/* Lumin — FCM background-delivery service worker (web/PWA channel,
 * 2026-07-18).  The firebase_messaging web plugin registers this file
 * (fixed name, web root) when the app first calls getToken; the browser
 * then wakes it for pushes that arrive while the app is closed — the
 * web analogue of Android rendering notification payloads natively.
 *
 * The <FIREBASE_*> placeholders are substituted by CI's build-web job
 * from the FIREBASE_WEB_CONFIG secret (same source as the
 * firebase_options.dart web block).  An undeployed/placeholder copy
 * fails initializeApp harmlessly: foreground push still works, and the
 * console shows the misconfiguration loudly.
 *
 * compat builds are deliberate: FCM's SW-side API surface is only
 * published for the compat namespace, and importScripts is the only
 * dependable module system across the SW engines we target (iOS 16.4+
 * Safari included).
 */
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: '<FIREBASE_API_KEY>',
  appId: '<FIREBASE_APP_ID>',
  messagingSenderId: '<FIREBASE_SENDER_ID>',
  projectId: '<FIREBASE_PROJECT_ID>',
  authDomain: '<FIREBASE_AUTH_DOMAIN>',
  storageBucket: '<FIREBASE_STORAGE_BUCKET>',
});

/* Instantiating messaging is what arms background delivery — the
 * engine's pushes carry notification payloads, so the SDK renders them
 * without a custom onBackgroundMessage handler (mirrors the Android
 * contract: display is payload-driven, muting is topic-driven). */
firebase.messaging();

/* Tap → focus an open Lumin tab (or open one), landing on the pushed
 * route.  The data.route value (pulse_alerts | signals) is the same
 * contract NavShell consumes via getInitialMessage on cold start. */
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((wins) => {
      for (const win of wins) {
        if ('focus' in win) return win.focus();
      }
      return clients.openWindow('/');
    })
  );
});
