import 'package:local_auth/local_auth.dart';

// ── 端末の生体認証（指紋・顔）───────────────────────────
// アプリロックのパスコード入力を、端末に登録済みの指紋・顔で置き換えるための層。
// PINと同じく端末ローカルの話で、Firestoreには一切保存しない。
//
// 呼び出しはプラットフォームチャネル越し（local_authプラグイン）なので、
// 単体テストからは実行できない。テスト側で差し替えられるよう、
// AppLockControllerが持つのは実装ではなくこのインターフェースにしてある。
abstract class BiometricAuthenticator {
  /// 端末が生体認証に対応し、かつ指紋・顔が1つ以上登録済みかどうか。
  Future<bool> isAvailable();

  /// 生体認証のダイアログを出し、本人と確認できたらtrueを返す。
  Future<bool> authenticate();
}

class BiometricService implements BiometricAuthenticator {
  BiometricService({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  // 端末が非対応・未登録なだけでなく、プラグインが解決できない環境
  // （プラットフォームチャネルの無いテスト環境など）でも例外を投げずに
  // falseへ倒す。生体認証はあくまで補助で、PINでの解除は常に残るため。
  @override
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'アプリのロックを解除します',
        options: const AuthenticationOptions(
          // 端末のパスコード（画面ロック）へのフォールバックは使わない。
          // アプリロックは「端末を渡した相手に中身を見せない」ための機能なので、
          // 端末のロックを開けられる相手が素通りできては意味が無い。
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
