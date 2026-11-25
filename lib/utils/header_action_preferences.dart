import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/utils/navigation_preferences.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:get/get.dart';

enum HeaderAction {
  scan('扫一扫'),
  messages('消息'),
  profile('我的'),
  recognizeLink('识别链接'),
  search('搜索'),
  replyHistory('评论记录'),
  incognito('无痕模式'),
  switchAccount('切换账号'),
  theme('切换主题'),
  settings('设置');

  const HeaderAction(this.label);

  final String label;
}

typedef HeaderActionEntry = ({HeaderAction action, bool pinned});

enum HeaderActionPage {
  home('首页', SettingBoxKey.homeHeaderActions, [
    (action: HeaderAction.scan, pinned: true),
    (action: HeaderAction.messages, pinned: true),
    (action: HeaderAction.profile, pinned: true),
    (action: HeaderAction.recognizeLink, pinned: false),
  ]),
  mine('我的', SettingBoxKey.mineHeaderActions, [
    (action: HeaderAction.messages, pinned: true),
    (action: HeaderAction.search, pinned: true),
    (action: HeaderAction.replyHistory, pinned: true),
    (action: HeaderAction.incognito, pinned: true),
    (action: HeaderAction.switchAccount, pinned: true),
    (action: HeaderAction.theme, pinned: true),
    (action: HeaderAction.settings, pinned: true),
    (action: HeaderAction.scan, pinned: true),
    (action: HeaderAction.recognizeLink, pinned: false),
  ]);

  const HeaderActionPage(this.label, this._storageKey, this._defaults);

  final String label;
  final String _storageKey;
  final List<HeaderActionEntry> _defaults;

  List<HeaderActionEntry> get defaults {
    if (this == home ||
        !NavigationPreferences.bars.contains(NavigationBarType.home)) {
      return _defaults;
    }
    return [
      for (final entry in _defaults)
        if (entry.action == HeaderAction.search ||
            entry.action == HeaderAction.messages)
          (action: entry.action, pinned: false)
        else
          entry,
    ];
  }
}

abstract final class HeaderActionPreferences {
  static final _revisions = {
    for (final page in HeaderActionPage.values) page: 0.obs,
  };

  // A null pin preserves the page's default even after other buttons move.
  static Map<String, bool?> _stored(HeaderActionPage page) {
    final stored = GStorage.setting.get(page._storageKey);
    final result = <String, bool?>{};
    if (stored is List) {
      for (final item in stored) {
        if (item case {'id': final String id, 'pinned': final bool? pinned}) {
          result.putIfAbsent(id, () => pinned);
        }
      }
    }
    return result;
  }

  /// Reading inside Obx subscribes that header to edits for just its page.
  static List<HeaderActionEntry> read(HeaderActionPage page) {
    _revisions[page]!.value;
    final remaining = {
      for (final entry in page.defaults) entry.action.name: entry,
    };
    final entries = <HeaderActionEntry>[];
    for (final item in _stored(page).entries) {
      final entry = remaining.remove(item.key);
      if (entry != null) {
        entries.add((action: entry.action, pinned: item.value ?? entry.pinned));
      }
    }
    return [...entries, ...remaining.values];
  }

  static Future<void> save(
    HeaderActionPage page,
    List<HeaderActionEntry> entries,
  ) async {
    final previous = _stored(page);
    final defaults = {
      for (final entry in page.defaults) entry.action: entry.pinned,
    };
    final stored = [
      for (final entry in entries)
        {
          'id': entry.action.name,
          'pinned':
              previous[entry.action.name] != null ||
                  entry.pinned != defaults[entry.action]
              ? entry.pinned
              : null,
        },
    ];
    await _notifyWrite(page, GStorage.setting.put(page._storageKey, stored));
  }

  static Future<void> reset(HeaderActionPage page) =>
      _notifyWrite(page, GStorage.setting.delete(page._storageKey));

  static Future<void> _notifyWrite(
    HeaderActionPage page,
    Future<void> write,
  ) async {
    // Hive updates the in-memory box immediately and rolls back a failed write.
    _revisions[page]!.value++;
    try {
      await write;
    } catch (_) {
      _revisions[page]!.value++;
      rethrow;
    }
  }
}
