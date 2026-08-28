import 'package:aimaru/services/biometric_service.dart';

// local_authはプラットフォームチャネル越しの呼び出しで単体テストから実行できないため、
// AppLockControllerに差し込むための差し替え可能な実装。
class FakeBiometricAuthenticator implements BiometricAuthenticator {
  FakeBiometricAuthenticator({this.available = true, this.succeeds = true});

  bool available;
  bool succeeds;
  int authenticateCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate() async {
    authenticateCalls++;
    return succeeds;
  }
}
