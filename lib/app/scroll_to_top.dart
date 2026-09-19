import 'package:flutter/animation.dart';

/// Contract for tab pages that return to the top when their already-active
/// bottom-navigation icon is tapped.
///
/// Why this exists: the five tabs live inside an [IndexedStack] (see
/// `NavShell`), which keeps every visited tab mounted — so a tab the user
/// scrolled deep into is still scrolled deep when they come back to it.
/// Returning to the beginning of a long feed then means dragging back through
/// it by hand, and the bottom bar — the one control already under the user's
/// thumb — did nothing at all when its active icon was tapped.
///
/// Every other mobile app treats the active tab icon as "take me back to the
/// start", so this is not a gesture anyone has to learn; it is the absence of
/// it that reads as broken.
///
/// Why an interface and not a [PrimaryScrollController]: on mobile, every
/// controller-less vertical `ListView` in a subtree attaches itself to an
/// ambient primary controller — including the ones nested inside a page. A
/// primary controller at the shell would therefore scroll a page's inner lists
/// as well as its outer one, and which lists those are changes whenever a page
/// changes. An explicit per-page method says exactly which list moves, and
/// `NavShell` reaches it through the same `GlobalKey` it already holds for
/// [ForegroundRefreshable].
///
/// Implementers own the animation. Use [kScrollToTopDuration] /
/// [kScrollToTopCurve] so all five tabs decelerate identically — a trading app
/// should feel fluid rather than animated, and two tabs that settle differently
/// are noticed even when neither is wrong.
abstract class ScrollToTop {
  /// Return this tab's primary scroll view to offset zero.
  ///
  /// Called by `NavShell` when the user taps the bottom-nav icon of the tab
  /// that is already selected. Implementations must be safe to call when the
  /// page has nothing scrollable mounted yet (a skeleton, an empty state, an
  /// error view): guard on `hasClients` and no-op rather than throwing.
  ///
  /// Called again at the top, this must stay at the top rather than bounce.
  void scrollToTop();
}

/// One duration for every tab's return-to-top.
///
/// 280ms sits in the handoff's "larger movement" band (260-400ms): long enough
/// to read as travel rather than a jump cut, short enough that a user who
/// tapped because they want to act is not waiting on it.
const Duration kScrollToTopDuration = Duration(milliseconds: 280);

/// Fast at the start, gently settling, and — unlike an elastic or bounce curve
/// — it stops exactly at zero. An overshoot at the top of a signal feed reads
/// as the list having more content above it, which it does not.
const Curve kScrollToTopCurve = Curves.easeOutCubic;
