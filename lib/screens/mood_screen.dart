import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/mood_service.dart';
import '../utils/app_theme.dart';
import '../widgets/section_label.dart';

// ── きょうの気分 ──────────────────────────────────────
// 関係性ウェルネス系アプリ（Amora・Paired等）が強化してきた「気分
// チェックイン」の差別化要素。ふたりの日記・ふたりの質問より気軽な入口として、
// 固定の選択肢から今日の気分を選ぶだけにする。
class MoodScreen extends StatefulWidget {
  final String coupleId;
  final List<String> memberIds;
  final String partnerName;
  // テストからエラー/データを直接流し込むための注入ポイント。
  // 未指定時は本番のFirestoreストリームを使う。
  final Stream<List<MoodEntry>>? entriesStreamOverride;
  // テストからfake_cloud_firestore等を差し込むための注入ポイント。
  final MoodService? moodServiceOverride;
  // テストからFirebase Authに触れずに「自分」を差し込むための注入ポイント。
  final String? currentUidOverride;
  // テストから「今日」を固定するための注入ポイント。
  final DateTime? nowOverride;

  const MoodScreen({
    super.key,
    required this.coupleId,
    required this.memberIds,
    required this.partnerName,
    this.entriesStreamOverride,
    this.moodServiceOverride,
    this.currentUidOverride,
    this.nowOverride,
  });

  @override
  State<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends State<MoodScreen> {
  // MoodService() は生成時にFirebaseFirestore.instanceへ即座に触れるため、
  // entriesStreamOverrideを使うテストではFirebase初期化なしに動けるよう
  // 実際に使うときまで生成を遅らせる。
  MoodService? _serviceInstance;
  MoodService get _service => _serviceInstance ??= widget.moodServiceOverride ?? MoodService();

  late final DateTime _now = widget.nowOverride ?? DateTime.now();
  late final String _todayKey = DateFormat('yyyy-MM-dd').format(_now);

  late final Stream<List<MoodEntry>> _entriesStream =
      widget.entriesStreamOverride ?? _service.watchRecentMoods(widget.coupleId);

  String get _uid => widget.currentUidOverride ?? FirebaseAuth.instance.currentUser!.uid;
  String get _partnerUid =>
      widget.memberIds.firstWhere((id) => id != _uid, orElse: () => '');

  bool _saving = false;

  Future<void> _selectMood(String mood) async {
    if (_saving) return;
    setState(() => _saving = true);
    await _service.setTodayMood(widget.coupleId, _todayKey, mood);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('きょうの気分')),
      body: StreamBuilder<List<MoodEntry>>(
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
          MoodEntry? entryOf(String uid, String dateKey) {
            for (final e in entries) {
              if (e.uid == uid && e.dateKey == dateKey) return e;
            }
            return null;
          }

          final myToday = entryOf(_uid, _todayKey);
          final partnerToday = _partnerUid.isEmpty ? null : entryOf(_partnerUid, _todayKey);

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
                const SectionLabel('今日の気分'),
                _buildMoodPicker(selectedKey: myToday?.mood),
                if (partnerToday != null) ...[
                  const SizedBox(height: 12),
                  _buildEntryTile(widget.partnerName, partnerToday.mood),
                ],
                if (historyDates.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const SectionLabel('これまでの気分'),
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

  Widget _buildMoodPicker({String? selectedKey}) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: moodOptions.map((option) {
      final selected = option.key == selectedKey;
      return InkWell(
        onTap: _saving ? null : () => _selectMood(option.key),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 62,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? appAccent(context).withValues(alpha: 0.18) : AppColors.navySurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? appAccent(context) : AppColors.hairline),
          ),
          child: Column(
            children: [
              Text(option.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 4),
              Text(option.label, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
            ],
          ),
        ),
      );
    }).toList(),
  );

  Widget _buildHistoryDate(String dateKey, MoodEntry? mine, MoodEntry? partner) => Container(
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
          _buildEntryLine('あなた', mine.mood),
        ],
        if (partner != null) ...[
          const SizedBox(height: 8),
          _buildEntryLine(widget.partnerName, partner.mood),
        ],
      ],
    ),
  );

  Widget _buildEntryLine(String label, String moodKey) {
    final option = moodOptionFor(moodKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text('${option.emoji} ${option.label}',
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.5)),
      ],
    );
  }

  Widget _buildEntryTile(String label, String moodKey) {
    final option = moodOptionFor(moodKey);
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
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 6),
          Text('${option.emoji} ${option.label}',
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.5)),
        ],
      ),
    );
  }
}
