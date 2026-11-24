part of 'package:PiliPlus/pages/live_room/controller.dart';

mixin LiveLikeMixin on GetxController {
  Account get heartbeat;
  int get roomId;
  int? get ruid;

  Timer? _likeClickTimer;
  final RxInt likeClickTime = 0.obs;

  bool get _isCurrent =>
      !isClosed &&
      heartbeat.isLogin &&
      identical(heartbeat, Accounts.heartbeat);

  void onLikeTap() {
    if (!_isCurrent) {
      SmartDialog.showToast(
        heartbeat.isLogin ? '记录观看账号已切换，请重新进入直播间' : '记录观看账号未登录',
      );
      return;
    }
    likeClickTime.value++;
    _likeClickTimer?.cancel();
    _likeClickTimer = Timer(const Duration(milliseconds: 800), _sendLikes);
  }

  Future<void> _sendLikes() async {
    final count = likeClickTime.value;
    likeClickTime.value = 0;
    if (!_isCurrent) return;
    final res = await LiveHttp.liveLikeReport(
      account: heartbeat,
      clickTime: count,
      roomId: roomId,
      anchorId: ruid,
    );
    if (!_isCurrent) return;
    if (res.isSuccess) {
      SmartDialog.showToast('点赞成功');
    } else {
      res.toast();
    }
  }

  @override
  void onClose() {
    _likeClickTimer?.cancel();
    super.onClose();
  }
}
