import 'dart:async';
import 'dart:io';

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
  String? _error;
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
        setState(
          () => _error = _controller.value.error == null
              ? null
              : '无法使用相机，请允许相机权限，或从相册识别二维码。',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法使用相机，请允许相机权限，或从相册识别二维码。');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    if (_busy) return;
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

  Future<void> _showResult(String value) async {
    if (_busy || !mounted) return;
    _busy = true;
    await _controller.stop();
    if (!mounted) return;
    final uri = TrustedUrl.scanLink(value);
    final isBili = uri != null && TrustedUrl.isBilibili(uri);
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('扫码结果'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                value.length > 8192 ? '${value.substring(0, 8192)}…' : value,
              ),
              const SizedBox(height: 12),
              Text(
                uri == null
                    ? '这是文本或不支持的链接，可以复制内容。'
                    : isBili
                    ? '确认后打开哔哩哔哩链接。登录授权请使用官方 App。'
                    : '这是外部网站，将在系统浏览器打开，请核对域名。',
              ),
            ],
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
              child: const Text('打开'),
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
      if (isBili && uri.host != 'passport.bilibili.com') {
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
    appBar: AppBar(title: const Text('扫一扫')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: !_supported
                ? const Center(child: Text('此平台暂不支持相机扫码'))
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      MobileScanner(
                        controller: _controller,
                        onDetect: _detect,
                        errorBuilder: (_, _) =>
                            const Center(child: Text('相机不可用，可使用下方的相册识别')),
                      ),
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error ?? '将二维码放入框内，识别结果不会自动打开'),
          ),
          if (_supported)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Wrap(
                spacing: 12,
                alignment: WrapAlignment.center,
                children: [
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
