import 'dart:async';

import 'package:PiliPlus/http/qr_login_authorization.dart';
import 'package:PiliPlus/models/qr_login_authorization.dart';
import 'package:PiliPlus/pages/scan/authorization.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _token = '0123456789abcdef0123456789abcdef';

QrLoginAuthorizationRequest _request({
  DateTime? now,
}) => QrLoginAuthorizationRequest.parse(
  'https://account.bilibili.com/h5/account-h5/auth/scan-web?qrcode_key=$_token',
  now: now,
)!;

LoginAccount _account([int mid = 123]) => LoginAccount(
  BiliCookieJar.fromJson({
    'SESSDATA': 'test-session',
    'bili_jct': 'test-csrf',
    'DedeUserID': '$mid',
  }),
  null,
  null,
  null,
  'test-buvid',
);

class _Repository extends QrLoginAuthorizationRepository {
  QrLoginAuthorizationScene scene = const QrLoginAuthorizationScene(
    differentLocation: false,
    location: '测试地点',
    application: '哔哩哔哩网页版',
  );
  int preparations = 0;
  int authorizations = 0;
  bool? temporaryRequested;
  Completer<void>? pending;
  QrLoginAuthorizationFailure? preparationFailure;

  @override
  Future<QrLoginAuthorizationScene> prepare(
    QrLoginAuthorizationRequest request,
    Account account, {
    required bool Function() isCurrent,
    required CancelToken cancelToken,
  }) async {
    preparations++;
    if (preparationFailure case final failure?) throw failure;
    return scene;
  }

  @override
  Future<void> authorize(
    QrLoginAuthorizationRequest request,
    Account account, {
    required bool Function() isCurrent,
    required CancelToken cancelToken,
    bool temporary = false,
  }) async {
    authorizations++;
    temporaryRequested = temporary;
    await pending?.future;
  }
}

Future<QrLoginAuthorizationSession> _show(
  WidgetTester tester,
  _Repository repository, {
  Account Function()? currentAccount,
  QrLoginAuthorizationRequest? request,
}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final account = _account();
  final challenge = request ?? _request();
  final session = QrLoginAuthorizationSession(
    request: challenge,
    repository: repository,
    currentAccount: currentAccount ?? () => account,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => QrLoginAuthorizationPage(
                  request: challenge,
                  session: session,
                ),
              ),
            ),
            child: const Text('打开扫码确认'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开扫码确认'));
  await tester.pumpAndSettle();
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  return session;
}

void main() {
  testWidgets(
    'shows account and scene but only authorizes after a deliberate tap',
    (
      tester,
    ) async {
      final repository = _Repository();
      await _show(tester, repository);
      expect(repository.preparations, 1);
      expect(repository.authorizations, 0);
      expect(find.text('使用账号：UID 123'), findsOneWidget);
      expect(find.text('官方服务提供的登录地点：测试地点'), findsOneWidget);
      expect(find.textContaining(_token), findsNothing);
      await tester.tap(find.text('确认授权登录'));
      await tester.pumpAndSettle();
      expect(repository.authorizations, 1);
      expect(repository.temporaryRequested, isFalse);
      expect(find.text('授权成功，请在待登录设备查看结果。'), findsOneWidget);
    },
  );

  testWidgets('cancel closes the page without any authorization', (
    tester,
  ) async {
    final repository = _Repository();
    final session = await _show(tester, repository);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repository.authorizations, 0);
    expect(session.phase, QrLoginAuthorizationPhase.cancelled);
    expect(find.text('打开扫码确认'), findsOneWidget);
  });

  testWidgets(
    'double taps cannot submit twice and closing cannot claim rollback',
    (
      tester,
    ) async {
      final repository = _Repository()..pending = Completer<void>();
      await _show(tester, repository);
      await tester.tap(find.text('确认授权登录'));
      await tester.tap(find.text('确认授权登录'));
      await tester.pump();
      expect(repository.authorizations, 1);
      expect(find.textContaining('关闭页面不能撤回'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      repository.pending!.complete();
      await tester.pump();
      expect(repository.authorizations, 1);
      expect(find.text('打开扫码确认'), findsOneWidget);
    },
  );

  testWidgets('different location requires a second explicit acknowledgement', (
    tester,
  ) async {
    final repository = _Repository()
      ..scene = const QrLoginAuthorizationScene(
        differentLocation: true,
        location: '其他地点',
      );
    await _show(tester, repository);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(repository.authorizations, 0);
    await tester.tap(find.text('我确认这是本人正在登录的设备'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.text('确认授权登录'));
    await tester.pumpAndSettle();
    expect(repository.authorizations, 1);
  });

  testWidgets('optional short login is off until selected by the user', (
    tester,
  ) async {
    final repository = _Repository()
      ..scene = const QrLoginAuthorizationScene(
        differentLocation: false,
        location: '',
        supportsTemporary: true,
      );
    await _show(tester, repository);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.tap(find.text('短期登录（24 小时）'));
    await tester.pump();
    expect(repository.authorizations, 0);
    await tester.tap(find.text('确认授权登录'));
    await tester.pumpAndSettle();
    expect(repository.temporaryRequested, isTrue);
  });

  testWidgets(
    'required official verification shows a failure and no confirm action',
    (
      tester,
    ) async {
      final repository = _Repository()
        ..preparationFailure = const QrLoginAuthorizationFailure(
          .officialVerificationRequired,
        );
      await _show(tester, repository);
      expect(find.textContaining('请使用哔哩哔哩官方 App'), findsOneWidget);
      expect(find.text('确认授权登录'), findsNothing);
      expect(repository.authorizations, 0);
    },
  );

  testWidgets('expired challenges never prepare or offer authorization', (
    tester,
  ) async {
    final repository = _Repository();
    await _show(
      tester,
      repository,
      request: _request(
        now: DateTime.now().subtract(const Duration(minutes: 4)),
      ),
    );
    expect(find.textContaining('登录二维码已失效'), findsOneWidget);
    expect(find.text('确认授权登录'), findsNothing);
    expect(repository.preparations, 0);
    expect(repository.authorizations, 0);
  });

  testWidgets('an account change removes authorization before the next tap', (
    tester,
  ) async {
    Account current = _account();
    final repository = _Repository();
    await _show(tester, repository, currentAccount: () => current);
    current = _account(456);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('当前账号已变化'), findsOneWidget);
    expect(find.text('确认授权登录'), findsNothing);
    expect(repository.authorizations, 0);
  });
}
