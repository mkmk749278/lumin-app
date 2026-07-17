/// Canonical legal-document URLs.
///
/// **Single source of truth** for the Play Store-required legal
/// surfaces (Privacy Policy + Terms of Service + Risk Disclosure).
/// Referenced from:
///
/// * Settings → Legal section (A5) — each row opens the corresponding
///   URL in the device browser via ``url_launcher``.
/// * Play Console listing — Privacy Policy URL field is mandatory;
///   we set it to [privacyUrl].
/// * In-app first-run consent gate (A1+A2, PR #51) — links to these
///   URLs from the consent screen (future PR adds the inline links).
///
/// Hosted in a separate ``lumin-legal`` GitHub repo so updates to
/// legal copy don't require an app rebuild — the URLs are stable and
/// the markdown content can be revised via a normal GitHub push.
///
/// **Why constants vs. fetched from a remote config:** the legal
/// URLs MUST be available even when the engine API is unreachable
/// (the user might be tapping "Privacy Policy" before sign-in, or
/// during a backend outage).  Constants in the binary guarantee
/// availability; the markdown content itself is what evolves.
library;

class LegalUrls {
  LegalUrls._();

  /// Base URL for the lumin-legal GitHub Pages site.  All three
  /// documents live as sibling pages off this root.
  static const String _base = 'https://mkmk749278.github.io/lumin-legal';

  /// Privacy Policy — what data we collect, why, retention, the
  /// user's GDPR / UK-GDPR rights, support contact.  Required URL
  /// for the Play Console listing.
  static const String privacyUrl = '$_base/privacy';

  /// Terms of Service — eligibility, scope of service, Binance API
  /// key responsibilities, risk acknowledgement, limitation of
  /// liability, governing law (Hyderabad, Telangana, India).
  static const String termsUrl = '$_base/terms';

  /// Risk Disclosure — separate from ToS; the explicit "you may
  /// lose all funds, past performance does not guarantee future
  /// results, leverage amplifies both directions" warning that
  /// Cornix / 3Commas / Bitsgap all surface as a standalone doc.
  static const String riskUrl = '$_base/risk';

  /// Support contact — the same address published in the legal docs
  /// (privacy §12 / terms §13).  Every in-app "contact support"
  /// surface routes here; Telegram is banned in-region and must never
  /// be presented as the support channel.
  static const String supportEmail = 'mulakapati446@gmail.com';

  /// `mailto:` URI for [supportEmail] with an optional prefilled
  /// subject, ready for `url_launcher`.
  static Uri supportMailto({String? subject}) => Uri(
        scheme: 'mailto',
        path: supportEmail,
        query: subject == null || subject.isEmpty
            ? null
            : 'subject=${Uri.encodeComponent(subject)}',
      );
}
