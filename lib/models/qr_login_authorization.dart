enum QrLoginAuthorizationKind { web, television }

/// A short-lived, in-memory login challenge. Never persist or log its token.
class QrLoginAuthorizationRequest {
  QrLoginAuthorizationRequest._(
    this.kind,
    this.token,
    this.receivedAt,
    this.tvParameters,
  );

  final QrLoginAuthorizationKind kind;
  final String token;
  final DateTime receivedAt;
  final Map<String, String> tvParameters;

  static const maxAge = Duration(minutes: 3);
  static final _tokenPattern = RegExp(r'^[0-9a-fA-F]{32}$');
  static final _contextPattern = RegExp(r'^[a-zA-Z0-9._-]{0,128}$');

  String get destination => switch (kind) {
    .web => '哔哩哔哩网页版',
    .television => '哔哩哔哩 TV / HD 客户端',
  };

  bool isExpired([DateTime? now]) =>
      !(now ?? DateTime.now()).isBefore(receivedAt.add(maxAge));

  /// Recognizes known authorization paths even if their parameters are invalid.
  /// Callers must not fall back to opening these pages with account cookies.
  static bool isAuthorizationUri(Uri uri) =>
      (uri.host == 'account.bilibili.com' &&
          uri.path == '/h5/account-h5/auth/scan-web') ||
      (uri.host == 'passport.bilibili.com' &&
          const {
            '/h5-app/passport/login/scan',
            '/h5-app/passport/login/scan-pad',
            '/x/passport-tv-login/h5/qrcode/auth',
            '/qrcode/h5/login',
          }.contains(uri.path));

  static QrLoginAuthorizationRequest? parse(String value, {DateTime? now}) {
    if (value.length > 2048 ||
        value.contains(RegExp(r'[\x00-\x20\x7f]')) ||
        // Uri normalizes an empty user-info away, so also check the raw input.
        RegExp(r'^https://[^/?#]*@', caseSensitive: false).hasMatch(value)) {
      return null;
    }
    try {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.authority.contains('@') ||
          uri.port != 443 ||
          uri.hasFragment) {
        return null;
      }
      final kind = switch ((uri.host, uri.path)) {
        ('account.bilibili.com', '/h5/account-h5/auth/scan-web') ||
        (
          'passport.bilibili.com',
          '/h5-app/passport/login/scan',
        ) => QrLoginAuthorizationKind.web,
        ('passport.bilibili.com', '/h5-app/passport/login/scan-pad') ||
        (
          'passport.bilibili.com',
          '/x/passport-tv-login/h5/qrcode/auth',
        ) => QrLoginAuthorizationKind.television,
        _ => null,
      };
      if (kind == null) return null;
      final tokenKey = kind == .web ? 'qrcode_key' : 'auth_code';
      final allowed = {
        tokenKey,
        'navhide',
        'from',
        if (uri.host == 'account.bilibili.com') 'callback',
        if (kind == .television) ...{
          'login_session_id',
          'mobi_app',
          'spm_id',
        },
      };
      final query = uri.queryParametersAll;
      if (query.entries.any(
        (entry) => !allowed.contains(entry.key) || entry.value.length != 1,
      )) {
        return null;
      }
      final token = query[tokenKey]?.single;
      if (token == null ||
          token.length != 32 ||
          !_tokenPattern.hasMatch(token)) {
        return null;
      }
      if (query.values.any(
        (values) =>
            values.single.length > 256 ||
            values.single.contains(RegExp(r'[\x00-\x1f\x7f]')),
      )) {
        return null;
      }
      final context = <String, String>{};
      for (final key in ['login_session_id', 'mobi_app', 'spm_id']) {
        final data = query[key]?.single;
        if (data != null) {
          if (_contextPattern.firstMatch(data)?.end != data.length) return null;
          context[key] = data;
        }
      }
      return QrLoginAuthorizationRequest._(
        kind,
        token,
        now ?? DateTime.now(),
        Map.unmodifiable(context),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => 'QrLoginAuthorizationRequest(${kind.name})';
}

class QrLoginAuthorizationScene {
  const QrLoginAuthorizationScene({
    required this.differentLocation,
    required this.location,
    this.application = '',
    this.supportsTemporary = false,
  });

  final bool differentLocation;
  final String location;
  final String application;
  final bool supportsTemporary;
}

enum QrLoginAuthorizationFailureKind {
  loginRequired,
  expired,
  accountChanged,
  unavailable,
  rejected,
  uncertain,
  cancelled,
  officialVerificationRequired,
}

class QrLoginAuthorizationFailure implements Exception {
  const QrLoginAuthorizationFailure(this.kind);

  final QrLoginAuthorizationFailureKind kind;

  String get message => switch (kind) {
    .loginRequired => '请先登录 Pili--，再重新扫描登录二维码。',
    .expired => '登录二维码已失效，请在待登录设备刷新后重新扫码。',
    .accountChanged => '当前账号已变化，请重新扫码并确认使用的账号。若已点击授权，请先在待登录设备核对结果。',
    .unavailable => '暂时无法核验登录二维码，请检查网络并重新扫码。',
    .rejected => '官方服务未接受此次请求，请在待登录设备刷新二维码后重试。',
    .uncertain => '未能确认授权结果。请先查看待登录设备，确认后再决定是否重新扫码。',
    .cancelled => '已关闭此次扫码。已发送的授权请求无法通过关闭页面撤回。',
    .officialVerificationRequired =>
      '此二维码需要手机号或登录环境等额外验证，请使用哔哩哔哩官方 App 重新扫码完成。',
  };

  @override
  String toString() => 'QrLoginAuthorizationFailure(${kind.name})';
}
