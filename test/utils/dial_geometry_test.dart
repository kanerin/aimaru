import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/utils/dial_geometry.dart';

// 時刻ダイヤルの角度計算。
//
// Flutter標準の時刻ピッカーは選択円が48dp固定で数字に被って読みにくいため、
// ダイヤルを自前で描いている。描画から切り離せる計算はここで固定しておく。
void main() {
  const center = Offset(100, 100);

  group('dialAngle', () {
    test('真上は0', () {
      expect(dialAngle(const Offset(100, 20), center), closeTo(0, 0.001));
    });

    test('右は90度（時計回りに増える）', () {
      expect(dialAngle(const Offset(180, 100), center),
          closeTo(math.pi / 2, 0.001));
    });

    test('真下は180度', () {
      expect(dialAngle(const Offset(100, 180), center),
          closeTo(math.pi, 0.001));
    });

    test('左は270度（負の角度へ折り返さない）', () {
      expect(dialAngle(const Offset(20, 100), center),
          closeTo(3 * math.pi / 2, 0.001));
    });
  });

  group('dialValue', () {
    test('12等分なら真上が0、右が3', () {
      expect(dialValue(0, 12), 0);
      expect(dialValue(math.pi / 2, 12), 3);
      expect(dialValue(math.pi, 12), 6);
      expect(dialValue(3 * math.pi / 2, 12), 9);
    });

    test('一周ぶんの角度は0へ戻る（11.5目盛りぶんでも12にならない）', () {
      expect(dialValue(2 * math.pi - 0.01, 12), 0);
    });

    test('60等分なら分として読める', () {
      expect(dialValue(math.pi / 2, 60), 15);
      expect(dialValue(math.pi, 60), 30);
    });

    test('目盛りの中間は近いほうへ丸める', () {
      final unit = 2 * math.pi / 60;
      expect(dialValue(unit * 7.4, 60), 7);
      expect(dialValue(unit * 7.6, 60), 8);
    });
  });

  group('dialOffset', () {
    test('0は真上（yが負）', () {
      final o = dialOffset(0, 12, 100);
      expect(o.dx, closeTo(0, 0.001));
      expect(o.dy, closeTo(-100, 0.001));
    });

    test('3は右（xが正）', () {
      final o = dialOffset(3, 12, 100);
      expect(o.dx, closeTo(100, 0.001));
      expect(o.dy, closeTo(0, 0.001));
    });

    test('dialAngleと往復して同じ目盛りに戻る', () {
      for (var v = 0; v < 12; v++) {
        final point = center + dialOffset(v, 12, 80);
        expect(dialValue(dialAngle(point, center), 12), v);
      }
    });
  });

  group('hourFromPoint', () {
    // 外側リングが0〜11、内側リングが12〜23。
    test('外側リングの真上は0時', () {
      expect(
        hourFromPoint(
          point: const Offset(100, 10),
          center: center,
          outerRadius: 90,
          innerRadius: 50,
        ),
        0,
      );
    });

    test('内側リングの真上は12時', () {
      expect(
        hourFromPoint(
          point: const Offset(100, 50),
          center: center,
          outerRadius: 90,
          innerRadius: 50,
        ),
        12,
      );
    });

    test('外側リングの右は3時、内側リングの右は15時', () {
      expect(
        hourFromPoint(
          point: const Offset(190, 100),
          center: center,
          outerRadius: 90,
          innerRadius: 50,
        ),
        3,
      );
      expect(
        hourFromPoint(
          point: const Offset(150, 100),
          center: center,
          outerRadius: 90,
          innerRadius: 50,
        ),
        15,
      );
    });

    test('リングの境目は中間で切り替わる', () {
      // outer 90 / inner 50 の中間は 70。
      expect(
        hourFromPoint(
          point: const Offset(100, 100 - 71),
          center: center,
          outerRadius: 90,
          innerRadius: 50,
        ),
        0,
        reason: '71は中間より外側',
      );
      expect(
        hourFromPoint(
          point: const Offset(100, 100 - 69),
          center: center,
          outerRadius: 90,
          innerRadius: 50,
        ),
        12,
        reason: '69は中間より内側',
      );
    });
  });

  group('minuteFromPoint', () {
    test('真上は0分、右は15分', () {
      expect(minuteFromPoint(point: const Offset(100, 20), center: center), 0);
      expect(minuteFromPoint(point: const Offset(180, 100), center: center), 15);
    });

    test('1分刻みで読める', () {
      final point = center + dialOffset(37, 60, 80);
      expect(minuteFromPoint(point: point, center: center), 37);
    });
  });
}
