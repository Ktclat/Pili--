import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/trusted_url.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

abstract final class UrlUtils {
  // 302重定向路由截取
  static Future<String?> parseRedirectUrl(String url) async {
    try {
      final source = Uri.parse(url);
      if (!TrustedUrl.isWebLink(source)) return null;
      final response = await Request.dio.headUri<void>(
        source,
        options: Options(
          followRedirects: false,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
          extra: {'account': AnonymousAccount()},
        ),
      );
      if ((response.statusCode ?? 0) < 300) return null;
      final location = response.headers.value('location');
      if (location == null || location.isEmpty) return null;
      final target = source.resolve(location);
      return TrustedUrl.isWebLink(target) ? target.toString() : null;
    } catch (_) {
      return null;
    }
  }

  // 匹配url路由跳转
  static Future<void> matchUrlPush(
    String pathSegment,
    String redirectUrl,
  ) async {
    final matchRes = IdUtils.matchAvorBv(input: pathSegment);
    if (matchRes.isNotEmpty) {
      final aid = matchRes.av;
      final bvid = matchRes.bv;
      final res = await SearchHttp.ab2cWithDimension(aid: aid, bvid: bvid);
      final cid = res?.cid;
      if (cid != null) {
        PageUtils.toVideoPage(
          aid: aid,
          bvid: bvid,
          cid: cid,
          dimension: res!.dimension,
          // title: res.title,
        );
      }
    } else {
      if (redirectUrl.isNotEmpty) {
        PageUtils.handleWebview(redirectUrl);
      } else {
        SmartDialog.showToast('matchUrlPush: $pathSegment');
      }
    }
  }
}
