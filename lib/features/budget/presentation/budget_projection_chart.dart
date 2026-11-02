import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../utils/app_theme.dart';
import '../domain/budget_result.dart';
import '../domain/year_month.dart';
import 'budget_widgets.dart';

// 1本の線（1つのプランの貯金推移）
class ProjectionSeries {
  final String label;
  final Color color;
  final List<ProjectionPoint> points;
  final int startingBalance;
  final YearMonth start; // 推移の開始月（この月の入金前 = startingBalance）
  final int? targetAmount;

  const ProjectionSeries({
    required this.label,
    required this.color,
    required this.points,
    required this.startingBalance,
    required this.start,
    this.targetAmount,
  });
}

// ── 貯金推移の折れ線グラフ ─────────────────────────────
// 複数のプランを同じ時間軸に重ねて、月次の残高と目標ラインを描く。
// 依存パッケージを増やさないよう CustomPainter で描く（表示する情報は
// 「線が目標ラインをいつ越えるか」だけなので、凝ったグラフ部品は要らない）。
class BudgetProjectionChart extends StatelessWidget {
  final List<ProjectionSeries> series;
  final double height;

  const BudgetProjectionChart({super.key, required this.series, this.height = 240});

  @override
  Widget build(BuildContext context) {
    final summary = series
        .map((s) => '${s.label}: ${s.points.isEmpty ? 'データなし' : '${s.points.last.yearMonth.year}年'
            '${s.points.last.yearMonth.month}月に${formatManYen(s.points.last.balance)}円'}')
        .join('、');
    return Semantics(
      label: '貯金推移グラフ。$summary',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _ProjectionPainter(series: series)),
      ),
    );
  }
}

class _ProjectionPainter extends CustomPainter {
  final List<ProjectionSeries> series;

  _ProjectionPainter({required this.series});

  static const _leftAxis = 52.0;
  static const _bottomAxis = 22.0;
  static const _topPad = 8.0;
  static const _rightPad = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final withData = series.where((s) => s.points.isNotEmpty).toList();
    if (withData.isEmpty) {
      _drawText(canvas, '表示できる推移がありません', Offset(size.width / 2, size.height / 2),
          align: TextAlign.center, color: AppColors.textMuted, fontSize: 12);
      return;
    }

    // 時間軸: 全プランの開始月（入金前の点）〜最も遅い期限
    final start = withData.map((s) => s.start).reduce((a, b) => a.isBefore(b) ? a : b);
    final end = withData.map((s) => s.points.last.yearMonth).reduce((a, b) => a.isAfter(b) ? a : b);
    final totalMonths = math.max(1, start.monthsUntil(end) + 1);

    // 縦軸: 0〜（最大残高・目標額の大きい方）を切りのいい値に
    var maxValue = 0;
    for (final s in withData) {
      maxValue = math.max(maxValue, s.startingBalance);
      for (final p in s.points) {
        maxValue = math.max(maxValue, p.balance);
      }
      if (s.targetAmount != null) maxValue = math.max(maxValue, s.targetAmount!);
    }
    final yMax = _niceCeil(math.max(maxValue, 10000));

    final chart = Rect.fromLTRB(_leftAxis, _topPad, size.width - _rightPad, size.height - _bottomAxis);
    double x(YearMonth ym) => chart.left + chart.width * (start.monthsUntil(ym) / totalMonths);
    double y(int v) => chart.bottom - chart.height * (v.clamp(0, yMax) / yMax);

    // 目盛り（横線4本）
    final gridPaint = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final v = yMax * i ~/ 4;
      final yy = y(v);
      canvas.drawLine(Offset(chart.left, yy), Offset(chart.right, yy), gridPaint);
      _drawText(canvas, formatManYen(v), Offset(chart.left - 4, yy - 6), align: TextAlign.right);
    }

    // 横軸ラベル（最初・中間・最後）。端のラベルはグラフの外へはみ出さないよう
    // 最初は左揃え、最後は右揃えにする（最後の点は月末＝右端に置いている）。
    _drawText(canvas, '${start.year}/${start.month}', Offset(chart.left, chart.bottom + 5));
    if (totalMonths >= 3) {
      final mid = start.addMonths(totalMonths ~/ 2);
      _drawText(canvas, '${mid.year}/${mid.month}', Offset(x(mid), chart.bottom + 5), align: TextAlign.center);
    }
    if (end != start) {
      _drawText(canvas, '${end.year}/${end.month}', Offset(chart.right, chart.bottom + 5), align: TextAlign.right);
    }

    // 目標ライン（プランごとに違う目標額なら、それぞれの色で点線）
    final targets = <int, Color>{};
    for (final s in withData) {
      if (s.targetAmount != null && s.targetAmount! > 0) targets.putIfAbsent(s.targetAmount!, () => s.color);
    }
    for (final entry in targets.entries) {
      final ty = y(entry.key);
      _drawDashedLine(canvas, Offset(chart.left, ty), Offset(chart.right, ty),
          Paint()
            ..color = targets.length == 1 ? AppColors.gold : entry.value.withValues(alpha: 0.7)
            ..strokeWidth = 1.5);
      _drawText(canvas, '目標 ${formatManYen(entry.key)}', Offset(chart.right - 2, ty - 15),
          align: TextAlign.right, color: const Color(0xFFB8862B));
    }

    // 推移の線
    for (final s in withData) {
      final path = Path()..moveTo(x(s.start), y(s.startingBalance));
      for (final p in s.points) {
        // 点は「その月の入金後」なので、月の右端（翌月の開始位置）に置く
        path.lineTo(x(p.yearMonth.addMonths(1)), y(p.balance));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  // 1, 2, 2.5, 5 × 10^n のうち value 以上で最小のもの
  static int _niceCeil(int value) {
    final magnitude = math.pow(10, (math.log(value) / math.ln10).floor()).toInt();
    for (final f in [1.0, 2.0, 2.5, 5.0, 10.0]) {
      final candidate = (magnitude * f).round();
      if (candidate >= value) return candidate;
    }
    return magnitude * 10;
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    final total = (to - from).distance;
    final direction = (to - from) / total;
    var drawn = 0.0;
    while (drawn < total) {
      final segEnd = math.min(drawn + dash, total);
      canvas.drawLine(from + direction * drawn, from + direction * segEnd, paint);
      drawn = segEnd + gap;
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset anchor, {
    TextAlign align = TextAlign.left,
    Color color = AppColors.textMuted,
    double fontSize = 9.5,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: fontSize, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => anchor.dx - painter.width,
      TextAlign.center => anchor.dx - painter.width / 2,
      _ => anchor.dx,
    };
    painter.paint(canvas, Offset(dx, anchor.dy));
  }

  @override
  bool shouldRepaint(covariant _ProjectionPainter oldDelegate) => oldDelegate.series != series;
}
