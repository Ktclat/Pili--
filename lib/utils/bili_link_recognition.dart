/// Extract public Bilibili content from shared text without network access.
/// Login/authorization links deliberately belong to the scanner's own flow.
abstract final class BiliLinkRecognition {
  static const maxTextLength = 8192;
  static const _hosts = {
    'bilibili.com',
    'www.bilibili.com',
    'm.bilibili.com',
    't.bilibili.com',
    'space.bilibili.com',
    'live.bilibili.com',
    'bangumi.bilibili.com',
    'b23.tv',
  };
  static const _schemes = {
    'video',
    'space',
    'live',
    'bangumi',
    'pgc',
    'opus',
    'article',
    'search',
  };
  static final _url = RegExp(
    r'''(?<![a-zA-Z0-9_.@/\-])(?:https?://|bilibili://|www\.bilibili\.com/|b23\.tv/)[^\s<>"'`]+''',
    caseSensitive: false,
  );
  static final _trailing = RegExp(r'[.,!?;:，。！？；：、）)】\]》〉」』]+$');
  static final _id = RegExp(
    r'(?<![a-zA-Z0-9_./?=&%#:@\-])(?:BV[0-9a-zA-Z]{10}|av[0-9]{1,19})(?![a-zA-Z0-9_])',
    caseSensitive: false,
  );

  static List<Uri> parse(String text) {
    if (text.isEmpty ||
        text.length > maxTextLength ||
        text.contains(RegExp(r'[\x00-\x08\x0b-\x1f\x7f]'))) {
      return const [];
    }
    final result = <Uri>[];
    final seen = <String>{};
    final matches = _url.allMatches(text).toList();
    for (final match in matches) {
      var value = match.group(0)!.replaceFirst(_trailing, '');
      if (!value.contains('://')) value = 'https://$value';
      // Uri normalizes an empty user-info marker away; inspect raw authority.
      if (RegExp(r'^[^:]+://[^/?#]*@').hasMatch(value)) continue;
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.userInfo.isNotEmpty ||
          uri.authority.contains('@')) {
        continue;
      }
      Uri? accepted;
      if ((uri.scheme == 'https' || uri.scheme == 'http') &&
          _hosts.contains(uri.host) &&
          uri.port == (uri.scheme == 'https' ? 443 : 80)) {
        accepted = uri.replace(scheme: 'https', port: 443);
      } else if (uri.scheme == 'bilibili' &&
          _schemes.contains(uri.host) &&
          !uri.hasPort) {
        accepted = uri;
      }
      if (accepted != null && seen.add(accepted.toString())) {
        result.add(accepted);
      }
      if (result.length == 8) break;
    }
    // Never extract an ID embedded in an untrusted URL as a valid Bili link.
    if (matches.isEmpty && !text.contains('://')) {
      for (final match in _id.allMatches(text)) {
        final raw = match.group(0)!;
        final id = raw.toLowerCase().startsWith('bv')
            ? 'BV${raw.substring(2)}'
            : raw.toLowerCase();
        if (id.startsWith('av') && (int.tryParse(id.substring(2)) ?? 0) <= 0) {
          continue;
        }
        final uri = Uri.https('www.bilibili.com', '/video/$id');
        if (seen.add(uri.toString())) result.add(uri);
        if (result.length == 8) break;
      }
    }
    return result;
  }
}
