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

  test('プライバシーマニフェストがあり、Runnerのリソースとして登録されている', () {
    // 2024年以降、App Storeへの提出にはPrivacyInfo.xcprivacyが求められる。
    final manifest = File('ios/Runner/PrivacyInfo.xcprivacy');
    expect(manifest.existsSync(), isTrue);
    final body = manifest.readAsStringSync();
    expect(RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>').hasMatch(body),
        isTrue);
    // shared_preferences(UserDefaults)の利用理由の申告
    expect(body, contains('NSPrivacyAccessedAPICategoryUserDefaults'));
    expect(body, contains('CA92.1'));

    // ファイルがあるだけではバンドルに入らないので、pbxprojの
    // Resourcesビルドフェーズに入っていることも確認する。
    final pbxproj =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(pbxproj,
        contains('PrivacyInfo.xcprivacy in Resources */ = {isa = PBXBuildFile'));
    expect(RegExp(r'PrivacyInfo\.xcprivacy in Resources \*/,').hasMatch(pbxproj),
        isTrue);
  });

  test('プッシュ通知のentitlements(aps-environment)があり、全ビルド構成で参照されている', () {
    // aps-environmentが無いとiOSはAPNsトークンを発行せず、FCM通知が届かない。
    final entitlements = File('ios/Runner/Runner.entitlements');
    expect(entitlements.existsSync(), isTrue);
    expect(entitlements.readAsStringSync(), contains('<key>aps-environment</key>'));

    final pbxproj =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    // Runnerターゲットの Debug / Release / Profile の3構成
    expect(
      'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
          .allMatches(pbxproj)
          .length,
      3,
    );
    expect(pbxproj, contains('path = Runner.entitlements;'));
  });

  test('デプロイメントターゲットがFirebaseプラグインの要求(iOS 15.0)以上', () {
    // firebase_core / firebase_messaging / cloud_firestore / firebase_auth の
    // podspecは iOS 15.0 以上を要求する。下回るとpod installが失敗する。
    final pbxproj =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final targets = RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);')
        .allMatches(pbxproj)
        .map((m) => double.parse(m.group(1)!))
        .toList();
    expect(targets, isNotEmpty);
    for (final t in targets) {
      expect(t, greaterThanOrEqualTo(15.0));
    }
  });
}
