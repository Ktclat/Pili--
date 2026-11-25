import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/custom_height_widget.dart';
import 'package:PiliPlus/common/widgets/header_more_button.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart' show tabBarView;
import 'package:PiliPlus/pages/common/common_page.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/header_action_preferences.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends CommonPageState<HomePage>
    with AutomaticKeepAliveClientMixin {
  late ColorScheme _colorScheme;
  final _homeController = Get.putOrFind(HomeController.new);
  final _mainController = Get.find<MainController>();

  @override
  bool get needsCorrection => _homeController.hideTopBar;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorScheme = ColorScheme.of(context);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    Widget tabBar;
    if (_homeController.tabs.length > 1) {
      tabBar = Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SizedBox(
          height: 42,
          width: double.infinity,
          child: TabBar(
            controller: _homeController.tabController,
            tabs: _homeController.tabs.map((e) => Tab(text: e.label)).toList(),
            isScrollable: true,
            dividerColor: Colors.transparent,
            dividerHeight: 0,
            splashBorderRadius: Style.mdRadius,
            tabAlignment: TabAlignment.center,
            onTap: (_) {
              feedBack();
              if (!_homeController.tabController.indexIsChanging) {
                _homeController.animateToTop();
              }
            },
          ),
        ),
      );
      if (_homeController.hideTopBar &&
          _mainController.barHideType == .instant) {
        tabBar = Material(
          color: _colorScheme.surface,
          child: tabBar,
        );
      }
    } else {
      tabBar = const SizedBox(height: 6);
    }
    final showSearch =
        !_mainController.useSideBar && MediaQuery.isPortraitOf(context);
    return Column(
      children: [
        if (showSearch) ...[
          customAppBar(),
          tabBar,
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _HomeHeaderBar(
              mainController: _mainController,
              leading: tabBar,
            ),
          ),
        Expanded(
          child: onBuild(
            tabBarView(
              controller: _homeController.tabController,
              children: _homeController.tabs.map((e) => e.page).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget customAppBar() {
    const padding = EdgeInsets.fromLTRB(14, 6, 14, 0);
    final child = _HomeHeaderBar(
      mainController: _mainController,
      leading: searchBar(),
    );
    if (_homeController.hideTopBar) {
      if (_mainController.barOffset case final barOffset?) {
        return Obx(
          () {
            final offset = barOffset.value;
            return CustomHeightWidget(
              offset: Offset(0, -offset),
              height: Style.topBarHeight - offset,
              child: Padding(
                padding: padding,
                child: child,
              ),
            );
          },
        );
      }
      if (_homeController.showTopBar case final showTopBar?) {
        return Obx(() {
          final showSearchBar = showTopBar.value;
          return AnimatedOpacity(
            opacity: showSearchBar ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: AnimatedContainer(
              curve: Curves.easeInOutCubicEmphasized,
              duration: const Duration(milliseconds: 500),
              height: showSearchBar ? Style.topBarHeight : 0,
              padding: padding,
              child: child,
            ),
          );
        });
      }
    }
    return Container(
      height: Style.topBarHeight,
      padding: padding,
      child: child,
    );
  }

  Widget searchBar() {
    const borderRadius = BorderRadius.all(Radius.circular(25));
    void openSearch() => Get.toNamed(
      '/search',
      parameters: _homeController.enableSearchWord
          ? {'hintText': _homeController.defaultSearch.value}
          : null,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 72) {
          return IconButton(
            tooltip: '搜索',
            onPressed: openSearch,
            icon: const Icon(Icons.search_outlined),
          );
        }
        return SizedBox(
          height: 44,
          child: Material(
            borderRadius: borderRadius,
            color: _colorScheme.onSecondaryContainer.withValues(alpha: 0.05),
            child: InkWell(
              borderRadius: borderRadius,
              splashColor: _colorScheme.primaryContainer.withValues(alpha: 0.3),
              onTap: openSearch,
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(
                    Icons.search_outlined,
                    color: _colorScheme.onSecondaryContainer,
                    semanticLabel: '搜索',
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Obx(
                      () => Text(
                        _homeController.defaultSearch.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _colorScheme.outline),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomeHeaderBar extends StatelessWidget {
  const _HomeHeaderBar({
    required this.mainController,
    required this.leading,
  });

  final MainController mainController;
  final Widget leading;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Obx(() {
      final loggedIn = mainController.accountService.isLogin.value;
      final colors = ColorScheme.of(context);
      final buttons = <HeaderAction, ({Widget icon, VoidCallback open})>{
        .scan: (
          icon: const Icon(Icons.qr_code_scanner),
          open: () => Get.toNamed('/scan'),
        ),
        if (loggedIn)
          .messages: (
            icon: messageBadgeIcon(mainController),
            open: () => openMessages(mainController),
          ),
        .profile: (
          icon: _profileIcon(mainController, colors),
          open: mainController.toMinePage,
        ),
        .recognizeLink: (
          icon: const Icon(Icons.link),
          open: () => Get.toNamed('/recognizeLink'),
        ),
      };
      final entries = HeaderActionPreferences.read(.home)
          .where((entry) => buttons.containsKey(entry.action))
          .toList();
      // Keep the search field or scrollable tabs usable before pinning shortcuts.
      const slot = kMinInteractiveDimension;
      final slots = ((constraints.maxWidth - 96) / slot).floor() - 1;
      final pinned = entries
          .where((entry) => entry.pinned)
          .take(slots.clamp(0, entries.length))
          .map((entry) => entry.action)
          .toSet();
      final more = entries.where((entry) => !pinned.contains(entry.action));
      return Row(
        children: [
          Expanded(child: leading),
          for (final action in pinned)
            SizedBox(
              width: slot,
              child: IconButton(
                padding: action == .profile ? EdgeInsets.zero : null,
                tooltip: action == .profile && !loggedIn
                    ? '点击登录'
                    : action.label,
                onPressed: buttons[action]!.open,
                icon: buttons[action]!.icon,
              ),
            ),
          SizedBox(
            width: constraints.maxWidth.clamp(0.0, slot),
            child: HeaderMoreButton(
              page: HeaderActionPage.home,
              icon: loggedIn && !pinned.contains(HeaderAction.messages)
                  ? messageBadgeIcon(
                      mainController,
                      child: const Icon(Icons.more_vert),
                    )
                  : const Icon(Icons.more_vert),
              items: [
                for (final entry in more)
                  headerMenuItem(
                    label: entry.action.label,
                    icon: buttons[entry.action]!.icon,
                    onPressed: buttons[entry.action]!.open,
                  ),
              ],
            ),
          ),
        ],
      );
    }),
  );
}

Widget _profileIcon(MainController main, ColorScheme colors) {
  return Obx(() {
    if (!main.accountService.isLogin.value) {
      return CircleAvatar(
        radius: 17,
        backgroundColor: colors.onInverseSurface,
        child: Icon(Icons.person_rounded, size: 22, color: colors.primary),
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        NetworkImgLayer(
          type: .avatar,
          width: 34,
          height: 34,
          src: main.accountService.face.value,
        ),
        if (MineController.anonymity.value)
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.secondaryContainer,
              ),
              child: Icon(
                MdiIcons.incognito,
                size: 14,
                color: colors.onSecondaryContainer,
              ),
            ),
          ),
      ],
    );
  });
}

Widget userAvatar({
  required ColorScheme colorScheme,
  required MainController mainController,
}) => Obx(
  () {
    final loggedIn = mainController.accountService.isLogin.value;
    return SizedBox.square(
      dimension: loggedIn ? 34 : 38,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: loggedIn ? '我的' : '点击登录',
        onPressed: mainController.toMinePage,
        icon: _profileIcon(mainController, colorScheme),
      ),
    );
  },
);

void openMessages(MainController mainController) {
  if (!mainController.accountService.isLogin.value) return;
  mainController
    ..clearUnreadMsg()
    ..lastCheckUnreadAt = DateTime.now().millisecondsSinceEpoch;
  Get.toNamed('/whisper');
}

Widget messageBadgeIcon(
  MainController mainController, {
  Widget child = const Icon(Icons.notifications_none),
}) => Obx(() {
  final count = mainController.msgUnReadCount.value;
  final isNumBadge = mainController.msgBadgeMode == .number;
  return Badge(
    isLabelVisible: mainController.msgBadgeMode != .hidden && count != null,
    alignment: isNumBadge
        ? const Alignment(0.0, -0.85)
        : const Alignment(1.0, -0.85),
    label: isNumBadge && count != null ? Text(count) : null,
    child: child,
  );
});

Widget msgBadge(MainController mainController) => Obx(
  () => mainController.accountService.isLogin.value
      ? IconButton(
          tooltip: '消息',
          onPressed: () => openMessages(mainController),
          icon: messageBadgeIcon(mainController),
        )
      : const SizedBox.shrink(),
);
