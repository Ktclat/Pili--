import 'package:PiliPlus/common/constants.dart';
import 'package:pub_semver/pub_semver.dart';

enum AndroidUpgradeStatus {
  verified,
  signerMismatch,
  packageMismatch,
  unsupportedAbi,
  unavailable,
  notNewer,
}

class AndroidUpgradeResult {
  const AndroidUpgradeResult(this.status)
    : assert(status != AndroidUpgradeStatus.verified),
      downloadUrl = null;

  const AndroidUpgradeResult.verified(String url)
    : status = AndroidUpgradeStatus.verified,
      downloadUrl = url;

  final AndroidUpgradeStatus status;
  final String? downloadUrl;
}

/// The public stable release selected by the repository’s latest channel.
class ReleaseInfo {
  static const _abis = {'arm64-v8a', 'armeabi-v7a', 'x86_64'};
  static const _androidPackage = 'io.github.ktclat.piliminus';
  static final _sha256Pattern = RegExp(r'^[a-fA-F0-9]{64}$');

  final Map<String, dynamic> data;
  final Version version;

  const ReleaseInfo._(this.data, this.version);

  static ReleaseInfo? fromLatest(Object? response) {
    if (response is! Map<String, dynamic> ||
        response['draft'] != false ||
        response['prerelease'] != false) {
      return null;
    }
    final tag = response['tag_name'];
    if (tag is! String || !RegExp(r'^v[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(tag)) {
      return null;
    }
    try {
      final version = Version.parse(tag.substring(1));
      return tag == 'v${version.canonicalizedVersion}'
          ? ReleaseInfo._(response, version)
          : null;
    } on FormatException {
      return null;
    }
  }

  String get pageUrl => '${Constants.sourceCodeUrl}/releases/tag/v$version';

  Iterable<Map> get _assets sync* {
    final assets = data['assets'];
    if (assets is List) {
      for (final item in assets) {
        if (item is Map &&
            item['state'] == 'uploaded' &&
            item['name'] is String) {
          yield item;
        }
      }
    }
  }

  Iterable<String> get _assetNames =>
      _assets.map((asset) => asset['name'] as String);

  Map? _uniqueAsset(String name) =>
      _assets.where((asset) => asset['name'] == name).singleOrNull;

  static String? _assetSha256(Map? asset) {
    final digest = asset?['digest'];
    return digest is String && digest.startsWith('sha256:')
        ? _sha256Hex(digest.substring('sha256:'.length))
        : null;
  }

  Iterable<int?> get _androidArchiveCodes sync* {
    final archive = RegExp(
      '^PiliMinus-${RegExp.escape(version.toString())}\\+([0-9]+)-source\\.tar\\.gz\$',
    );
    for (final name in _assetNames) {
      final match = archive.firstMatch(name);
      if (match != null) yield int.tryParse(match[1]!);
    }
  }

  Version _installedVersion(String installedVersion) {
    final installed = Version.parse(installedVersion);
    return Version(
      installed.major,
      installed.minor,
      installed.patch,
      pre: installed.isPreRelease ? installed.preRelease.join('.') : null,
    );
  }

  bool isNewerThan(String installedVersion, {int? installedAndroidCode}) {
    final current = _installedVersion(installedVersion);
    final remoteCode = _androidArchiveCodes.singleOrNull;
    if (installedAndroidCode != null && remoteCode != null) {
      return version >= current && remoteCode > installedAndroidCode;
    }
    return version > current;
  }

  String _downloadUrl(String name) =>
      '${Constants.sourceCodeUrl}/releases/download/v$version/${Uri.encodeComponent(name)}';

  String? platformDownloadUrl(String platform, {String? extension}) {
    for (final name in _assetNames) {
      if (name.contains(platform) &&
          (extension == null || name.endsWith('.$extension'))) {
        return _downloadUrl(name);
      }
    }
    return null;
  }

  String? get androidBuildInfoSha256 =>
      _assetSha256(_uniqueAsset('BUILD_INFO.json'));

  String? get androidBuildInfoUrl =>
      androidBuildInfoSha256 == null ? null : _downloadUrl('BUILD_INFO.json');

  static String? _sha256Hex(Object? value) =>
      value is String && _sha256Pattern.hasMatch(value)
      ? value.toLowerCase()
      : null;

  // BUILD_INFO.json is generated from the same APKs the release workflow uploads.
  ({int code, String signer, Set<String> abis})? _androidBuild(
    Object? manifest,
  ) {
    if (androidBuildInfoUrl == null ||
        manifest is! Map ||
        manifest['schema_version'] is! int ||
        manifest['schema_version'] != 1 ||
        manifest['release_tag'] != 'v$version' ||
        manifest['prerelease'] != false) {
      return null;
    }
    final signing = manifest['signing'];
    final records = manifest['apks'];
    final releaseVersion = manifest['version'];
    if (signing is! Map ||
        signing['pinned_distribution_signer'] != true ||
        records is! List ||
        records.isEmpty ||
        releaseVersion is! String) {
      return null;
    }
    final signer = _sha256Hex(signing['certificate_sha256']);
    final code = int.tryParse(releaseVersion.split('+').last);
    final archiveCodes = _androidArchiveCodes.toList();
    if (signer == null ||
        code == null ||
        code < 1 ||
        code > 2100000000 ||
        releaseVersion != '$version+$code' ||
        (archiveCodes.isNotEmpty && archiveCodes.singleOrNull != code)) {
      return null;
    }

    final recordedAbis = <String>{};
    for (final record in records) {
      if (record is! Map) return null;
      final abi = record['abi'];
      if (abi is! String) return null;
      if (!_abis.contains(abi)) continue;
      final file = 'PiliMinus-$abi.apk';
      final digest = _assetSha256(_uniqueAsset(file));
      if (recordedAbis.contains(abi) ||
          record['file'] != file ||
          record['application_id'] != _androidPackage ||
          record['version_name'] != version.toString() ||
          record['version_code'] is! int ||
          record['version_code'] != code ||
          _sha256Hex(record['signer_certificate_sha256']) != signer ||
          digest == null ||
          _sha256Hex(record['sha256']) != digest) {
        return null;
      }
      recordedAbis.add(abi);
    }
    for (final abi in _abis) {
      if (!recordedAbis.contains(abi) &&
          _assetNames.contains('PiliMinus-$abi.apk')) {
        return null;
      }
    }

    return (code: code, signer: signer, abis: recordedAbis);
  }

  AndroidUpgradeResult checkAndroidUpgrade(
    Object? manifest, {
    required String installedPackage,
    required String installedSignature,
    required String installedVersion,
    required int? installedCode,
    required Iterable<String> supportedAbis,
  }) {
    const unavailable = AndroidUpgradeResult(AndroidUpgradeStatus.unavailable);
    final build = _androidBuild(manifest);
    final localSigner = _sha256Hex(installedSignature);
    if (build == null ||
        localSigner == null ||
        installedCode == null ||
        installedCode < 1 ||
        installedPackage.isEmpty) {
      return unavailable;
    }
    try {
      if (version < _installedVersion(installedVersion) ||
          build.code <= installedCode) {
        return const AndroidUpgradeResult(AndroidUpgradeStatus.notNewer);
      }
    } on FormatException {
      return unavailable;
    }
    if (installedPackage != _androidPackage) {
      return const AndroidUpgradeResult(AndroidUpgradeStatus.packageMismatch);
    }
    if (localSigner != build.signer) {
      return const AndroidUpgradeResult(AndroidUpgradeStatus.signerMismatch);
    }
    for (final abi in supportedAbis) {
      if (build.abis.contains(abi)) {
        return AndroidUpgradeResult.verified(
          _downloadUrl('PiliMinus-$abi.apk'),
        );
      }
    }
    return const AndroidUpgradeResult(AndroidUpgradeStatus.unsupportedAbi);
  }
}
