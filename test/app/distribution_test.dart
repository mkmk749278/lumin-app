/// Distribution-flag guard. The default (no --dart-define) must remain
/// **sideload** so existing GitHub-Releases builds keep their self-updater.
/// Play builds flip LUMIN_DISTRIBUTION=play, which disables it.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/app/distribution.dart';

void main() {
  test('defaults to sideload when no dart-define is set', () {
    expect(kDistribution, AppDistribution.sideload);
  });

  test('self-update is enabled on the default (sideload) build', () {
    expect(kSelfUpdateEnabled, isTrue);
  });

  test('self-update enabled iff sideload channel', () {
    expect(kSelfUpdateEnabled, kDistribution == AppDistribution.sideload);
  });
}
