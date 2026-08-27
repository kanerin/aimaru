import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/diary_service.dart';
import '../utils/app_theme.dart';
import '../widgets/section_label.dart';

// ── ふたりの日記 ──────────────────────────────────────
// 「共有日記」は競合（Between Us等）が2025年以降に強化してきた「お互いを知る」
// 系の差別化要素。「ふたりの質問」と違い相手の回答を伏せる仕組みは無く、
// 自由に書いていつでも書き直せる素朴な日記として位置付ける。
class DiaryScreen extends StatefulWidget {
  final String coupleId;
  final List<String> memberIds;
  final String partnerName;
  // テストからエラー/データを直接流し込むための注入ポイント。
  // 未指定時は本番のFirestoreストリームを使う。
  final Stream<List<DiaryEntry>>? entriesStreamOverride;
  // テストからFirebase Authに触れずに「自分」を差し込むための注入ポイント。
  final String? currentUidOverride;
  // テストから「今日」を固定するための注入ポイント。
  final DateTime? nowOverride;

  const DiaryScreen({
    super.key,
    required this.coupleId,
    required this.memberIds,
    required this.partnerName,
    this.entriesStreamOverride,
    this.currentUidOverride,
    this.nowOverride,
  });

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  DiaryService? _serviceInstance;
  DiaryService get _service => _serviceInstance ??= DiaryService();

  late final DateTime _now = widget.nowOverride ?? DateTime.now();
  late final String _todayKey = DateFormat('yyyy-MM-dd').format(_now);

  late final Stream<List<DiaryEntry>> _entriesStream =
      widget.entriesStreamOverride ?? _service.watchRecentEntries(widget.coupleId);

  String get _uid => widget.currentUidOverride ?? FirebaseAuth.instance.currentUser!.uid;
  String get _partnerUid =>
      widget.memberIds.firstWhere((id) => id != _uid, orElse: () => '');

  final _entryController = TextEditingController();
  bool _saving = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _entryController.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    await _service.saveEntry(widget.coupleId, _todayKey, text);
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _delete() async {
    if (_saving) return;
    setState(() => _saving = true);
    await _service.deleteEntry(widget.coupleId, _todayKey);
    _entryController.clear();
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('ふたりの日記')),
      body: StreamBuilder<List<DiaryEntry>>(
        stream: _entriesStream,
        builder: (context, snap) {
          // hasDataだけを見ていると、権限エラー等でストリームがエラーに
          // 落ちたときに無限ローディングのまま固まる。
          if (snap.hasError) {
            return const Center(
              child: Text('読み込みに失敗しました\nしばらくしてから開き直してください',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
            );
          }
          if (!snap.hasData) {
            return Center(child: CircularProgressIndicator(color: appAccent(context)));
          }

          final entries = snap.data!;
          DiaryEntry? entryOf(String uid, String dateKey) {
            for (final e in entries) {
              if (e.uid == uid && e.dateKey == dateKey) return e;
            }
            return null;
          }

          final myToday = entryOf(_uid, _todayKey);
          final partnerToday = _partnerUid.isEmpty ? null : entryOf(_partnerUid, _todayKey);

          if (!_prefilled) {
            _entryController.text = myToday?.text ?? '';
            _prefilled = true;
          }

          final historyDates = entries
              .map((e) => e.dateKey)
              .where((d) => d != _todayKey)
              .toSet()
              .toList()
            ..sort((a, b) => b.compareTo(a));

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('今日の日記'),
                _buildTodayInput(hasSavedEntry: myToday != null),
                if (partnerToday != null) ...[
                  const SizedBox(height: 12),
                  _buildEntryTile(widget.partnerName, partnerToday.text),
                ],
                if (historyDates.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const SectionLabel('これまでの日記'),
                  for (final date in historyDates) ...[
                    _buildHistoryDate(date, entryOf(_uid, date), entryOf(_partnerUid, date)),
                    const SizedBox(height: 12),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTodayInput({required bool hasSavedEntry}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _entryController,
        maxLines: 5,
        style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
        decoration: const InputDecoration(hintText: '今日あったことを書く'),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: const Text('保存する'),
            ),
          ),
          if (hasSavedEntry) ...[
            const SizedBox(width: 12),
            TextButton(
              onPressed: _saving ? null : _delete,
              child: const Text('削除'),
            ),
          ],
        ],
      ),
    ],
  );

  Widget _buildHistoryDate(String dateKey, DiaryEntry? mine, DiaryEntry? partner) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.navySurface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(dateKey, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        if (mine != null) ...[
          const SizedBox(height: 8),
          _buildEntryLine('あなた', mine.text),
        ],
        if (partner != null) ...[
          const SizedBox(height: 8),
          _buildEntryLine(widget.partnerName, partner.text),
        ],
      ],
    ),
  );

  Widget _buildEntryLine(String label, String text) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      const SizedBox(height: 2),
      Text(text, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.5)),
    ],
  );

  Widget _buildEntryTile(String label, String text) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.navySurface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 6),
        Text(text, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.5)),
      ],
    ),
  );
}
