import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/event_service.dart';
import '../services/google_calendar_cache_service.dart';
import '../utils/app_theme.dart';
import '../utils/free_time_finder.dart';

// ── 2人の空き時間 ──────────────────────────────────────
// 共有予定・双方のGoogleカレンダーキャッシュはどちらもFirestore上の
// 1箇所に既に集まっている。ここから今日〜1週間で「2人とも何も
// 入っていない時間帯」を計算して提案する。TimeTreeのような大手が
// 構造的に持てない優位性（docs/open-issues.md 課題10）。
class FreeTimeScreen extends StatefulWidget {
  final String coupleId;
  const FreeTimeScreen({super.key, required this.coupleId});

  @override
  State<FreeTimeScreen> createState() => _FreeTimeScreenState();
}

class _FreeTimeScreenState extends State<FreeTimeScreen> {
  final _eventService = EventService();
  final _gcalCache = GoogleCalendarCacheService();

  static const _searchDays = 7;
  static const _minDuration = Duration(hours: 2);

  StreamSubscription<List<AimaruEvent>>? _eventsSub;
  StreamSubscription<Map<String, List<GCalEventSummary>>>? _gcalSub;

  List<AimaruEvent>? _events;
  Map<String, List<GCalEventSummary>>? _gcalByUid;

  @override
  void initState() {
    super.initState();
    // 判定に必要な2つのソース（共有予定・Googleカレンダーキャッシュ）を
    // それぞれ購読し、両方揃ってから空き時間を計算する。
    _eventsSub = _eventService
        .watchUpcomingEvents(widget.coupleId, limit: 100)
        .listen((events) { if (mounted) setState(() => _events = events); });
    _gcalSub = _gcalCache
        .watchAll(widget.coupleId)
        .listen((map) { if (mounted) setState(() => _gcalByUid = map); });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _gcalSub?.cancel();
    super.dispose();
  }

  List<FreeSlot> _computeSlots() {
    final events = _events;
    final gcal = _gcalByUid;
    if (events == null || gcal == null) return [];

    final busy = <BusyInterval>[
      ...events.map(intervalForEvent),
      for (final list in gcal.values) ...list.map(intervalForGCalEvent),
    ];

    final now = DateTime.now();
    return findFreeSlots(
      busy: busy,
      from: now,
      to: now.add(const Duration(days: _searchDays)),
      minDuration: _minDuration,
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = _events == null || _gcalByUid == null;
    final slots = loading ? const <FreeSlot>[] : _computeSlots();

    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('2人の空き時間')),
      body: loading
          ? Center(child: CircularProgressIndicator(color: appAccent(context)))
          : slots.isEmpty
              ? const Center(
                  child: Text(
                    '今週はまとまった空き時間が\n見つかりませんでした',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: slots.length,
                  itemBuilder: (ctx, i) => _buildSlotTile(context, slots[i]),
                ),
    );
  }

  Widget _buildSlotTile(BuildContext context, FreeSlot slot) {
    final sameDay = slot.start.year == slot.end.year &&
        slot.start.month == slot.end.month &&
        slot.start.day == slot.end.day;
    final dateLabel = DateFormat('M月d日（E）', 'ja').format(slot.start);
    final timeLabel = sameDay
        ? '${DateFormat('HH:mm').format(slot.start)}〜${DateFormat('HH:mm').format(slot.end)}'
        : '${DateFormat('HH:mm').format(slot.start)}〜${DateFormat('M/d HH:mm').format(slot.end)}';
    final hours = slot.duration.inMinutes / 60;
    final hoursLabel =
        hours == hours.roundToDouble() ? '${hours.round()}時間' : '${hours.toStringAsFixed(1)}時間';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(children: [
        Container(
          width: 3, height: 34,
          decoration: BoxDecoration(color: appAccent(context), borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(dateLabel, style: const TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.cream,
            )),
            const SizedBox(height: 3),
            Text(timeLabel, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        ),
        Text(hoursLabel, style: TextStyle(
          fontSize: 11.5, color: appAccent(context), fontWeight: FontWeight.w600,
        )),
      ]),
    );
  }
}
