import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _Settings extends Fake implements Box<dynamic> {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      key == SettingBoxKey.openInBrowser ? false : defaultValue;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'malformed shared route returns its asynchronous error to the caller',
    () async {
      GStorage.setting = _Settings();

      // This supported URI reaches the real asynchronous router, whose CID
      // conversion fails before any navigation or network request can start.
      // The entry point must return that failure so its confirmation UI can
      // handle it instead of leaving an unhandled future in the application.
      await expectLater(
        PageUtils.handleWebview('bilibili://video/123?cid=abc'),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
