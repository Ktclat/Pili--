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
        release('v01.0.0'),
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

  group('Android upgrade verification', () {
    const version = '0.6.3';
    const tag = 'v0.6.3';
    const package = 'io.github.ktclat.piliminus';
    final pin = 'ab' * 32;
    final otherPin = 'cd' * 32;
    const abis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

    Map<String, Object?> apk(String abi) => {
      'abi': abi,
      'file': 'PiliMinus-$abi.apk',
      'application_id': package,
      'version_name': version,
      'version_code': 10,
      'signer_certificate_sha256': pin,
      'sha256': 'ad' * 32,
    };

    Map<String, Object?> manifest() => {
      'schema_version': 1,
      'release_tag': tag,
      'prerelease': false,
      'version': '$version+10',
      'signing': {
        'pinned_distribution_signer': true,
        'certificate_sha256': pin,
      },
      'apks': abis.map(apk).toList(),
    };

    final assets = [
      asset('PiliMinus-$version+10-source.tar.gz'),
      for (final name in [
        'BUILD_INFO.json',
        ...abis.map((a) => 'PiliMinus-$a.apk'),
      ])
        {
          ...asset(name),
          'digest': 'sha256:${'ad' * 32}',
          'browser_download_url': 'https://unrelated.example/$name',
        },
    ];
    ReleaseInfo latest([List<Map<String, String>>? files]) =>
        ReleaseInfo.fromLatest(release(tag, assets: files ?? assets))!;

    AndroidUpgradeResult check(
      Object? metadata, {
      ReleaseInfo? release,
      String? signature,
      String installedVersion = '0.6.2',
      int? code = 9,
      String installedPackage = package,
      List<String> deviceAbis = abis,
    }) => (release ?? latest()).checkAndroidUpgrade(
      metadata,
      installedPackage: installedPackage,
      installedSignature: signature ?? pin.toUpperCase(),
      installedVersion: installedVersion,
      installedCode: code,
      supportedAbis: deviceAbis,
    );

    void expectStatus(
      AndroidUpgradeResult result,
      AndroidUpgradeStatus status,
    ) {
      expect(result.status, status);
      expect(result.downloadUrl, isNull);
    }

    test('uses the exact release and ABI preference, keeping digest case independent', () {
      const base = 'https://github.com/Ktclat/Pili--/releases/download/$tag';
      expect(latest().androidBuildInfoUrl, '$base/BUILD_INFO.json');
      expect(latest().androidBuildInfoSha256, 'ad' * 32);
      for (final preferred in abis) {
        final result = check(
          manifest(),
          deviceAbis: ['unknown', preferred, ...abis],
        );
        expect(result.status, AndroidUpgradeStatus.verified);
        expect(result.downloadUrl, '$base/PiliMinus-$preferred.apk');
      }
      expectStatus(
        check(manifest(), deviceAbis: ['mips']),
        AndroidUpgradeStatus.unsupportedAbi,
      );
      expectStatus(
        check(manifest(), deviceAbis: []),
        AndroidUpgradeStatus.unsupportedAbi,
      );
    });

    test('rejects missing or duplicated metadata, alternate names and partial uploads', () {
      for (final files in [
        assets.where((a) => a['name'] != 'BUILD_INFO.json').toList(),
        [...assets, asset('BUILD_INFO.json')],
        [
          asset('BUILD_INFO.json.bak'),
          {'name': 'BUILD_INFO.json', 'state': 'open'},
        ],
      ]) {
        final release = latest(files);
        expect(release.androidBuildInfoUrl, isNull);
        expect(release.androidBuildInfoSha256, isNull);
        expectStatus(
          check(manifest(), release: release),
          AndroidUpgradeStatus.unavailable,
        );
      }
      for (final files in [
        [...assets, asset('PiliMinus-arm64-v8a.apk')],
        assets.where((a) => a['name'] != 'PiliMinus-arm64-v8a.apk').toList(),
        assets
            .map(
              (a) => a['name'] == 'PiliMinus-x86_64.apk'
                  ? asset('PiliMinus-x86_64-test-signed.apk')
                  : a,
            )
            .toList(),
        [...assets, asset('PiliMinus-$version+11-source.tar.gz')],
        assets
            .map(
              (a) => a['name']!.endsWith('.tar.gz')
                  ? asset('PiliMinus-$version+11-source.tar.gz')
                  : a,
            )
            .toList(),
      ]) {
        expectStatus(
          check(manifest(), release: latest(files)),
          AndroidUpgradeStatus.unavailable,
        );
      }
    });

    test('checks the exact manifest and each published APK asset digest', () {
      for (final invalid in ['', 'sha512:${'ad' * 32}', 'sha256:bork']) {
        final files = [
          for (final file in assets)
            if (file['name'] == 'BUILD_INFO.json')
              {...file, 'digest': invalid}
            else
              file,
        ];
        final release = latest(files);
        expect(release.androidBuildInfoSha256, isNull);
        expect(release.androidBuildInfoUrl, isNull);
        expectStatus(
          check(manifest(), release: release),
          AndroidUpgradeStatus.unavailable,
        );
      }
      for (final changed in [
        {'name': 'PiliMinus-arm64-v8a.apk', 'state': 'uploaded'},
        {
          'name': 'PiliMinus-arm64-v8a.apk',
          'state': 'uploaded',
          'digest': 'sha256:${'ee' * 32}',
        },
      ]) {
        final files = [
          for (final file in assets)
            if (file['name'] == changed['name']) changed else file,
        ];
        expectStatus(
          check(manifest(), release: latest(files)),
          AndroidUpgradeStatus.unavailable,
        );
      }
    });

    test('rejects incomplete, conflicting, or unpinned build manifests', () {
      final valid = manifest();
      for (final input in <Object?>[
        null,
        [],
        {},
        {...valid, 'schema_version': 2},
        {...valid, 'release_tag': 'v0.6.4'},
        {...valid, 'prerelease': true},
        {...valid, 'version': '0.6.4+10'},
        {...valid, 'version': '0.6.3+0'},
        {...valid, 'version': '0.6.3+2100000001'},
        {
          ...valid,
          'signing': {
            'certificate_sha256': pin,
            'pinned_distribution_signer': false,
          },
        },
        {
          ...valid,
          'signing': {
            'certificate_sha256': 'invalid',
            'pinned_distribution_signer': true,
          },
        },
        {...valid, 'apks': []},
        {
          ...valid,
          'apks': [apk(abis.first)],
        },
        {
          ...valid,
          'apks': [...abis.map(apk), apk(abis.first)],
        },
        for (final inconsistent in [
          {'abi': 'invalid'},
          {'file': 'https://unrelated.example/download.apk'},
          {'signer_certificate_sha256': otherPin},
          {'sha256': null},
          {'sha256': 'wrong'},
          {'version_code': '10'},
          {'version_code': 9},
          {'version_name': '0.6.2'},
          {'application_id': 'com.example.piliplus'},
        ])
          {
            ...valid,
            'apks': [
              apk(abis.first),
              apk(abis[1]),
              {...apk(abis.last), ...inconsistent},
            ],
          },
      ]) {
        expectStatus(check(input), AndroidUpgradeStatus.unavailable);
      }
    });

    test(
      'returns distinct reasons without an APK URL for unrelated installations',
      () {
        expectStatus(
          check(manifest(), signature: otherPin),
          AndroidUpgradeStatus.signerMismatch,
        );
        expectStatus(
          check(manifest(), installedPackage: '$package.dev'),
          AndroidUpgradeStatus.packageMismatch,
        );
        for (final missing in ['', 'oops', pin.substring(1)]) {
          expectStatus(
            check(manifest(), signature: missing),
            AndroidUpgradeStatus.unavailable,
          );
        }
        expectStatus(
          check(manifest(), code: null),
          AndroidUpgradeStatus.unavailable,
        );
        expectStatus(
          check(manifest(), installedVersion: 'unknown'),
          AndroidUpgradeStatus.unavailable,
        );
      },
    );

    test(
      'requires increasing versionCode and prevents semantic downgrades',
      () {
        for (final release in [
          latest(),
          latest(assets.where((a) => !a['name']!.endsWith('.tar.gz')).toList()),
        ]) {
          for (final existing in [10, 11]) {
            expectStatus(
              check(manifest(), code: existing, release: release),
              AndroidUpgradeStatus.notNewer,
            );
          }
          expectStatus(
            check(manifest(), installedVersion: '0.7.0', release: release),
            AndroidUpgradeStatus.notNewer,
          );
          expect(
            check(
              manifest(),
              installedVersion: '0.6.3+9',
              release: release,
            ).status,
            AndroidUpgradeStatus.verified,
          );
        }
      },
    );
  });
}
