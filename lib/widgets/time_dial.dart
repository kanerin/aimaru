import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../utils/dial_geometry.dart';

/// ダイヤルで今どちらを選んでいるか。
enum TimeDialMode { hour, minute }

/// 選択中の目盛りを示す円の半径。
///
/// Flutter標準の時刻ピッカーはここが24（直径48dp）で固定されており、
/// 数字より大きく隣の目盛りにも被って読みにくかった。自前で描くことで
/// 数字にちょうど収まる大きさにしている。
const double kTimeDialSelectorRadius = 15;

/// 時刻を選ぶダイヤル。
///
/// 24時間表示。時は外側リングが0〜11、内側リングが12〜23。
/// 分は1分刻みで、数字は5分ごとに描く（すべて描くと潰れて読めないため）。
class TimeDial extends StatelessWidget {
  final TimeOfDay value;
  final TimeDialMode mode;
  final ValueChanged<TimeOfDay> onChanged;

  /// 指を離したとき（時→分へ進めるのに使う）。
  final VoidCallback? onSettled;

  /// ダイヤルの一辺（正方形）。
  final double size;

  const TimeDial({
    super.key,
    required this.value,
    required this.mode,
    required this.onChanged,
    this.onSettled,
    this.size = 256,
  });

  // 外側リング・内側リングの半径を、ダイヤルの大きさから決める。
  // 内側リングは目盛りの間隔が狭くなるので、選択円(直径30)が隣に
  // 被らない程度には半径を残す（240pxのとき間隔は約35px）。
  static double _outerRadius(double size) => size / 2 - 22;
  static double _innerRadius(double size) => size / 2 - 52;

  void _updateFromPoint(Offset local, Size box) {
    final center = Offset(box.width / 2, box.height / 2);
    if (mode == TimeDialMode.hour) {
      final hour = hourFromPoint(
        point: local,
        center: center,
        outerRadius: _outerRadius(box.shortestSide),
        innerRadius: _innerRadius(box.shortestSide),
      );
      if (hour != value.hour) onChanged(value.replacing(hour: hour));
    } else {
      final minute = minuteFromPoint(point: local, center: center);
      if (minute != value.minute) onChanged(value.replacing(minute: minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    // ダイアログの中に置くため高さが定まらない。大きさは呼び出し側から
    // 決め打ちで受け取り、正方形として扱う（LayoutBuilderだと
    // 高さが無制限になって描けない）。
    final box = Size(size, size);

    return SizedBox(
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _updateFromPoint(d.localPosition, box),
        onTapUp: (_) => onSettled?.call(),
        onPanStart: (d) => _updateFromPoint(d.localPosition, box),
        onPanUpdate: (d) => _updateFromPoint(d.localPosition, box),
        onPanEnd: (_) => onSettled?.call(),
        child: CustomPaint(
          size: box,
          painter: _TimeDialPainter(
            value: value,
            mode: mode,
            accent: appAccent(context),
            background: AppColors.navySurface,
            labelColor: AppColors.textPrimary,
            selectedLabelColor: Colors.white,
            textDirection: Directionality.of(context),
          ),
        ),
      ),
    );
  }
}

class _TimeDialPainter extends CustomPainter {
  final TimeOfDay value;
  final TimeDialMode mode;
  final Color accent;
  final Color background;
  final Color labelColor;
  final Color selectedLabelColor;
  final TextDirection textDirection;

  _TimeDialPainter({
    required this.value,
    required this.mode,
    required this.accent,
    required this.background,
    required this.labelColor,
    required this.selectedLabelColor,
    required this.textDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dialRadius = size.shortestSide / 2;
    final outerRadius = TimeDial._outerRadius(size.shortestSide);
    final innerRadius = TimeDial._innerRadius(size.shortestSide);

    canvas.drawCircle(center, dialRadius, Paint()..color = background);

    // 針と選択円。針は選択円の中心で止め、円からはみ出させない。
    final selected = _selectedOffset(outerRadius, innerRadius);
    final handPaint = Paint()
      ..color = accent
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, center + selected, handPaint);
    canvas.drawCircle(center, 3, Paint()..color = accent);
    canvas.drawCircle(
      center + selected,
      kTimeDialSelectorRadius,
      Paint()..color = accent,
    );

    if (mode == TimeDialMode.hour) {
      for (var h = 0; h < 12; h++) {
        _label(canvas, center, dialOffset(h, 12, outerRadius),
            h.toString().padLeft(2, '0'), h == value.hour);
      }
      for (var h = 12; h < 24; h++) {
        _label(canvas, center, dialOffset(h - 12, 12, innerRadius),
            h.toString(), h == value.hour, small: true);
      }
    } else {
      // 60個すべては潰れて読めないので数字は5分ごと。選択中がその間の分なら、
      // 円だけがその位置に出る（数字は最寄りの5分に残る）。
      for (var m = 0; m < 60; m += 5) {
        _label(canvas, center, dialOffset(m, 60, outerRadius),
            m.toString().padLeft(2, '0'), m == value.minute);
      }
    }
  }

  Offset _selectedOffset(double outerRadius, double innerRadius) {
    if (mode == TimeDialMode.minute) {
      return dialOffset(value.minute, 60, outerRadius);
    }
    return value.hour < 12
        ? dialOffset(value.hour, 12, outerRadius)
        : dialOffset(value.hour - 12, 12, innerRadius);
  }

  void _label(Canvas canvas, Offset center, Offset offset, String text,
      bool selected, {bool small = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: small ? 12 : 14,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? selectedLabelColor : labelColor,
        ),
      ),
      textDirection: textDirection,
    )..layout();
    final position = center + offset -
        Offset(painter.width / 2, painter.height / 2);
    painter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _TimeDialPainter old) =>
      old.value != value || old.mode != mode || old.accent != accent;
}
