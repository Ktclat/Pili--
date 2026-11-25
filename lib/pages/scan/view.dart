import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/models/qr_login_authorization.dart';
import 'package:PiliPlus/pages/scan/authorization.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/trusted_url.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  final _controller = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
    cameraResolution: const Size(1280, 720),
  );
  bool _busy = false;
  bool _disposed = false;
  bool _leaving = false;
  int _pasteRevision = 0;
  String? _error;
  static const _cameraError = '相机不可用，可从相册识别二维码。';
  bool get _supported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_supported) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _start(requestPermission: true),
      );
    }
  }

  Future<void> _start({bool requestPermission = false}) async {
    if (_disposed ||
        _leaving ||
        _busy ||
        !_supported ||
        _controller.value.isStarting ||
        _controller.value.isRunning ||
        (!requestPermission &&
            _controller.value.error?.errorCode ==
                MobileScannerErrorCode.permissionDenied) ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    try {
      await _controller.start();
      if (mounted) {
        if (_busy || _leaving) await _controller.stop();
        if (!mounted) return;
        setState(
          () => _error = _controller.value.error == null ? null : _cameraError,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = _cameraError);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == .hidden || state == .paused || state == .detached) {
      _pasteRevision++;
    }
    if (!_supported || !_controller.value.hasCameraPermission) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_start());
    } else {
      unawaited(_controller.stop());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    if (_supported) unawaited(_controller.dispose());
    super.dispose();
  }

  void _detect(BarcodeCapture capture) {
    if (_busy || _leaving || !mounted) return;
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue case final value? when value.isNotEmpty) {
        unawaited(_showResult(value));
        break;
      }
    }
  }

  Future<void> _toggleTorch() async {
    if (_busy || !_controller.value.isRunning) return;
    try {
      await _controller.toggleTorch();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('此设备暂时无法使用手电筒')),
        );
      }
    }
  }

  Future<void> _openLinkRecognition() async {
    if (_busy || _leaving) return;
    _busy = true;
    try {
      if (_controller.value.isRunning) await _controller.stop();
      if (!mounted) return;
      await Get.toNamed('/recognizeLink');
    } finally {
      _busy = false;
      await _start();
    }
  }

  void _openAuthorization(QrLoginAuthorizationRequest request) {
    _leaving = true;
    Get.off(() => QrLoginAuthorizationPage(request: request));
  }

  Future<void> _pasteLoginLink() async {
    if (_busy || _leaving) return;
    final revision = _pasteRevision;
    bool isCurrent() =>
        mounted &&
        revision == _pasteRevision &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true;
    if (!isCurrent()) return;

    final messenger = ScaffoldMessenger.of(context);
    _busy = true;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!isCurrent()) return;
      final request = QrLoginAuthorizationRequest.parse(data?.text ?? '');
      if (request == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('请先复制哔哩哔哩官方网页或 TV 登录二维码中的完整链接')),
        );
        return;
      }
      if (_supported && _controller.value.isRunning) await _controller.stop();
      if (isCurrent()) _openAuthorization(request);
    } catch (_) {
      if (isCurrent()) {
        messenger.showSnackBar(
          const SnackBar(content: Text('暂时无法粘贴登录链接，请重试')),
        );
      }
    } finally {
      if (!_leaving) {
        _busy = false;
        if (mounted &&
            _controller.value.hasCameraPermission &&
            ModalRoute.of(context)?.isCurrent == true) {
          await _start();
        }
      }
    }
  }

  Future<void> _showResult(String value) async {
    if (_busy || _leaving || !mounted) return;
    _busy = true;
    await _controller.stop();
    if (!mounted) return;
    final request = QrLoginAuthorizationRequest.parse(value);
    if (request != null) {
      _openAuthorization(request);
      return;
    }
    final parsed = Uri.tryParse(value.trim());
    if (parsed != null &&
        QrLoginAuthorizationRequest.isAuthorizationUri(parsed)) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('无法识别登录二维码'),
          content: const Text('请在哔哩哔哩网页或电视端刷新登录二维码后重试。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('继续扫码'),
            ),
          ],
        ),
      );
      _busy = false;
      await _start();
      return;
    }
    final uri = TrustedUrl.scanLink(value);
    final openInApp =
        uri != null &&
        TrustedUrl.isBilibili(uri) &&
        uri.host != 'passport.bilibili.com';
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('扫码结果'),
        content: SingleChildScrollView(
          child: SelectableText(
            value.length > 8192 ? '${value.substring(0, 8192)}…' : value,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('继续扫码'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'copy'),
            child: const Text('复制'),
          ),
          if (uri != null)
            FilledButton(
              onPressed: () => Navigator.pop(context, 'open'),
              child: Text(openInApp ? '打开' : '在浏览器打开'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已复制')));
      }
    } else if (action == 'open' && uri != null) {
      // Remove the camera route before opening another page, releasing CameraX.
      _leaving = true;
      Get.back();
      if (openInApp) {
        unawaited(PageUtils.handleWebview(uri.toString()));
      } else {
        unawaited(PageUtils.launchURL(uri.toString()));
      }
      return;
    }
    _busy = false;
    await _start();
  }

  Future<void> _gallery() async {
    if (_busy) return;
    _busy = true;
    await _controller.stop();
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null || !mounted) return;
      final result = await _controller.analyzeImage(
        file.path,
        formats: const [BarcodeFormat.qrCode],
      );
      if (!mounted) return;
      _busy = false;
      if (result != null &&
          result.barcodes.any((b) => b.rawValue?.isNotEmpty == true)) {
        for (final barcode in result.barcodes) {
          if (barcode.rawValue case final value? when value.isNotEmpty) {
            await _showResult(value);
            break;
          }
        }
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('图片中未找到二维码')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('图片识别失败，请重试')));
      }
    } finally {
      _busy = false;
      await _start();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('扫一扫'),
      actions: [
        IconButton(
          tooltip: '识别链接',
          icon: const Icon(Icons.link_rounded),
          onPressed: _openLinkRecognition,
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: !_supported
                ? const Center(child: Text('此平台暂不支持相机扫码'))
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: MobileScanner(
                          controller: _controller,
                          onDetect: _detect,
                          errorBuilder: (_, _) => const Center(
                            child: Icon(
                              Icons.no_photography_outlined,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                      if (_error == null)
                        IgnorePointer(
                          child: Container(
                            width: 240,
                            height: 240,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          if (_supported)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error ?? '将内容二维码或登录码放入框内',
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                if (_supported) ...[
                  OutlinedButton.icon(
                    onPressed: _gallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('从相册识别'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _toggleTorch,
                    icon: const Icon(Icons.flashlight_on_outlined),
                    label: const Text('手电筒'),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: _pasteLoginLink,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('粘贴登录链接'),
                ),
                if (_error != null)
                  TextButton(
                    onPressed: () => _start(requestPermission: true),
                    child: const Text('重试相机'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
