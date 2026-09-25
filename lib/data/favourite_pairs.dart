/// Favourite pairs for the Markets list — on-device only.
///
/// A star is a personal bookmark, not account data: it lives in
/// SharedPreferences, costs the engine nothing, and works for a guest.
/// Load failures read as "no favourites" rather than breaking the list.
library;

import 'package:shared_preferences/shared_preferences.dart';

class FavouritePairs {
  FavouritePairs._();

  static const String _key = 'markets.favourites';

  static Future<Set<String>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return (p.getStringList(_key) ?? const <String>[]).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> save(Set<String> symbols) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_key, symbols.toList()..sort());
    } catch (_) {/* a lost star is not worth an error dialog */}
  }
}
