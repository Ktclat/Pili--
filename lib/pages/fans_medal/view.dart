import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/loading_widget/loading_widget.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/live/live_fans_medal/item.dart';
import 'package:PiliPlus/pages/fans_medal/controller.dart';
import 'package:PiliPlus/pages/fans_medal/medal_setting_mixin.dart';
import 'package:PiliPlus/pages/member/widget/medal_widget.dart';
import 'package:PiliPlus/utils/bili_colors.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

const _kMedalAlign = Alignment(-0.7, 0);
const _kBtnBorderRadius = BorderRadius.all(.circular(4));
const _kBtnPadding = EdgeInsets.symmetric(horizontal: 3, vertical: 2);

class FansMedalPage extends StatefulWidget {
  const FansMedalPage({super.key});

  @override
  State<FansMedalPage> createState() => _FansMedalPageState();
}

class _FansMedalPageState extends State<FansMedalPage> with MedalSettingMixin {
  late final FansMedalController _controller;
  @override
  FansMedalController get medalController => _controller;
  late ColorScheme colorScheme;

  @override
  void initState() {
    super.initState();
    _controller = FansMedalController.forAccount(Accounts.main);
    if (_controller.loadingState.value is Loading) {
      _controller.queryData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    colorScheme = .of(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() {
          final count = _controller.count.value;
          return Text('粉丝勋章${count != null ? '($count)' : ''}');
        }),
        actions: [
          IconButton(
            tooltip: '展示设置',
            onPressed: showMedalSettingDialog,
            icon: const Icon(Icons.settings),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: refreshIndicator(
        onRefresh: _controller.onRefresh,
        child: CustomScrollView(
          slivers: [
            ViewSliverSafeArea(
              sliver: Obx(() => _buildBody(_controller.loadingState.value)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(LoadingState<List<FansMedalItem>?> state) {
    return switch (state) {
      Loading() => linearLoading,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverList.builder(
                itemCount: response.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _header();
                  }

                  if (index == response.length) {
                    _controller.onLoadMore();
                  }

                  final item = response[index - 1];
                  return _buildItem(index, item);
                },
              )
            : HttpError(onReload: _controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _controller.onReload,
      ),
    };
  }

  Widget _buildItem(int index, FansMedalItem item) {
    final medal = item.medal;
    final isWearing = medal.wearingStatus == 1;
    final actionColor = isWearing ? BiliColors.linkBlue : BiliColors.linkPurple;
    final medalWidget = MedalWidget.fromMedalInfo(
      medal: item.uinfoMedal,
      padding: const .symmetric(horizontal: 6, vertical: 4),
    );
    const strutStyle = StrutStyle(leading: 0, height: 1, fontSize: 12);
    final child = Padding(
      padding: const .symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Align(alignment: _kMedalAlign, child: medalWidget),
          ),
          Expanded(
            flex: 6,
            child: GestureDetector(
              behavior: .translucent,
              onTap: () => Get.toNamed(
                '/member?mid=${item.uinfoMedal.ruid}',
              ),
              child: Padding(
                padding: const .symmetric(vertical: 12),
                child: Text(
                  item.anchorInfo.nickName,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${medal.intimacy}/${NumUtils.numFormat(medal.nextIntimacy)}',
              style: TextStyle(fontSize: 13, color: colorScheme.outline),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${medal.todayFeed}/${NumUtils.numFormat(medal.dayLimit)}',
              style: TextStyle(fontSize: 13, color: colorScheme.outline),
            ),
          ),
          Expanded(
            flex: 5,
            child: Align(
              alignment: .centerLeft,
              child: GestureDetector(
                onTap: () => isWearing
                    ? _controller.onTakeOff(item)
                    : _controller.onWear(item),
                behavior: .translucent,
                child: Container(
                  padding: _kBtnPadding,
                  decoration: BoxDecoration(
                    borderRadius: _kBtnBorderRadius,
                    border: .all(color: actionColor.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    isWearing ? '取消佩戴' : '佩戴',
                    style: TextStyle(
                      height: 1,
                      fontSize: 12,
                      color: actionColor,
                    ),
                    strutStyle: strutStyle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (index.isOdd) {
      return ColoredBox(
        color: colorScheme.isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainer,
        child: child,
      );
    }
    return child;
  }

  Widget _header() {
    return DefaultTextStyle(
      style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
      child: const Padding(
        padding: .fromLTRB(12, 0, 12, 10),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Align(alignment: _kMedalAlign, child: Text('勋章')),
            ),
            Expanded(flex: 6, child: Text('主播呢称')),
            Expanded(flex: 3, child: Text('累计')),
            Expanded(flex: 3, child: Text('获得')),
            Expanded(flex: 5, child: Text('操作')),
          ],
        ),
      ),
    );
  }
}
