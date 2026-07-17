/// EngineMetadataStore — persistence behind the 2026-07-17 restart fix.
///
/// The store is the reason a paying subscriber keeps their tier across
/// an app restart, so these tests pin the three behaviours the fix
/// depends on: round-trip fidelity, per-UID isolation (no entitlement
/// leaking between accounts on a shared device), and corrupt-entry
/// tolerance (a bad blob degrades to "not yet known", never a crash).
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/engine_metadata_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('round-trips full metadata', () async {
    const meta = EngineMetadata(
      userId: 42,
      tier: 'auto',
      paidUntil: '2026-08-17T00:00:00Z',
      needsOnboarding: false,
      displayName: 'Kishore',
    );
    await EngineMetadataStore.save('uidA', meta);
    final back = await EngineMetadataStore.load('uidA');
    expect(back, isNotNull);
    expect(back!.userId, 42);
    expect(back.tier, 'auto');
    expect(back.paidUntil, '2026-08-17T00:00:00Z');
    expect(back.needsOnboarding, false);
    expect(back.displayName, 'Kishore');
  });

  test('round-trips sparse metadata (nulls preserved)', () async {
    const meta = EngineMetadata(tier: 'assist');
    await EngineMetadataStore.save('uidA', meta);
    final back = await EngineMetadataStore.load('uidA');
    expect(back!.tier, 'assist');
    expect(back.userId, isNull);
    expect(back.paidUntil, isNull);
    expect(back.displayName, isNull);
    expect(back.needsOnboarding, false);
  });

  test('isolates entries per Firebase UID', () async {
    await EngineMetadataStore.save('uidA', const EngineMetadata(tier: 'auto'));
    await EngineMetadataStore.save('uidB', const EngineMetadata(tier: 'free'));
    expect((await EngineMetadataStore.load('uidA'))!.tier, 'auto');
    expect((await EngineMetadataStore.load('uidB'))!.tier, 'free');
  });

  test('clear removes only the target UID', () async {
    await EngineMetadataStore.save('uidA', const EngineMetadata(tier: 'auto'));
    await EngineMetadataStore.save('uidB', const EngineMetadata(tier: 'assist'));
    await EngineMetadataStore.clear('uidA');
    expect(await EngineMetadataStore.load('uidA'), isNull);
    expect((await EngineMetadataStore.load('uidB'))!.tier, 'assist');
  });

  test('missing entry loads as null', () async {
    expect(await EngineMetadataStore.load('nobody'), isNull);
  });

  test('corrupt entry loads as null instead of throwing', () async {
    SharedPreferences.setMockInitialValues({
      'lumin.engineMeta.uidA': 'not json {{{',
      'lumin.engineMeta.uidB': '[1,2,3]',
    });
    expect(await EngineMetadataStore.load('uidA'), isNull);
    expect(await EngineMetadataStore.load('uidB'), isNull);
  });

  test('empty uid is a safe no-op', () async {
    await EngineMetadataStore.save('', const EngineMetadata(tier: 'auto'));
    expect(await EngineMetadataStore.load(''), isNull);
    await EngineMetadataStore.clear('');
  });
}
