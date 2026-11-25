import 'package:PiliPlus/common/constants.dart';
import 'package:pub_semver/pub_semver.dart';

/// The public stable release selected by the repository’s latest channel.
class ReleaseInfo {
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
      return ReleaseInfo._(response, Version.parse(tag.substring(1)));
    } on FormatException {
      return null;
    }
  }

  String get pageUrl =>
      '${Constants.sourceCodeUrl}/releases/tag/${data['tag_name']}';

  Iterable<String> get _assetNames sync* {
    final assets = data['assets'];
    if (assets is List) {
      for (final item in assets) {
        if (item is Map &&
            item['state'] == 'uploaded' &&
            item['name'] is String) {
          yield item['name'] as String;
        }
      }
    }
  }

  int? get _androidBuildNumber {
    final archive = RegExp(
      '^PiliMinus-${RegExp.escape(version.toString())}\\+([0-9]+)-source\\.tar\\.gz\$',
    );
    for (final name in _assetNames) {
      final match = archive.firstMatch(name);
      if (match != null) return int.tryParse(match[1]!);
    }
    return null;
  }

  bool isNewerThan(String installedVersion, {int? installedAndroidCode}) {
    final installed = Version.parse(installedVersion);
    final current = Version(
      installed.major,
      installed.minor,
      installed.patch,
      pre: installed.isPreRelease ? installed.preRelease.join('.') : null,
    );
    final remoteCode = _androidBuildNumber;
    if (installedAndroidCode != null && remoteCode != null) {
      return version >= current && remoteCode > installedAndroidCode;
    }
    return version > current;
  }

  String _downloadUrl(String name) =>
      '${Constants.sourceCodeUrl}/releases/download/${data['tag_name']}/${Uri.encodeComponent(name)}';

  String? platformDownloadUrl(String platform, {String? extension}) {
    for (final name in _assetNames) {
      if (name.contains(platform) &&
          (extension == null || name.endsWith('.$extension'))) {
        return _downloadUrl(name);
      }
    }
    return null;
  }

  String? androidDownloadUrl(Iterable<String> abis) {
    final names = _assetNames.toSet();
    for (final abi in abis) {
      if (!const {'arm64-v8a', 'armeabi-v7a', 'x86_64'}.contains(abi)) continue;
      final name = 'PiliMinus-$abi.apk';
      if (names.contains(name)) {
        return _downloadUrl(name);
      }
    }
    return null;
  }
}
