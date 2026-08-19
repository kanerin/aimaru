import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/anniversary_service.dart';
import '../services/couple_service.dart';
import '../utils/anniversary_calculator.dart';
import '../utils/app_theme.dart';
import '../widgets/anniversary_card.dart';
import '../widgets/next_meeting_card.dart';

// ── 記念日タブ ────────────────────────────────────────
// 旧・思い出タブの跡地。設定画面に埋もれていた「次に会う日」「記念日」
// （付き合い始めた日）「記念日リスト」（複数記念日）を1画面へ統合し、
// メニューからすぐ開けるようにした。設定画面からはこれらのセクションを
// 削除し、ここへ一本化している。
class AnniversaryHubScreen extends StatefulWidget {
  final String coupleId;

  // テスト用の注入ポイント。未指定時は本番のサービス/DatePicker/現在時刻を使う。
  final CoupleService? coupleServiceOverride;
  final AnniversaryService? anniversaryServiceOverride;
  final Stream<List<AnniversaryItem>>? anniversariesStreamOverride;
  final DateTime Function()? nowOverride;
  final Future<DateTime?> Function(BuildContext context, DateTime? initial)? pickDateOverride;
  // getMyCoupleの非同期読み込みを待たずにテストできるよう、既知の初期値を注入する
  final CoupleModel? initialCoupleOverride;

  const AnniversaryHubScreen({
    super.key,
    required this.coupleId,
    this.coupleServiceOverride,
    this.anniversaryServiceOverride,
    this.anniversariesStreamOverride,
    this.nowOverride,
    this.pickDateOverride,
    this.initialCoupleOverride,
  });

  @override
  State<AnniversaryHubScreen> createState() => _AnniversaryHubScreenState();
}

class _AnniversaryHubScreenState extends State<AnniversaryHubScreen> {
  CoupleService? _coupleServiceInstance;
  CoupleService get _coupleService =>
      widget.coupleServiceOverride ?? (_coupleServiceInstance ??= CoupleService());

  AnniversaryService? _anniversaryServiceInstance;
  AnniversaryService get _anniversaryService =>
      widget.anniversaryServiceOverride ?? (_anniversaryServiceInstance ??= AnniversaryService());

  late final Stream<List<AnniversaryItem>> _anniversariesStream =
      widget.anniversariesStreamOverride ?? _anniversaryService.watchAnniversaries(widget.coupleId);

  CoupleModel? _couple;
  bool _loadingCouple = true;

  DateTime get _now => (widget.nowOverride ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCoupleOverride;
    if (initial != null) {
      _couple = initial;
      _loadingCouple = false;
    } else {
      _loadCouple();
    }
  }

  Future<void> _loadCouple() async {
    final couple = await _coupleService.getMyCouple();
    if (mounted) {
      setState(() {
        _couple = couple;
        _loadingCouple = false;
      });
    }
  }

  Future<void> _addAnniversary() async {
    final titleController = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('記念日を追加'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: '例: プロポーズ記念日'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, titleController.text.trim()),
            child: const Text('次へ'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty || !mounted) return;

    final now = _now;
    final date = widget.pickDateOverride != null
        ? await widget.pickDateOverride!(context, now)
        : await showDatePicker(
            context: context,
            initialDate: now,
            firstDate: DateTime(now.year - 50),
            lastDate: now, // 未来の記念日は選べない（daysTogetherの計算を単純に保つため）
          );
    if (date == null || !mounted) return;

    await _anniversaryService.addAnniversary(widget.coupleId, title, date);
  }

  Future<void> _deleteAnniversary(AnniversaryItem item) async {
    await _anniversaryService.deleteAnniversary(item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('記念日')),
      body: _loadingCouple
          ? Center(child: CircularProgressIndicator(color: appAccent(context)))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                NextMeetingCard(
                  coupleId: widget.coupleId,
                  initialNextMeetingDate: _couple?.nextMeetingDate,
                  coupleServiceOverride: widget.coupleServiceOverride,
                  pickDateOverride: widget.pickDateOverride,
                  nowOverride: widget.nowOverride,
                  onSaved: (date) => setState(() {
                    final couple = _couple;
                    if (couple != null) {
                      _couple = CoupleModel(
                        id: couple.id,
                        memberIds: couple.memberIds,
                        inviteCode: couple.inviteCode,
                        createdAt: couple.createdAt,
                        anniversary: couple.anniversary,
                        nextMeetingDate: date,
                        daysOff: couple.daysOff,
                        holidaysAreDaysOff: couple.holidaysAreDaysOff,
                      );
                    }
                  }),
                ),
                const SizedBox(height: 16),
                AnniversaryCard(
                  coupleId: widget.coupleId,
                  initialAnniversary: _couple?.anniversary,
                  coupleServiceOverride: widget.coupleServiceOverride,
                  pickDateOverride: widget.pickDateOverride,
                  nowOverride: widget.nowOverride,
                  onSaved: (date) => setState(() {
                    final couple = _couple;
                    if (couple != null) {
                      _couple = CoupleModel(
                        id: couple.id,
                        memberIds: couple.memberIds,
                        inviteCode: couple.inviteCode,
                        createdAt: couple.createdAt,
                        anniversary: date,
                        nextMeetingDate: couple.nextMeetingDate,
                        daysOff: couple.daysOff,
                        holidaysAreDaysOff: couple.holidaysAreDaysOff,
                      );
                    }
                  }),
                ),
                const SizedBox(height: 24),
                const Text('記念日リスト', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted,
                )),
                const SizedBox(height: 10),
                _AnniversaryListSection(
                  stream: _anniversariesStream,
                  now: _now,
                  onAdd: _addAnniversary,
                  onDelete: _deleteAnniversary,
                ),
              ],
            ),
    );
  }
}

// プロポーズ・入籍日など、付き合い始めた日以外の記念日をまとめて管理する。
// 単独の全画面（旧AnniversariesScreen）ではなく、この画面内に埋め込む
// セクションとして持たせるため、外側のListViewの中でColumnとして描く
// （内部で別にスクロールさせるとジェスチャーが競合するため、件数を
// 予定するリストではなく短いリスト向けにColumnで組んでいる）。
class _AnniversaryListSection extends StatelessWidget {
  final Stream<List<AnniversaryItem>> stream;
  final DateTime now;
  final VoidCallback onAdd;
  final void Function(AnniversaryItem item) onDelete;

  const _AnniversaryListSection({
    required this.stream,
    required this.now,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AnniversaryItem>>(
      stream: stream,
      builder: (context, snap) {
        // hasDataだけを見ていると、権限エラー等でストリームがエラーに
        // 落ちたときに無限ローディングのまま固まる
        // （本番でFirestoreルール未反映のまま実際に発生した不具合と同じ経路）。
        if (snap.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('読み込みに失敗しました\nしばらくしてから開き直してください',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
          );
        }
        if (!snap.hasData) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator(color: appAccent(context))),
          );
        }
        final items = List<AnniversaryItem>.from(snap.data!)
          ..sort((a, b) => summarizeAnniversary(a.date, now).daysUntilNextAnniversary
              .compareTo(summarizeAnniversary(b.date, now).daysUntilNextAnniversary));
        return Column(
          children: [
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('まだ記念日がありません\nプロポーズや入籍日など、追いたい記念日を登録しましょう',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
              )
            else
              ...items.map((item) => _AnniversaryTile(item: item, now: now, onDelete: onDelete)),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('記念日を追加'),
              style: OutlinedButton.styleFrom(
                foregroundColor: appAccent(context),
                side: BorderSide(color: appAccent(context)),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AnniversaryTile extends StatelessWidget {
  final AnniversaryItem item;
  final DateTime now;
  final void Function(AnniversaryItem item) onDelete;

  const _AnniversaryTile({required this.item, required this.now, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final summary = summarizeAnniversary(item.date, now);
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.redAccent),
      ),
      onDismissed: (_) => onDelete(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
            )),
            const SizedBox(height: 4),
            Text(
              '${DateFormat('yyyy年M月d日').format(item.date)}から',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 6),
            Text(
              summary.daysUntilNextAnniversary == 0
                  ? '🎉 今日は${summary.nextAnniversaryYearCount}周年記念日です！'
                  : '${summary.nextAnniversaryYearCount}周年まであと${summary.daysUntilNextAnniversary}日',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: appAccent(context)),
            ),
          ],
        ),
      ),
    );
  }
}
