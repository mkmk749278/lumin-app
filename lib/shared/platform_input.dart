/// Platform rules for text-input behaviour that differ between the native
/// Android build and the web (PWA) channel.
library;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Whether a screen may open with a text field already focused.
///
/// Native: yes — `autofocus: true` puts the keyboard up the moment the
/// sign-in / OTP / search screen appears, which is the behaviour the app
/// shipped with and what users expect on Android.
///
/// Web: no (2026-07-26 iPhone setup-screen fix).  Browsers only raise the
/// on-screen keyboard from inside a user-gesture handler.  Flutter's web
/// text-input backend still moves focus to its hidden `<input>` when a
/// field autofocuses at mount, so on iOS Safari the app believed the field
/// was focused while the user saw no keyboard; their first tap went into
/// resolving that mismatch instead of pressing what they aimed at.  That is
/// half of the "have to tap it twice" report on the setup screens — the
/// phone-number field, the OTP field and both country-picker search fields
/// all autofocus.  Letting the user's own tap focus the field keeps the
/// keyboard inside a real gesture, where Safari honours it.
///
/// Deliberately keyed on [kIsWeb] rather than on an iOS user-agent probe:
/// the gesture requirement is a browser rule, not an Apple one, and Chrome
/// on Android enforces it too.
const bool kAutofocusTextFields = !kIsWeb;
