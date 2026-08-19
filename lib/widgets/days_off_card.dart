import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/couple_service.dart';
import '../utils/app_theme.dart';

// ── 設定画面に置く「基本の休日」カード ──────────────────
// 2人が普段休みの曜日を登録する。「2人の空き時間」はここで指定した曜日と
// 祝日だけを探索対象にするため、平日の夜のような実際には会えない時間帯が
// 候補に並ばなくなる。土日休みとは限らない職種のために曜日は自由に選べる。
//
// 端末ローカルではなくカップルのドキュメントに保存するので、
// どちらが設定しても2人に反映される。
class DaysOffCard extends StatefulWidget {
  final String coupleId;
  final List<int> initialDaysOff;
  final bool initialHolidaysAreDaysOff;
  final void Function(List<int> daysOff, bool holidaysAreDaysOff)? onSaved;

  // テスト用の注入ポイント。未指定時は本番のCoupleServiceを使う。
  final CoupleService? coupleServiceOverride;

  const DaysOffCard({
    super.key,
    required this.coupleId,
    this.initialDaysOff = CoupleModel.defaultDaysOff,
    this.initialHolidaysAreDaysOff = true,
    this.onSaved,
    this.coupleServiceOverride,
  });

  @override
  State<DaysOffCard> createState() => _DaysOffCardState();
}

class _DaysOffCardState extends State<DaysOffCard> {
  CoupleService? _coupleServiceInstance;
  CoupleService get _coupleService =>
      widget.coupleServiceOverride ?? (_coupleServiceInstance ??= CoupleService());

  late Set<int> _daysOff = {...widget.initialDaysOff};
  late bool _holidaysAreDaysOff = widget.initialHolidaysAreDaysOff;
  bool _saving = false;

  // DateTime.monday=1 〜 DateTime.sunday=7 の並びで表示する
  static const _labels = <int, String>{
    DateTime.monday: '月',
    DateTime.tuesday: '火',
    DateTime.wednesday: '水',
    DateTime.thursday: '木',
    DateTime.friday: '金',
    DateTime.saturday: '土',
    DateTime.sunday: '日',
  };

  @override
  void didUpdateWidget(covariant DaysOffCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 親（設定画面）が非同期でカップル情報を読み込み終えた後に初期値が
    // 確定するため、その変化だけ追従する。
    if (oldWidget.initialDaysOff != widget.initialDaysOff) {
      _daysOff = {...widget.initialDaysOff};
    }
    if (oldWidget.initialHolidaysAreDaysOff != widget.initialHolidaysAreDaysOff) {
      _holidaysAreDaysOff = widget.initialHolidaysAreDaysOff;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final daysOff = _daysOff.toList()..sort();
    try {
      await _coupleService.setDaysOff(
        widget.coupleId,
        daysOff: daysOff,
        holidaysAreDaysOff: _holidaysAreDaysOff,
      );
      widget.onSaved?.call(daysOff, _holidaysAreDaysOff);
    } catch (_) {
      // 保存に失敗したまま黙って進むと、設定できたように見えて次回開くと
      // 元に戻っている、という分かりにくい状態になる
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('休みの設定を保存できませんでした')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleDay(int weekday) async {
    setState(() {
      if (!_daysOff.remove(weekday)) _daysOff.add(weekday);
    });
    await _save();
  }

  // 選択中の曜日を折り返さない1行のサマリーにして、プルダウンの閉じた
  // 状態に表示する（月〜日の並び順で表示する）
  String get _daysOffSummary {
    if (_daysOff.isEmpty) return '未選択';
    return _labels.entries
        .where((e) => _daysOff.contains(e.key))
        .map((e) => e.value)
        .join('・');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(
              child: Text('普段の休み', style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
              )),
            ),
            if (_saving)
              SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: appAccent(context)),
              ),
          ]),
          const SizedBox(height: 4),
          const Text(
            '「2人の空き時間」はここで選んだ曜日から探します',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          MenuAnchor(
            style: MenuStyle(
              backgroundColor: const WidgetStatePropertyAll(AppColors.navySurface),
              shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.hairline),
              )),
            ),
            builder: (context, controller, child) {
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _saving
                    ? null
                    : () => controller.isOpen ? controller.close() : controller.open(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.navyCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _daysOffSummary,
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, color: AppColors.textMuted),
                    ],
                  ),
                ),
              );
            },
            menuChildren: _labels.entries.map((e) {
              final selected = _daysOff.contains(e.key);
              return CheckboxMenuButton(
                value: selected,
                // 選んでもメニューを閉じず、複数の曜日を続けて選べるようにする
                closeOnActivate: false,
                onChanged: _saving ? null : (_) => _toggleDay(e.key),
                child: Text('${e.value}曜日'),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          // SwitchListTile は背景色付きのContainerの中に置くと
          // 「インク効果が見えなくなる」とFlutterがアサーションを出すため、
          // このカードでは素のRow + Switchで組む。
          Row(children: [
            const Expanded(
              child: Text('祝日も休みにする', style: TextStyle(
                fontSize: 13, color: AppColors.textSecond,
              )),
            ),
            Switch(
              value: _holidaysAreDaysOff,
              onChanged: _saving
                  ? null
                  : (v) async {
                      setState(() => _holidaysAreDaysOff = v);
                      await _save();
                    },
              activeThumbColor: appAccent(context),
            ),
          ]),
        ],
      ),
    );
  }
}
