/// Guest mode helpers (owner, 2026-09-25).
///
/// A visitor browses as an anonymous guest (see `AuthService.isGuest`).  The
/// engine serves a guest closed signals, pulse, charts and the track record,
/// and refuses everything per-user.  Anything that needs an account renders
/// [AccountRequiredView] instead of calling an endpoint that would only
/// refuse, so a guest meets an invitation rather than an error.
library;

import 'package:flutter/material.dart';

import '../../../data/app_config.dart';
import '../../../shared/tokens.dart';
import '../pages/phone_signin_page.dart';

/// True when the current session is an anonymous guest.  Mock / preview
/// scopes have no auth and are never guests.
bool isGuestSession(BuildContext context) => AppConfigScope.maybeOf(context)?.auth?.isGuest ?? false;

/// Open phone sign-in on top of the current screen.  On success the OTP
/// page replaces the stack with a fresh NavShell for the new account.
void openCreateAccount(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const PhoneSignInPage()),
  );
}

/// Full-page invitation shown where a guest would otherwise hit a
/// per-user screen.
class AccountRequiredView extends StatelessWidget {
  const AccountRequiredView({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.person_add_alt_1_outlined,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(LuminSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A soft glowing badge rather than a bare glyph floating in
            // empty space (UX review 2026-09-25).
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: LuminColors.accent.withValues(alpha: 0.10),
                border: Border.all(color: LuminColors.accent.withValues(alpha: 0.35)),
                boxShadow: [
                  BoxShadow(
                    color: LuminColors.accent.withValues(alpha: 0.18),
                    blurRadius: 32,
                  ),
                ],
              ),
              child: Icon(icon, size: 40, color: LuminColors.accent),
            ),
            const SizedBox(height: LuminSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: LuminSpacing.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: LuminSpacing.xl),
            // Full-width like the welcome screen's primary action, capped so
            // it does not stretch across a tablet.
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: LuminColors.accent,
                  foregroundColor: LuminColors.bgDeep,
                  padding: const EdgeInsets.symmetric(
                    horizontal: LuminSpacing.xl,
                    vertical: LuminSpacing.lg,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(LuminRadii.md),
                  ),
                ),
                onPressed: () => openCreateAccount(context),
                child: const Text(
                  'Create free account',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: LuminSpacing.sm),
            const Text(
              'New accounts get 3 days of live signals free.',
              style: TextStyle(color: LuminColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
