// ── 金額の表示（3桁区切り・円）───────────────────────────
// 変更履歴の文言（domain）と画面（presentation）で同じ書式を使うため、
// Flutterに依存しない形でここに置く。

// 205000 → '205,000'、-35000 → '-35,000'
String formatAmount(int amount) {
  final negative = amount < 0;
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}

// 205000 → '205,000円'
String formatYen(int amount) => '${formatAmount(amount)}円';

// 差分の表示。5000 → '+5,000円'、-5000 → '-5,000円'、0 → '±0円'
String formatSignedYen(int diff) {
  if (diff == 0) return '±0円';
  return diff > 0 ? '+${formatYen(diff)}' : formatYen(diff);
}

// 入力欄の文字列を金額に。'120,000' や '120000円' のような表記も受け付け、
// 数字が1つも無ければnull。全角数字も半角として読む。
int? parseAmount(String text) {
  final normalized = text.replaceAllMapped(
    RegExp('[０-９]'),
    (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFF10 + 0x30),
  );
  final negative = normalized.trim().startsWith('-') || normalized.trim().startsWith('−');
  final digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  final value = int.tryParse(digits);
  if (value == null) return null;
  return negative ? -value : value;
}
