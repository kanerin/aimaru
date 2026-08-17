import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/couple_service.dart';
import '../services/event_service.dart';
import '../services/google_calendar_cache_service.dart';
import '../utils/app_theme.dart';
import '../utils/free_time_finder.dart';
import '../utils/japan_holidays.dart';
import 'event_form_screen.dart';

// ── 2人の空き時間 ──────────────────────────────────────
// 共有予定・双方のGoogleカレンダーキャッシュはどちらもFirestore上の
// 1箇所に既に集まっている。ここから「2人とも空いている休みの日」を
// 計算して提案する。TimeTreeのような大手が構造的に持てない優位性
// （docs/open-issues.md 課題10）。
//
// 平日の夜まで含めて空き時間を並べても実際には会えないので、
// 探すのは基本の休日（設定画面で変更可）と祝日だけに絞る。
class FreeTimeScreen extends StatefulWidget {
  final String coupleId;

  // テスト用の差し替え口（本番は未指定で実サービスを使う）
  final Stream<List<AimaruEvent>>? eventsStreamOverride;
  final Stream<Map<String, List<GCalEventSummary>>>? gcalStreamOverride;
  final CoupleModel? coupleOverride;

  const FreeTimeScreen({
    super.key,
    required this.coupleId,
    this.eventsStreamOverride,
    this.gcalStreamOverride,
    this.coupleOverride,
  });

  @override
  State<FreeTimeScreen> createState() => _FreeTimeScreenState();
}

class _FreeTimeScreenState extends State<FreeTimeScreen> {
  // サービスはフィールド初期化子で作らない。ここで作るとウィジェットテストでも
  // FirebaseFirestore.instance に触れてしまい、差し替え口を渡しても動かせない。
  // 差し替えが無いときだけ、必要になった時点で生成する。

  // 休みは先まで見たいので4週間先まで探す
  static const _searchDays = 28;
  static const _minDuration = Duration(hours: 2);

  StreamSubscription<List<AimaruEvent>>? _eventsSub;
  StreamSubscription<Map<String, List<GCalEventSummary>>>? _gcalSub;

  List<AimaruEvent>? _events;
  Map<String, List<GCalEventSummary>>? _gcalByUid;
  CoupleModel? _couple;
  Object? _error;

  @override
  void initState() {
    super.initState();

    // 判定に必要な3つのソース（休みの設定・共有予定・Googleカレンダー
    // キャッシュ）をそれぞれ購読し、揃ってから空き時間を計算する。
    // どれかがエラーになったら、無限ローディングにせずエラー表示に切り替える。
    final coupleOverride = widget.coupleOverride;
    if (coupleOverride != null) {
      _couple = coupleOverride;
    } else {
      _loadCouple();
    }

    _eventsSub = (widget.eventsStreamOverride ??
            EventService().watchUpcomingEvents(widget.coupleId, limit: 200))
        .listen(
      (events) { if (mounted) setState(() => _events = events); },
      onError: _onError,
    );
    _gcalSub = (widget.gcalStreamOverride ??
            GoogleCalendarCacheService().watchAll(widget.coupleId))
        .listen(
      (map) { if (mounted) setState(() => _gcalByUid = map); },
      onError: _onError,
    );
  }

  Future<void> _loadCouple() async {
    try {
      final couple = await CoupleService().getMyCouple();
      if (mounted) setState(() => _couple = couple);
    } catch (e) {
      _onError(e);
    }
  }

  void _onError(Object error) {
    if (mounted) setState(() => _error = error);
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _gcalSub?.cancel();
    super.dispose();
  }

  List<FreeDay> _computeDays() {
    final events = _events;
    final gcal = _gcalByUid;
    final couple = _couple;
    if (events == null || gcal == null || couple == null) return const [];

    final busy = <BusyInterval>[
      ...events.map(intervalForEvent),
      // Googleカレンダー側の予定も塞がりとして扱う。
      // 自分・パートナーどちらの予定でも、片方が埋まっていれば会えない。
      for (final list in gcal.values) ...list.map(intervalForGCalEvent),
    ];

    final now = DateTime.now();
    return findFreeDays(
      busy: busy,
      from: now,
      to: now.add(const Duration(days: _searchDays)),
      daysOff: couple.daysOff,
      holidaysAreDaysOff: couple.holidaysAreDaysOff,
      minDuration: _minDuration,
    );
  }

  // 空いている時間帯をタップしたら、その日時で予定作成フォームを開く
  Future<void> _openForm(FreeSlot slot) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventFormScreen(
          coupleId: widget.coupleId,
          initialDate: slot.start,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading =
        _error == null && (_events == null || _gcalByUid == null || _couple == null);
    final days = loading || _error != null ? const <FreeDay>[] : _computeDays();
    final fullDays = days.where((d) => d.kind == FreeDayKind.fullDay).toList();
    final partialDays = days.where((d) => d.kind == FreeDayKind.partial).toList();

    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('2人の空き時間')),
      body: _buildBody(context, loading, fullDays, partialDays),
    );
  }

  Widget _buildBody(
    BuildContext context,
    bool loading,
    List<FreeDay> fullDays,
    List<FreeDay> partialDays,
  ) {
    if (_error != null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '空き時間の読み込みに失敗しました\n通信状況を確認してもう一度お試しください',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6),
          ),
        ),
      );
    }

    if (loading) {
      return Center(child: CircularProgressIndicator(color: appAccent(context)));
    }

    if (fullDays.isEmpty && partialDays.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'これから4週間で2人が会えそうな休みは\n見つかりませんでした\n\n'
            '設定の「基本の休日」が実際の休みと\n合っているか確認してみてください',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (fullDays.isNotEmpty) ...[
          const _SectionHeader(
            emoji: '🌞',
            title: '一日空いてる日',
            description: '朝から夜まで予定が入っていない休み',
          ),
          ...fullDays.map((d) => _buildDayCard(context, d)),
          const SizedBox(height: 20),
        ],
        if (partialDays.isNotEmpty) ...[
          const _SectionHeader(
            emoji: '☕',
            title: 'ちょっと会える日',
            description: '予定の合間に空いている時間がある休み',
          ),
          ...partialDays.map((d) => _buildDayCard(context, d)),
        ],
      ],
    );
  }

  Widget _buildDayCard(BuildContext context, FreeDay day) {
    final holidayName = JapanHolidays.nameFor(day.date);
    final dateLabel = DateFormat('M月d日（E）', 'ja').format(day.date);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(children: [
              Text(dateLabel, style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.cream,
              )),
              if (holidayName != null) ...[
                const SizedBox(width: 6),
                Text(holidayName, style: const TextStyle(
                  fontSize: 11, color: AppColors.pinkAccent, fontWeight: FontWeight.w600,
                )),
              ],
            ]),
          ),
          // 時間帯ごとにタップできる。タップするとその日時で予定を作れる。
          ...day.slots.map((slot) => _buildSlotRow(context, slot)),
        ],
      ),
    );
  }

  Widget _buildSlotRow(BuildContext context, FreeSlot slot) {
    final timeLabel =
        '${DateFormat('HH:mm').format(slot.start)}〜${DateFormat('HH:mm').format(slot.end)}';
    final hours = slot.duration.inMinutes / 60;
    final hoursLabel =
        hours == hours.roundToDouble() ? '${hours.round()}時間' : '${hours.toStringAsFixed(1)}時間';

    return InkWell(
      onTap: () => _openForm(slot),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 10),
        child: Row(children: [
          Container(
            width: 3, height: 26,
            decoration: BoxDecoration(
              color: appAccent(context), borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(timeLabel, style: const TextStyle(
              fontSize: 12.5, color: AppColors.textSecond,
            )),
          ),
          Text(hoursLabel, style: TextStyle(
            fontSize: 11.5, color: appAccent(context), fontWeight: FontWeight.w600,
          )),
          const SizedBox(width: 4),
          const Icon(Icons.add, size: 16, color: AppColors.textMuted),
        ]),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String emoji;
  final String title;
  final String description;

  const _SectionHeader({
    required this.emoji,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 15)),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.cream,
        )),
      ]),
      const SizedBox(height: 3),
      Text(description, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
    ]),
  );
}
