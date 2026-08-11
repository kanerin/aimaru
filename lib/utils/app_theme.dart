import 'package:flutter/material.dart';

class AppColors {
  // ── Palette（淡いパステル基調）──
  static const navy        = Color(0xFFFBF6F3); // ページ背景（淡いオフホワイト）
  static const navyCard    = Color(0xFFFFFFFF); // カード・AppBar
  static const navySurface = Color(0xFFF4EEF8); // 入力欄・チップなどの面
  static const pink        = Color(0xFFF3CDD3);
  static const pinkAccent  = Color(0xFFE2A0AE);
  static const lavender    = Color(0xFF8B8FE0); // デフォルトのアクセントカラー（設定で変更可）
  static const lavenderSoft= Color(0xFFC7CAF2);
  static const cream       = Color(0xFF3A3550); // 見出し・強調テキスト
  static const creamDim    = Color(0xFF5B5470);
  static const textPrimary = Color(0xFF3A3550);
  static const textSecond  = Color(0xFF6B6480);
  static const textMuted   = Color(0xFF9C93AE);
  static const success     = Color(0xFF5FAE86);
  static const gold        = Color(0xFFE0B85C);
  static const background  = Color(0xFFFBF6F3);

  // 淡い背景に合わせた罫線色（旧 AppColors.hairline / white24 相当）
  static const hairline       = Color(0x1F3A3550);
  static const hairlineStrong = Color(0x3D3A3550);

  // ── 設定画面で選べるテーマカラー（アクセント）のプリセット ──
  static const accentPresets = <String, Color>{
    'ラベンダー': Color(0xFF8B8FE0),
    'ピンク':     Color(0xFFE28AA5),
    'ミント':     Color(0xFF63B79E),
    'ピーチ':     Color(0xFFE8A46B),
    'スカイ':     Color(0xFF6FA0DC),
  };

  // ── 予定/メンバーの色分け用（「誰の予定か」表示） ──
  static const partnerColor = Color(0xFFE8A46B); // パートナーの予定・アバターに使う固定色
}

// 現在選択中のアクセントカラー（Theme.of(context).colorScheme.primary）を
// あちこちのウィジェットから簡潔に参照するためのヘルパー。
Color appAccent(BuildContext context) => Theme.of(context).colorScheme.primary;

// アクセントを白に寄せた、淡いバリエーション（「今日」マーカーなどの背景用）
Color appAccentSoft(BuildContext context) =>
    Color.lerp(appAccent(context), Colors.white, 0.35)!;

class AppTheme {
  static ThemeData light(Color accent) => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.navy,
    colorScheme: ColorScheme.light(
      primary:   accent,
      secondary: AppColors.pinkAccent,
      surface:   AppColors.navyCard,
      onPrimary: Colors.white,
      onSurface: AppColors.textPrimary,
    ),
    fontFamily: 'NotoSansJP',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.navy,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.navyCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: AppColors.hairline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.navySurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide.none,
      ),
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? accent : null),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? accent.withValues(alpha: 0.5) : null),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: Colors.white,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.hairline, space: 1),
  );
}
