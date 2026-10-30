import 'package:PiliPlus/utils/release_info.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> release(
  String tag, {
  bool draft = false,
  bool prerelease = false,
  String createdAt = '2026-01-01T00:00:00Z',
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'created_at': createdAt,
};

void main() {
  test(
    'selects highest stable version regardless of release order or date',
    () {
      final latest = ReleaseInfo.latestStable([
        release('v0.1.9', createdAt: '2026-10-27T00:00:00Z'),
        release('v0.1.10', createdAt: '2026-01-01T00:00:00Z'),
        release('0.1.8'),
      ]);

      expect(latest?.data['tag_name'], 'v0.1.10');
      expect(latest?.isNewerThan('0.1.9'), isTrue);
    },
  );

  test('ignores draft, prerelease, malformed tags and malformed entries', () {
    final latest = ReleaseInfo.latestStable([
      release('v9.0.0', draft: true),
      release('v8.0.0', prerelease: true),
      release('v7.0.0-beta.1'),
      release('SNAPSHOT'),
      {'tag_name': null},
      null,
      'invalid entry',
      release('v0.1.1'),
    ]);

    expect(latest?.data['tag_name'], 'v0.1.1');
  });

  test('empty or prerelease-only repositories have no stable release', () {
    expect(ReleaseInfo.latestStable([]), isNull);
    expect(
      ReleaseInfo.latestStable([release('v0.2.0-rc.1')]),
      isNull,
    );
  });

  test(
    'same or older release never prompts an update, including local builds',
    () {
      final latest = ReleaseInfo.latestStable([release('v0.1.1+999')])!;

      expect(latest.isNewerThan('0.1.1'), isFalse);
      expect(latest.isNewerThan('0.1.1+2'), isFalse);
      expect(latest.isNewerThan('0.1.2'), isFalse);
      expect(latest.isNewerThan('0.1.0'), isTrue);
    },
  );

  test('stable release upgrades a prerelease of the same version', () {
    final latest = ReleaseInfo.latestStable([release('v0.2.0')])!;

    expect(latest.isNewerThan('0.2.0-rc.1'), isTrue);
    expect(latest.isNewerThan('0.3.0-rc.1'), isFalse);
  });

  test(
    'unreadable installed version fails instead of suggesting a downgrade',
    () {
      final latest = ReleaseInfo.latestStable([release('v0.1.1')])!;

      expect(() => latest.isNewerThan('SNAPSHOT'), throwsFormatException);
    },
  );
}
