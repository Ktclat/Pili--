import 'package:PiliPlus/models/qr_login_authorization.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = '0123456789abcdef0123456789abcdef';
const _web = 'https://passport.bilibili.com/h5-app/passport/login/scan';
const _currentWeb = 'https://account.bilibili.com/h5/account-h5/auth/scan-web';
const _tv = 'https://passport.bilibili.com/x/passport-tv-login/h5/qrcode/auth';

void main() {
  test('accepts current and legacy official web formats without callbacks', () {
    for (final base in [_web, _currentWeb]) {
      final request = QrLoginAuthorizationRequest.parse(
        '$base?qrcode_key=$_key&navhide=1&from=',
      )!;
      expect(request.kind, QrLoginAuthorizationKind.web);
      expect(request.token, _key);
      expect(request.tvParameters, isEmpty);
      expect(request.toString(), isNot(contains(_key)));
    }
    final withCallback = QrLoginAuthorizationRequest.parse(
      '$_currentWeb?qrcode_key=$_key&callback=close',
    )!;
    expect(withCallback.tvParameters, isEmpty);
  });

  test('TV context remains bounded and cannot replace endpoint or identity', () {
    final request = QrLoginAuthorizationRequest.parse(
      '$_tv?auth_code=$_key&mobi_app=android_hd&login_session_id=abc-12&spm_id=1.2',
    )!;
    expect(request.kind, QrLoginAuthorizationKind.television);
    expect(request.tvParameters, {
      'mobi_app': 'android_hd',
      'login_session_id': 'abc-12',
      'spm_id': '1.2',
    });
    expect(
      () => request.tvParameters['mobi_app'] = 'modified',
      throwsUnsupportedError,
    );
    expect(
      QrLoginAuthorizationRequest.parse(
        'https://passport.bilibili.com/h5-app/passport/login/scan-pad?auth_code=$_key',
      )?.kind,
      QrLoginAuthorizationKind.television,
    );
  });

  for (final value in [
    'http://passport.bilibili.com/h5-app/passport/login/scan?qrcode_key=$_key',
    'https://passport.bilibili.com:444/h5-app/passport/login/scan?qrcode_key=$_key',
    'https://passport.bilibili.com.evil.test/h5-app/passport/login/scan?qrcode_key=$_key',
    'https://user@passport.bilibili.com/h5-app/passport/login/scan?qrcode_key=$_key',
    'https://@passport.bilibili.com/h5-app/passport/login/scan?qrcode_key=$_key',
    'https://passport.bilibili.com./h5-app/passport/login/scan?qrcode_key=$_key',
    'https://account.bilibili.com/h5-app/passport/login/scan?qrcode_key=$_key',
    'https://passport.bilibili.com/h5/account-h5/auth/scan-web?qrcode_key=$_key',
    '$_web/?qrcode_key=$_key',
    '$_web?qrcode_key=$_key#',
    '$_web?qrcode_key=$_key#callback',
    '$_web?qrcode_key=$_key&qrcode_key=$_key',
    '$_web?qrcode_key=$_key&qrcode%5fkey=$_key',
    '$_web?qrcode_key=$_key&from=one&from=two',
    '$_web?qrcode_key=$_key&csrf=unsafe',
    '$_web?qrcode_key=$_key&buvid=unsafe',
    '$_web?qrcode_key=$_key&redirect=https://evil.test',
    '$_web?qrcode_key=short',
    '$_web?qrcode_key=${'g' * 32}',
    '$_web?qrcode_key=$_key%0A',
    '$_web?qrcode_key=$_key%0D',
    '$_web?qrcode_key=$_key&from=%00',
    '$_web?qrcode_key=$_key&from=${'a' * 257}',
    '$_web?qrcode_key=$_key\n',
    ' $_web?qrcode_key=$_key',
    '$_tv?auth_code=$_key&login_session_id=https%3A%2F%2Fevil.test',
    '$_tv?auth_code=$_key&mobi_app=${'a' * 129}',
    '$_tv?auth_code=$_key&login_session_id=abc%0A',
    '$_tv?auth_code=$_key&spm_id=abc%0D',
    'https://passport.bilibili.com/qrcode/h5/login?oauthKey=$_key',
    '$_web?auth_code=$_key',
    '$_tv?qrcode_key=$_key',
  ]) {
    test(
      'rejects malformed or ambiguous authorization URL ${value.hashCode}',
      () {
        expect(QrLoginAuthorizationRequest.parse(value), isNull);
      },
    );
  }

  test(
    'invalid official authorization URLs are still recognized for blocking',
    () {
      expect(
        QrLoginAuthorizationRequest.isAuthorizationUri(
          Uri.parse('$_web?qrcode_key=invalid'),
        ),
        isTrue,
      );
      expect(
        QrLoginAuthorizationRequest.isAuthorizationUri(
          Uri.parse('$_currentWeb?qrcode_key=invalid'),
        ),
        isTrue,
      );
    },
  );

  test('local lifetime is capped and does not trust QR expiry parameters', () {
    final now = DateTime.utc(2026, 10, 29);
    final request = QrLoginAuthorizationRequest.parse(
      '$_web?qrcode_key=$_key',
      now: now,
    )!;
    expect(request.isExpired(now.add(const Duration(seconds: 179))), isFalse);
    expect(request.isExpired(now.add(const Duration(seconds: 180))), isTrue);
    expect(
      QrLoginAuthorizationRequest.parse(
        '$_web?qrcode_key=$_key&expires=999999999999',
      ),
      isNull,
    );
  });

  test('accepts exact safe parameter limits and rejects oversized URLs', () {
    expect(
      QrLoginAuthorizationRequest.parse(
        '$_tv?auth_code=$_key&login_session_id=${'a' * 128}',
      ),
      isNotNull,
    );
    expect(
      QrLoginAuthorizationRequest.parse(
        '$_web?qrcode_key=$_key&from=${'a' * 256}',
      ),
      isNotNull,
    );
    expect(
      QrLoginAuthorizationRequest.parse(
        '$_web?qrcode_key=$_key&from=${'a' * 2048}',
      ),
      isNull,
    );
  });
}
