/// No `State.initState` may reach an inherited-widget lookup (2026-09-26).
///
/// `X.of(context)` during initState is an assert failure in debug builds and
/// compiled out of release ones — so a page that does it works in production
/// and silently takes its failure branch everywhere a developer or a test
/// looks. Two pages did, both wrapped in a `catch` that turned the assert into
/// an ordinary-looking state:
///
/// * the Binance connect page read "not connected" for a connected user;
/// * the agent detail sheet opened on its error state, under a comment saying
///   the lookup was safe.
///
/// Derived from `lib/`, so tomorrow's page is covered without editing a list.
/// It follows one level of calls (`initState` → `_load()` → a lookup before
/// the first `await` suspends, its operand included), which is the shape
/// both defects had; work deferred with
/// `addPostFrameCallback` / `Future.microtask` / `scheduleMicrotask` is exempt.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Removes `//` and `/* */` comments, leaving string literals intact.
String stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  String? quote; // current string delimiter: ', ", ''' or """
  while (i < src.length) {
    if (quote != null) {
      if (quote.length == 1 && src[i] == r'\') {
        out.write(src.substring(i, (i + 2).clamp(0, src.length)));
        i += 2;
        continue;
      }
      if (src.startsWith(quote, i)) {
        out.write(quote);
        i += quote.length;
        quote = null;
        continue;
      }
      out.write(src[i]);
      i++;
      continue;
    }
    if (src.startsWith("'''", i) || src.startsWith('"""', i)) {
      quote = src.substring(i, i + 3);
      out.write(quote);
      i += 3;
      continue;
    }
    if (src[i] == "'" || src[i] == '"') {
      quote = src[i];
      out.write(quote);
      i++;
      continue;
    }
    if (src.startsWith('//', i)) {
      final nl = src.indexOf('\n', i);
      i = nl < 0 ? src.length : nl;
      continue;
    }
    if (src.startsWith('/*', i)) {
      final end = src.indexOf('*/', i + 2);
      i = end < 0 ? src.length : end + 2;
      continue;
    }
    out.write(src[i]);
    i++;
  }
  return out.toString();
}

/// Index just past the bracket that closes the one at [open].
int _closing(String s, int open) {
  final o = s[open];
  final c = o == '(' ? ')' : '}';
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == o) depth++;
    if (s[i] == c && --depth == 0) return i + 1;
  }
  return s.length;
}

String _withoutDeferred(String body) {
  var s = body;
  for (final call in const [
    'addPostFrameCallback(',
    'Future.microtask(',
    'scheduleMicrotask(',
  ]) {
    var at = s.indexOf(call);
    while (at >= 0) {
      final open = at + call.length - 1;
      s = s.substring(0, at) + s.substring(_closing(s, open));
      at = s.indexOf(call);
    }
  }
  return s;
}

final _lookup = RegExp(r'\b\w+\.(?:of|maybeOf)\(\s*context\b');

/// Every way [src] reaches an inherited lookup synchronously from initState.
List<String> initStateLookups(String src) {
  final code = stripComments(src);
  final found = <String>[];
  for (final m in RegExp(r'void\s+initState\s*\(\s*\)\s*\{').allMatches(code)) {
    final open = m.end - 1;
    final body = _withoutDeferred(code.substring(open, _closing(code, open)));
    if (_lookup.hasMatch(body)) found.add('initState itself');
    for (final call in RegExp(r'(?<![.\w])(_\w+)\s*\(').allMatches(body)) {
      final name = call.group(1)!;
      final def = RegExp('(?:Future<[^>]*>|void|[A-Z]\\w*)\\??\\s+'
              '${RegExp.escape(name)}\\s*\\([^)]*\\)\\s*(?:async\\s*)?\\{')
          .firstMatch(code);
      if (def == null) continue;
      final fOpen = def.end - 1;
      final fBody = code.substring(fOpen, _closing(code, fOpen));
      // Synchronous up to the first await's OPERAND inclusive — the operand
      // is evaluated before the await suspends. `await X.of(context).y()` is
      // exactly the shape the Binance connect page had.
      final firstAwait = RegExp(r'\bawait\b').firstMatch(fBody);
      final syncPart = firstAwait == null
          ? fBody
          : fBody.substring(0, () {
              final semi = fBody.indexOf(';', firstAwait.end);
              return semi < 0 ? fBody.length : semi;
            }());
      if (_lookup.hasMatch(_withoutDeferred(syncPart))) {
        found.add('$name() before its first await');
      }
    }
  }
  return found;
}

void main() {
  group('the scanner', () {
    test('flags a direct lookup and one reached through a helper', () {
      expect(initStateLookups('''
        class A { void initState() { super.initState(); Theme.of(context); } }
      '''), ['initState itself']);
      expect(initStateLookups('''
        class A {
          void initState() { super.initState(); _load(); }
          Future<void> _load() async { final r = AppConfigScope.of(context).repo; await r.x(); }
        }
      '''), ['_load() before its first await']);
      // The operand of the first await runs before it suspends.
      expect(initStateLookups('''
        class A {
          void initState() { super.initState(); _refresh(); }
          Future<void> _refresh() async {
            try { final s = await AppConfigScope.of(context).repo.status(); } catch (_) {}
          }
        }
      '''), ['_refresh() before its first await']);
    });

    test('exempts deferred work, lookups after an await, and comments', () {
      expect(initStateLookups('''
        class A {
          void initState() {
            super.initState();
            // AppConfigScope.of(context) would be wrong here
            WidgetsBinding.instance.addPostFrameCallback((_) { _load(); X.of(context); });
            _later();
          }
          Future<void> _load() async { X.of(context); }
          Future<void> _later() async { await Future.value(); X.of(context); }
          void didChangeDependencies() { X.of(context); }
        }
      '''), isEmpty);
    });
  });

  test('no initState in lib/ reaches an inherited-widget lookup', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final hit in initStateLookups(f.readAsStringSync())) {
        offenders.add('${f.path}: $hit');
      }
    }
    expect(offenders, isEmpty,
        reason: 'move the read to didChangeDependencies or a post-frame '
            'callback — in a debug build it throws, and a catch around it '
            'turns the throw into a plausible-looking state');
  });
}
