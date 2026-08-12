import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

// ── フォーム内の見出し ──────────────────────────────
// 予定の作成フォームとGoogleカレンダーの予定編集で同じ見出しを使う。
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(
      fontSize: 11, letterSpacing: 1, color: AppColors.textMuted, fontWeight: FontWeight.w600,
    )),
  );
}
