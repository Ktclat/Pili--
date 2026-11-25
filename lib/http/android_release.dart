import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/release_info.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';

Future<Object?> loadAndroidBuildInfo(ReleaseInfo release) async {
  final url = release.androidBuildInfoUrl;
  final digest = release.androidBuildInfoSha256;
  if (url == null || digest == null) return null;

  // Hash the original file bytes before decoding JSON, regardless of the CDN MIME type.
  final response = await Request().get<List<int>>(
    url,
    options: Options(
      responseType: ResponseType.bytes,
      extra: {'account': const NoAccount()},
    ),
  );
  final body = response.data;
  if (response.statusCode != 200 || body is! List<int>) {
    throw const HttpException('无法读取此版本的安装包信息');
  }
  final bytes = Request.responseBytesDecoder(body, response.headers.map);
  if (sha256.convert(bytes).toString() != digest) {
    throw const FormatException('安装包信息与发布记录不一致');
  }
  return jsonDecode(utf8.decode(bytes));
}
