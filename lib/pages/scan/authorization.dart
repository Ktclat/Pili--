import 'dart:async';

import 'package:PiliPlus/http/qr_login_authorization.dart';
import 'package:PiliPlus/models/qr_login_authorization.dart';
import 'package:material_ui/material_ui.dart';

class QrLoginAuthorizationPage extends StatefulWidget {
  const QrLoginAuthorizationPage({
    super.key,
    required this.request,
    this.session,
  });

  final QrLoginAuthorizationRequest request;
  final QrLoginAuthorizationSession? session;

  @override
  State<QrLoginAuthorizationPage> createState() =>
      _QrLoginAuthorizationPageState();
}

class _QrLoginAuthorizationPageState extends State<QrLoginAuthorizationPage>
    with WidgetsBindingObserver {
  late final _session =
      widget.session ??
      QrLoginAuthorizationSession(
        request: widget.request,
        repository: BilibiliQrLoginAuthorizationRepository(),
      );
  Timer? _timer;
  bool _confirmedDifferentLocation = false;
  bool _temporaryLogin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_refresh);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _session.checkContext();
      _refresh();
    });
    unawaited(_session.prepare());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from an account picker or another app must not reuse stale
    // identity or an expired challenge.
    if (state == .resumed) _session.checkContext();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _session.removeListener(_refresh);
    _session.dispose();
    super.dispose();
  }

  void _close() {
    final success = _session.phase == .completed;
    _session.cancel();
    Navigator.of(context).pop(success);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phase = _session.phase;
    final scene = _session.scene;
    final differentLocation = scene?.differentLocation ?? false;
    final busy = phase == .checking || phase == .authorizing;
    final canConfirm =
        _session.canAuthorize &&
        (!differentLocation || _confirmedDifferentLocation);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _session.cancel();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('扫码授权登录')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Icon(
                    phase == .completed
                        ? Icons.check_circle_outline
                        : Icons.login,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.request.destination,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _session.account.isLogin
                        ? '使用账号：UID ${_session.account.mid}'
                        : '当前尚未登录 Pili--',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '确认后，二维码对应的浏览器或设备将获得你的账号登录权限。'
                    '请只扫描你本人正在操作的设备上的登录二维码，不要为陌生人发送的二维码授权。',
                  ),
                  if (scene != null) ...[
                    const SizedBox(height: 16),
                    if (scene.application.isNotEmpty) ...[
                      Text('官方服务提供的应用名称：${scene.application}'),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      scene.location.isEmpty
                          ? '官方服务未提供登录地点。'
                          : '官方服务提供的登录地点：${scene.location}',
                    ),
                    if (differentLocation) ...[
                      const SizedBox(height: 12),
                      Text(
                        '官方服务提示登录地点存在差异，请再次核对待登录设备。',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('我确认这是本人正在登录的设备'),
                        value: _confirmedDifferentLocation,
                        onChanged: phase == .ready
                            ? (value) => setState(
                                () => _confirmedDifferentLocation =
                                    value ?? false,
                              )
                            : null,
                      ),
                    ],
                    if (scene.supportsTemporary) ...[
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('短期登录（24 小时）'),
                        subtitle: const Text('适合公用或不常用的设备'),
                        value: _temporaryLogin,
                        onChanged: phase == .ready
                            ? (value) => setState(
                                () => _temporaryLogin = value ?? false,
                              )
                            : null,
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  if (busy) ...[
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 16),
                    Text(
                      phase == .checking ? '正在核验二维码…' : '正在请求授权…',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (phase == .authorizing) ...[
                    const SizedBox(height: 12),
                    const Text('请求已发送，关闭页面不能撤回已完成的授权，请在待登录设备核对结果。'),
                  ],
                  if (phase == .completed)
                    const Text(
                      '授权成功，请在待登录设备查看结果。',
                      textAlign: TextAlign.center,
                    ),
                  if (_session.failure case final failure?)
                    Text(
                      failure.message,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  if (phase == .ready) ...[
                    FilledButton(
                      onPressed: canConfirm
                          ? () => unawaited(
                              _session.authorize(temporary: _temporaryLogin),
                            )
                          : null,
                      child: const Text('确认授权登录'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextButton(
                    onPressed: _close,
                    child: Text(
                      phase == .completed
                          ? '完成'
                          : phase == .authorizing
                          ? '关闭'
                          : '取消',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
