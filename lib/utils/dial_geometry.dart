import 'dart:math' as math;
import 'dart:ui' show Offset;

// ── 時刻ダイヤルの角度計算（純粋関数のみ）─────────────────
//
// Flutterの標準の時刻ピッカーは選択円の大きさが48dp固定で、テーマからは
// 変えられない（_TimePickerDefaultsM3.dotRadius）。円が数字より大きく、
// 隣の目盛りに被って読みにくかったため、ダイヤルを自前で描いている。
// 描画・ジェスチャーから切り離せる計算だけをここへ置き、単体テストする。

/// 12時方向を0とし、時計回りに増える角度（ラジアン、[0, 2π)）。
double dialAngle(Offset point, Offset center) {
  final dx = point.dx - center.dx;
  final dy = point.dy - center.dy;
  // atan2(dx, -dy) で「真上が0・右回りが正」になる。
  final angle = math.atan2(dx, -dy);
  return angle < 0 ? angle + 2 * math.pi : angle;
}

/// 角度を divisions 等分の目盛り番号（[0, divisions)）へ丸める。
int dialValue(double angle, int divisions) {
  final unit = 2 * math.pi / divisions;
  return (angle / unit).round() % divisions;
}

/// 目盛り番号を、中心からの相対座標へ直す（半径 radius の円周上）。
Offset dialOffset(int value, int divisions, double radius) {
  final angle = 2 * math.pi * value / divisions;
  return Offset(radius * math.sin(angle), -radius * math.cos(angle));
}

/// タップ位置が内側のリング（24時間表示の12〜23）かどうか。
///
/// 外側リングと内側リングの中間より内側なら内側リングとみなす。
/// 中心付近（針の根元）は誤爆しやすいので、外側リング扱いにはしない。
bool isInnerRing({
  required double distanceFromCenter,
  required double outerRadius,
  required double innerRadius,
}) =>
    distanceFromCenter < (outerRadius + innerRadius) / 2;

/// 24時間ダイヤルで、指した位置から「時」を求める。
///
/// 外側リングが0〜11、内側リングが12〜23。
int hourFromPoint({
  required Offset point,
  required Offset center,
  required double outerRadius,
  required double innerRadius,
}) {
  final base = dialValue(dialAngle(point, center), 12);
  final inner = isInnerRing(
    distanceFromCenter: (point - center).distance,
    outerRadius: outerRadius,
    innerRadius: innerRadius,
  );
  return inner ? base + 12 : base;
}

/// 分ダイヤルで、指した位置から「分」を求める（1分刻み）。
int minuteFromPoint({required Offset point, required Offset center}) =>
    dialValue(dialAngle(point, center), 60);
