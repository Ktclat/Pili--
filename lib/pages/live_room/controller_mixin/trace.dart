part of 'package:PiliPlus/pages/live_room/controller.dart';

mixin _LiveTraceMixin on GetxController, _LiveDataMixin {
  bool _traceRequested = false;
  bool get _canTrace =>
      _traceRequested &&
      !isClosed &&
      isLoaded.value &&
      roomInfoH5.rawValue?.roomInfo != null &&
      plPlayerController.visible &&
      plPlayerController.playerStatus.isPlaying &&
      heartbeat.isLogin &&
      identical(heartbeat, Accounts.heartbeat) &&
      !Pref.historyPause;

  late final _traceSession = LiveTraceSession(() => _canTrace);

  void _startLiveTraceTimer() {
    // A fresh request/response pair belongs exclusively to this playback session.
    LiveTraceReq? request;
    LiveTraceResp? previous;
    _traceSession.start((token) async {
      bool isCurrent() => !token.isCancelled && _canTrace;
      try {
        if (request == null) {
          final cookies = await heartbeat.cookieJar.loadForRequest(
            Uri.parse(HttpString.baseUrl),
          );
          if (!isCurrent()) return null;
          final buvid = cookies
              .firstWhereOrNull((c) => c.name == 'LIVE_BUVID')
              ?.value;
          final room = roomInfoH5.rawValue?.roomInfo;
          final anchor = ruid;
          if (buvid == null ||
              room?.parentAreaId == null ||
              room?.areaId == null ||
              anchor == null) {
            return null;
          }
          request = LiveTraceReq(
            parentAreaId: room!.parentAreaId!,
            areaId: room.areaId!,
            roomId: roomId,
            liveBuvid: buvid,
            ruid: anchor,
          );
        }
        final res = previous == null
            ? await LiveHttp.liveTraceE(
                traceReq: request!,
                heartbeat: heartbeat,
                token: token,
                isCurrent: isCurrent,
              )
            : await LiveHttp.liveTraceX(
                traceReq: request!,
                traceResp: previous!,
                heartbeat: heartbeat,
                token: token,
                isCurrent: isCurrent,
              );
        if (!isCurrent()) return null;
        previous = res.dataOrNull;
        return previous == null ? null : Duration(seconds: previous!.interval);
      } catch (error, stack) {
        if (isCurrent()) Utils.reportError(error, stack);
        return null;
      }
    });
  }
}
