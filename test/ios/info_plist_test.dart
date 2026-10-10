import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ios/Runner/Info.plist の必須キーが消えていないことを確認する。
// iOSのビルドはCIで検証していないため、キーの欠落（実機でのクラッシュや
// 配布の停止につながる）をここで機械的に検知する。
void main() {
  late String plist;

  setUpAll(() {
    plist = File('ios/Runner/Info.plist').readAsStringSync();
  });

  test('輸出コンプライアンス: 独自の暗号化を使わない旨を申告している', () {
    expect(
      RegExp(r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>')
          .hasMatch(plist),
      isTrue,
    );
  });

  test('保護リソースの利用目的の説明が揃っている', () {
    for (final key in [
      'NSFaceIDUsageDescription',
      'NSPhotoLibraryUsageDescription',
      'NSPhotoLibraryAddUsageDescription',
    ]) {
      expect(plist, contains('<key>$key</key>'), reason: key);
    }
  });

  test('招待リンク(aimaru://)とFCMバックグラウンド受信の設定がある', () {
    expect(plist, contains('<string>aimaru</string>'));
    expect(plist, contains('<string>remote-notification</string>'));
  });
}
