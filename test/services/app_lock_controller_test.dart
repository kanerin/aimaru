import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aimaru/services/app_lock_controller.dart';

import '../helpers/fake_biometric_authenticator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBiometricAuthenticator biometrics;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // local_authはプラットフォームチャネル越しの呼び出しで単体テストから
    // 実行できないため、シングルトンの生体認証をフェイクに差し替える。
    biometrics = FakeBiometricAuthenticator();
    AppLockController.instance.biometrics = biometrics;
    // シングルトンなので前のテストの状態を引きずらないよう、
    // 新しいSharedPreferencesバックエンドに合わせて明示的に再読込する。
    await AppLockController.instance.load();
  });

  test('未設定の状態ではロックされていない', () async {
    final controller = AppLockController.instance;
    expect(controller.enabled, isFalse);
    expect(controller.locked, isFalse);
  });

  test('setEnabled(true, pin: ...)で有効化すると、直後はロックされない', () async {
    final controller = AppLockController.instance;
    await controller.setEnabled(true, pin: '1234');

    expect(controller.enabled, isTrue);
    expect(controller.locked, isFalse);
  });

  test('4桁でないPINを渡した場合は有効化されない', () async {
    final controller = AppLockController.instance;
    await controller.setEnabled(true, pin: '12');

    expect(controller.enabled, isFalse);
  });

  test('有効化した状態でloadすると起動直後からロックされる', () async {
    final controller = AppLockController.instance;
    await controller.setEnabled(true, pin: '1234');

    await controller.load();

    expect(controller.enabled, isTrue);
    expect(controller.locked, isTrue);
  });

  test('lock()でロックされ、正しいPINでunlockするとロックが解除される', () async {
    final controller = AppLockController.instance;
    await controller.setEnabled(true, pin: '1234');
    controller.lock();
    expect(controller.locked, isTrue);

    final wrongOk = await controller.unlock('0000');
    expect(wrongOk, isFalse);
    expect(controller.locked, isTrue);

    final ok = await controller.unlock('1234');
    expect(ok, isTrue);
    expect(controller.locked, isFalse);
  });

  test('無効化中はlock()を呼んでもロックされない', () {
    final controller = AppLockController.instance;
    controller.lock();
    expect(controller.locked, isFalse);
  });

  test('setEnabled(false)でロックも即座に解除される', () async {
    final controller = AppLockController.instance;
    await controller.setEnabled(true, pin: '1234');
    controller.lock();
    expect(controller.locked, isTrue);

    await controller.setEnabled(false);

    expect(controller.enabled, isFalse);
    expect(controller.locked, isFalse);
  });

  test('状態が変わるとリスナーに通知される', () async {
    final controller = AppLockController.instance;
    var notified = false;
    controller.addListener(() => notified = true);

    await controller.setEnabled(true, pin: '1234');

    expect(notified, isTrue);
  });

  group('生体認証での解除', () {
    test('アプリロックが無効なうちは生体認証を有効化できない', () async {
      final controller = AppLockController.instance;

      await controller.setBiometricEnabled(true);

      expect(controller.biometricEnabled, isFalse);
    });

    test('アプリロック有効時に生体認証を有効化でき、loadで復元される', () async {
      final controller = AppLockController.instance;
      await controller.setEnabled(true, pin: '1234');

      await controller.setBiometricEnabled(true);
      expect(controller.biometricEnabled, isTrue);

      await controller.load();
      expect(controller.biometricEnabled, isTrue);
    });

    test('生体認証がOFFなら端末へ問い合わせずcanUseBiometricsがfalse', () async {
      final controller = AppLockController.instance;
      await controller.setEnabled(true, pin: '1234');

      expect(await controller.canUseBiometrics(), isFalse);
    });

    test('端末が生体認証に非対応ならcanUseBiometricsはfalse', () async {
      final controller = AppLockController.instance;
      await controller.setEnabled(true, pin: '1234');
      await controller.setBiometricEnabled(true);
      biometrics.available = false;

      expect(await controller.canUseBiometrics(), isFalse);
    });

    test('認証に成功するとロックが解除される', () async {
      final controller = AppLockController.instance;
      await controller.setEnabled(true, pin: '1234');
      await controller.setBiometricEnabled(true);
      controller.lock();

      final ok = await controller.unlockWithBiometrics();

      expect(ok, isTrue);
      expect(controller.locked, isFalse);
      expect(biometrics.authenticateCalls, 1);
    });

    test('認証に失敗・キャンセルするとロックは維持される', () async {
      final controller = AppLockController.instance;
      await controller.setEnabled(true, pin: '1234');
      await controller.setBiometricEnabled(true);
      controller.lock();
      biometrics.succeeds = false;

      final ok = await controller.unlockWithBiometrics();

      expect(ok, isFalse);
      expect(controller.locked, isTrue);
    });

    test('生体認証がOFFなら端末へ問い合わせずに解除も行わない', () async {
      final controller = AppLockController.instance;
      await controller.setEnabled(true, pin: '1234');
      controller.lock();

      final ok = await controller.unlockWithBiometrics();

      expect(ok, isFalse);
      expect(controller.locked, isTrue);
      expect(biometrics.authenticateCalls, 0);
    });

    test('生体認証をONにしていてもPINでの解除は使える', () async {
      final controller = AppLockController.instance;
      await controller.setEnabled(true, pin: '1234');
      await controller.setBiometricEnabled(true);
      controller.lock();

      expect(await controller.unlock('1234'), isTrue);
      expect(controller.locked, isFalse);
    });

    test('アプリロックを無効化すると生体認証の設定も落ちる', () async {
      final controller = AppLockController.instance;
      await controller.setEnabled(true, pin: '1234');
      await controller.setBiometricEnabled(true);

      await controller.setEnabled(false);

      expect(controller.biometricEnabled, isFalse);
      await controller.load();
      expect(controller.biometricEnabled, isFalse);
    });
  });
}
