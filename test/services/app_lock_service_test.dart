import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aimaru/services/app_lock_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('初期状態では無効', () async {
    final service = AppLockService();
    expect(await service.isEnabled(), isFalse);
  });

  test('setPinで有効化され、正しいPINでverifyPinがtrueを返す', () async {
    final service = AppLockService();
    await service.setPin('1234');

    expect(await service.isEnabled(), isTrue);
    expect(await service.verifyPin('1234'), isTrue);
    expect(await service.verifyPin('0000'), isFalse);
  });

  test('PINを設定していない状態でverifyPinはfalseを返す', () async {
    final service = AppLockService();
    expect(await service.verifyPin('1234'), isFalse);
  });

  test('disableでPINが消え、無効化される', () async {
    final service = AppLockService();
    await service.setPin('1234');

    await service.disable();

    expect(await service.isEnabled(), isFalse);
    expect(await service.verifyPin('1234'), isFalse);
  });
}
