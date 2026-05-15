// PLACEHOLDER — regenerate via
//
//   flutterfire configure --project=<your-project-id>
//
// once the Firebase project exists.  The values below are intentionally
// invalid: `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`
// will throw at runtime until they're replaced with the real project's
// API key / app ID / project ID from the Firebase Console.
//
// The CI build step does NOT yet auto-regenerate this file; that's a
// follow-up wiring task (the FlutterFire CLI needs a service-account
// token to run unattended, which the workflow doesn't have today).
//
// For now this stub exists so the imports in `main.dart` compile and
// the rest of the PR's diff is reviewable in isolation.  Owner
// replaces it pre-merge as part of the pre-merge checklist.
//
// File generated/managed-by: FlutterFire CLI (when run by owner).
// Do not hand-edit the generated version — re-run `flutterfire configure`.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported on this platform. '
          'Re-run `flutterfire configure` once you target it.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
    appId: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
    messagingSenderId: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
    projectId: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
    storageBucket: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
    appId: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
    messagingSenderId: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
    projectId: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
    storageBucket: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
    iosBundleId: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
    appId: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
    messagingSenderId: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
    projectId: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
    authDomain: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
    storageBucket: '<TODO_FILL_FROM_FIREBASE_CONSOLE>',
  );
}
