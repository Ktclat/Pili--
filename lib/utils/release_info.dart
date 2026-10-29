import 'package:pub_semver/pub_semver.dart';

/// A published stable release, ordered by version rather than GitHub dates.
class ReleaseInfo {
  final Map<String, dynamic> data;
  final Version version;

  const ReleaseInfo._(this.data, this.version);

  static ReleaseInfo? latestStable(List<dynamic> releases) {
    ReleaseInfo? latest;
    for (final entry in releases) {
      if (entry is! Map<String, dynamic> ||
          entry['draft'] == true ||
          entry['prerelease'] == true) {
        continue;
      }
      final tag = entry['tag_name'];
      if (tag is! String) continue;
      final Version parsed;
      try {
        parsed = Version.parse(tag.startsWith('v') ? tag.substring(1) : tag);
      } on FormatException {
        continue;
      }
      if (parsed.isPreRelease) continue;
      // Build metadata is not an upgrade: releases must increment the version.
      final version = Version(parsed.major, parsed.minor, parsed.patch);
      if (latest == null || version > latest.version) {
        latest = ReleaseInfo._(entry, version);
      }
    }
    return latest;
  }

  bool isNewerThan(String installedVersion) {
    final installed = Version.parse(installedVersion);
    return version >
        Version(
          installed.major,
          installed.minor,
          installed.patch,
          pre: installed.isPreRelease ? installed.preRelease.join('.') : null,
        );
  }
}
