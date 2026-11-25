import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/utils/release_info.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> release(
  String tag, {
  bool draft = false,
  bool prerelease = false,
  List<Map<String, String>> assets = const [],
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'assets': assets,
};

Map<String, String> asset(String name) => {'name': name, 'state': 'uploaded'};

void main() {
  test('checks the managed latest channel and reads the version tag', () {
    expect(
      Api.latestApp,
      'https://api.github.com/repos/Ktclat/Pili--/releases/latest',
    );
    final latest = ReleaseInfo.fromLatest(release('v0.1.10'))!;
    expect(latest.isNewerThan('0.1.9'), isTrue);
    expect(
      latest.pageUrl,
      'https://github.com/Ktclat/Pili--/releases/tag/v0.1.10',
    );
  });

  test(
    'rejects drafts, prereleases, malformed tags and missing release flags',
    () {
      for (final entry in [
        release('v9.0.0', draft: true),
        release('v8.0.0', prerelease: true),
        release('v7.0.0-beta.1'),
        release('SNAPSHOT'),
        release('v1.0.0+10'),
        {'tag_name': 'v1.0.0'},
        null,
        <dynamic>[],
      ]) {
        expect(ReleaseInfo.fromLatest(entry), isNull);
      }
    },
  );

  test(
    'semantic comparison ignores build metadata and handles prereleases',
    () {
      final latest = ReleaseInfo.fromLatest(release('v0.2.0'))!;
      expect(latest.isNewerThan('0.2.0'), isFalse);
      expect(latest.isNewerThan('0.2.0+10'), isFalse);
      expect(latest.isNewerThan('0.3.0'), isFalse);
      expect(latest.isNewerThan('0.2.0-rc.1'), isTrue);
      expect(latest.isNewerThan('0.3.0-rc.1'), isFalse);
      expect(() => latest.isNewerThan('SNAPSHOT'), throwsFormatException);
    },
  );

  test('Android accounts for the installed build when the source archive reports the code', () {
    final latest = ReleaseInfo.fromLatest(
      release('v0.6.2', assets: [asset('PiliMinus-0.6.2+9-source.tar.gz')]),
    )!;
    expect(latest.isNewerThan('0.6.2', installedAndroidCode: 8), isTrue);
    expect(latest.isNewerThan('0.6.2', installedAndroidCode: 9), isFalse);
    expect(latest.isNewerThan('0.6.1', installedAndroidCode: 10), isFalse);
    expect(latest.isNewerThan('0.7.0', installedAndroidCode: 8), isFalse);
  });

  test('Android offers only available fixed APK names in device ABI order', () {
    final latest = ReleaseInfo.fromLatest(
      release(
        'v0.6.2',
        assets: [
          asset('PiliMinus-armeabi-v7a.apk'),
          asset('PiliMinus-arm64-v8a-test-signed.apk'),
          {'name': 'PiliMinus-arm64-v8a.apk', 'state': 'open'},
          asset('PiliMinus-x86_64.apk'),
        ],
      ),
    )!;
    expect(
      latest.androidDownloadUrl(['arm64-v8a', 'armeabi-v7a']),
      'https://github.com/Ktclat/Pili--/releases/download/v0.6.2/PiliMinus-armeabi-v7a.apk',
    );
    expect(
      latest.androidDownloadUrl(['x86_64', 'armeabi-v7a']),
      endsWith('/PiliMinus-x86_64.apk'),
    );
    expect(latest.androidDownloadUrl(['arm64-v8a']), isNull);
    expect(latest.androidDownloadUrl([]), isNull);
  });
}
