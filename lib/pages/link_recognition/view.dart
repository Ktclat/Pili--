import 'package:PiliPlus/utils/bili_link_recognition.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

Future<void> confirmRecognizedLinks(
  BuildContext context,
  List<Uri> links, {
  String title = '识别到哔哩哔哩链接',
}) async {
  final selected = await showDialog<Uri>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [
              const Text('核对后点击打开。短链接会在打开后解析，不会自动授权登录。'),
              const SizedBox(height: 12),
              for (final link in links)
                ListTile(
                  contentPadding: .zero,
                  title: Text(
                    link.toString(),
                    maxLines: 4,
                    overflow: .ellipsis,
                  ),
                  leading: const Icon(Icons.link),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => Navigator.pop(context, link),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    ),
  );
  if (selected == null || !context.mounted) return;
  try {
    await PageUtils.handleWebview(selected.toString());
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂时无法打开此链接，请稍后重试')));
    }
  }
}

class LinkRecognitionPage extends StatefulWidget {
  const LinkRecognitionPage({super.key});
  @override
  State<LinkRecognitionPage> createState() => _LinkRecognitionPageState();
}

class _LinkRecognitionPageState extends State<LinkRecognitionPage> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _recognize({bool paste = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (paste) {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (!mounted) return;
        _text.text = data?.text ?? '';
      }
      final links = BiliLinkRecognition.parse(_text.text);
      if (links.isEmpty) {
        setState(() => _error = '未识别到可打开的 B 站链接或 BV/av 号，请检查内容。');
      } else {
        await confirmRecognizedLinks(context, links);
      }
    } catch (_) {
      if (mounted) setState(() => _error = '读取或识别失败，可手动粘贴后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('识别链接')),
    body: SafeArea(
      child: ListView(
        padding: const .all(20),
        children: [
          const Text('支持分享文案中的 B 站链接、b23.tv 短链接和 BV/av 号。登录二维码请使用“扫码授权登录”。'),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 8,
            maxLength: BiliLinkRecognition.maxTextLength,
            decoration: InputDecoration(
              labelText: '链接或分享文字',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _recognize,
            child: const Text('识别'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : () => _recognize(paste: true),
            icon: const Icon(Icons.content_paste),
            label: const Text('从剪贴板粘贴并识别'),
          ),
          const Text('此按钮仅在点击时读取剪贴板；自动识别需在“设置 → 隐私设置”另行开启。'),
        ],
      ),
    ),
  );
}
