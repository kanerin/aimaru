import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aimaru/services/app_lock_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
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
}
