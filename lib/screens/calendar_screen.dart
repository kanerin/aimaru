import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/couple_service.dart';
import '../services/event_service.dart';
import '../services/google_calendar_service.dart';
import '../services/google_calendar_cache_service.dart';
import '../services/settings_service.dart';
import '../utils/app_theme.dart';
import '../utils/event_days.dart';
import '../utils/japan_holidays.dart';
import '../utils/recurring_events.dart';
import 'event_detail_screen.dart';
import 'event_form_screen.dart';
import 'event_search_screen.dart';
import 'free_time_screen.dart';
import 'google_event_edit_screen.dart';
import 'settings_screen.dart';

const _gcalColor = Color(0xFF4285F4);
const _sundayColor = Color(0xFFD97878);
const _saturdayColor = Color(0xFF6FA0DC);
const _holidayChipColor = Color(0xFFE8A0A0);

// Googleカレンダー側の予定に、それが誰のカレンダー由来かを付与するためのラッパー
class _GcalEntry {
  final String uid;
  final GCalEventSummary event;
  const _GcalEntry({required this.uid, required this.event});
}

class _Member {
  final String uid;
  final String name;
  final String? photoUrl;
  const _Member({required this.uid, required this.name, this.photoUrl});
}

class CalendarScreen extends StatefulWidget {
  final String coupleId;
  // 以下はテストからFirebase/Google APIに触れずに検証するための注入ポイント。
  // 未指定時はすべて本番実装（bug_report_screen.dart等と同じ「serviceOverride +
  // 遅延getter」設計）。
  final Stream<Map<DateTime, List<AimaruEvent>>>? eventsStreamOverride;
  final EventService? eventServiceOverride;
  final GoogleCalendarService? googleCalendarServiceOverride;
  final GoogleCalendarCacheService? googleCalendarCacheServiceOverride;
  final SettingsService? settingsServiceOverride;
  final CoupleService? coupleServiceOverride;
  final String? currentUidOverride;
  // テストから「今日」を固定するための注入ポイント（未指定時はDateTime.now）。
  final DateTime Function()? nowOverride;
  const CalendarScreen({
    super.key,
    required this.coupleId,
    this.eventsStreamOverride,
    this.eventServiceOverride,
    this.googleCalendarServiceOverride,
    this.googleCalendarCacheServiceOverride,
    this.settingsServiceOverride,
    this.coupleServiceOverride,
    this.currentUidOverride,
    this.nowOverride,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  // 各サービスは生成時にFirebaseFirestore.instance等へ即座に触れるため、
  // override付きのテストではFirebase初期化なしに動けるよう、実際に使うときまで
  // 生成を遅らせる（todos_screen.dartの_todoServiceと同じ設計）。
  EventService? _eventServiceInstance;
  EventService get _eventService => _eventServiceInstance ??= widget.eventServiceOverride ?? EventService();

  GoogleCalendarService? _googleCalendarInstance;
  GoogleCalendarService get _googleCalendar =>
      _googleCalendarInstance ??= widget.googleCalendarServiceOverride ?? GoogleCalendarService();

  GoogleCalendarCacheService? _googleCalendarCacheInstance;
  GoogleCalendarCacheService get _googleCalendarCache =>
      _googleCalendarCacheInstance ??= widget.googleCalendarCacheServiceOverride ?? GoogleCalendarCacheService();

  SettingsService? _settingsServiceInstance;
  SettingsService get _settingsService => _settingsServiceInstance ??= widget.settingsServiceOverride ?? SettingsService();

  CoupleService? _coupleServiceInstance;
  CoupleService get _coupleService => _coupleServiceInstance ??= widget.coupleServiceOverride ?? CoupleService();

  String get _selfUid => widget.currentUidOverride ?? FirebaseAuth.instance.currentUser!.uid;

  // widget.nowOverrideはテストから「今日」を固定するための注入ポイント
  // （initStateで確定させる。フィールド初期化子だとwidgetがまだ未設定のため）。
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  // true: ヘッダー/フッター以外全体にカレンダーを表示（各日に予定のプレビュー付き）
  // false: 現行の「小さめカレンダー(ドット表示) + 下部に選択日の予定リスト」表示
  bool _expandedView = true;

  bool _showGoogleCalendar = false;
  bool _showHolidays = true;
  bool _weekStartsMonday = false;

  // build()の中で watchEventsAsMap() を呼ぶと、再ビルドのたびに snapshots() を
  // 購読し直すことになり、最初のスナップショットが届くまで snap.data が null に
  // 戻る。月を送ると予定が一瞬消えてから出てくるのはこれが原因なので、
  // ストリームはこの画面で1本だけ作って使い回す。
  late final Stream<Map<DateTime, List<AimaruEvent>>> _eventsStream =
      widget.eventsStreamOverride ?? _eventService.watchEventsAsMap(widget.coupleId);

  StreamSubscription<Map<String, List<GCalEventSummary>>>? _gcalSub;
  Map<DateTime, List<_GcalEntry>> _gcalByDate = {};
  DateTime? _gcalSyncedMonth;

  Map<String, _Member> _members = {};

  DateTime _key(DateTime d) => dayKey(d);

  Color _dotColor(EventType t) => switch (t) {
    EventType.date        => AppColors.pink,
    EventType.anniversary => AppColors.gold,
    EventType.celebrity   => AppColors.lavenderSoft,
    EventType.plan        => AppColors.textMuted,
  };

  Color _memberColor(BuildContext context, String uid) =>
      uid == _selfUid ? appAccent(context) : AppColors.partnerColor;

  String _memberInitial(String uid) {
    final name = _members[uid]?.name ?? (uid == _selfUid ? '自分' : 'パートナー');
    return name.isNotEmpty ? name.substring(0, 1) : '?';
  }

  @override
  void initState() {
    super.initState();
    final now = (widget.nowOverride ?? DateTime.now)();
    _focusedDay  = now;
    _selectedDay = now;
    _initGoogleCalendar();
    _loadDisplayPrefs();
    _loadMembers();
  }

  @override
  void dispose() {
    _gcalSub?.cancel();
    super.dispose();
  }

  Future<void> _loadDisplayPrefs() async {
    final holidays = await _settingsService.getShowHolidays();
    final weekStart = await _settingsService.getWeekStartsMonday();
    if (mounted) setState(() { _showHolidays = holidays; _weekStartsMonday = weekStart; });
  }

  // メンバーの表示名・アイコンの取得。
  // 取得できなくてもカレンダー自体は「自分／パートナー」の既定表示で成立するため、
  // 失敗しても画面を壊さない。ここで例外を投げっぱなしにすると、権限エラーや
  // ログアウト直後の応答が非同期で着地したときに拾い手のない例外になる。
  Future<void> _loadMembers() async {
    try {
      final couple = await _coupleService.getMyCouple();
      if (couple == null || !mounted) return;
      final profiles = <String, _Member>{};
      for (final uid in couple.memberIds) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final data = doc.data();
        profiles[uid] = _Member(
          uid: uid,
          name: (data?['displayName'] as String?)?.isNotEmpty == true
              ? data!['displayName']
              : (uid == _selfUid ? '自分' : 'パートナー'),
          photoUrl: data?['photoUrl'],
        );
      }
      if (mounted) setState(() => _members = profiles);
    } catch (e) {
      debugPrint('[メンバー情報の取得に失敗] $e');
    }
  }

  Future<void> _initGoogleCalendar() async {
    final show = await _settingsService.getShowGoogleCalendar();
    if (!mounted) return;
    setState(() => _showGoogleCalendar = show);
    if (!show) return;

    _gcalSub = _googleCalendarCache.watchAll(widget.coupleId).listen((map) {
      final byDate = <DateTime, List<_GcalEntry>>{};
      map.forEach((uid, events) {
        for (final e in events) {
          // 自分以外がprivate指定したGoogle予定はパートナーに見せない
          // （AimaruEventのprivate予定と同じ扱い。Google側にはこの概念が
          // 無いため、GoogleCalendarCacheService側でvisibilityを付与している）。
          if (uid != _selfUid && e.visibility == EventVisibility.private) continue;
          // 開始日にしかキーを置かないと、日をまたぐ予定（旅行など）が
          // 初日にしか出ずドットも初日にしか付かない。終日予定のendは
          // 翌日を指す排他的な値なので、gcalLastDayで最終日へ直してから展開する。
          final lastDay = gcalLastDay(start: e.start, end: e.end, allDay: e.allDay);
          for (final day in daysBetween(e.start, lastDay)) {
            byDate.putIfAbsent(day, () => []).add(_GcalEntry(uid: uid, event: e));
          }
        }
      });
      if (mounted) setState(() => _gcalByDate = byDate);
    });

    await _syncGoogleCalendarForMonth(_focusedDay);
  }

  Future<void> _syncGoogleCalendarForMonth(DateTime month) async {
    if (!_showGoogleCalendar) return;
    final monthKey = DateTime(month.year, month.month);
    if (_gcalSyncedMonth == monthKey) return;
    _gcalSyncedMonth = monthKey;

    // 前後1ヶ月ぶんも合わせて取得しておくと月送り直後も表示が揃う
    final start = DateTime(month.year, month.month - 1, 1);
    final end   = DateTime(month.year, month.month + 2, 0, 23, 59);
    final events = await _googleCalendar.fetchEvents(start: start, end: end);
    await _googleCalendarCache.pushMyEvents(widget.coupleId, events);
  }

  // このアプリからGoogleカレンダーに同期した予定のGoogle側IDの集合。
  // Googleカレンダー由来の表示からこれらを除外し、二重表示を防ぐ。
  Set<String> _syncedGoogleIds(Map<DateTime, List<AimaruEvent>> eventsMap) => {
    for (final list in eventsMap.values)
      for (final e in list)
        if (e.googleCalendarEventId != null) e.googleCalendarEventId!,
  };

  List<_GcalEntry> _gcalFor(DateTime day, Set<String> syncedIds) =>
      (_gcalByDate[_key(day)] ?? []).where((e) => !syncedIds.contains(e.event.id)).toList();

  Future<void> _openForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EventFormScreen(
        coupleId: widget.coupleId, initialDate: _selectedDay,
      )),
    );
    if (saved == true) setState(() {}); // ストリームが更新するので再構築のみ
  }

  Future<void> _openDetail(AimaruEvent event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EventDetailScreen(
        event: event, coupleId: widget.coupleId,
      )),
    );
  }

  Future<void> _openGoogleEventEdit(GCalEventSummary event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GoogleEventEditScreen(
        coupleId: widget.coupleId, event: event,
      )),
    );
  }

  Future<void> _openFreeTime() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FreeTimeScreen(coupleId: widget.coupleId)),
    );
  }

  Future<void> _openSearch() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EventSearchScreen(coupleId: widget.coupleId)),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsScreen(coupleId: widget.coupleId)),
    );
    // 設定（Googleカレンダー表示・祝日表示・週の開始曜日など）が変わった可能性があるので再初期化
    _gcalSub?.cancel();
    _gcalSyncedMonth = null;
    _gcalByDate = {};
    await _initGoogleCalendar();
    await _loadDisplayPrefs();
  }

  // 全体表示で日付をタップ → 選択表示へ。選択表示で同じ日をもう一度タップ → 全体表示へ戻る。
  void _handleDaySelected(DateTime selected, DateTime focused) {
    setState(() {
      if (!_expandedView && isSameDay(selected, _selectedDay)) {
        _expandedView = true;
      } else {
        _selectedDay = selected;
        _focusedDay  = focused;
        _expandedView = false;
      }
    });
  }

  static const _headerStyle = HeaderStyle(
    formatButtonVisible: false,
    titleCentered: true,
    titleTextStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    leftChevronIcon: Icon(Icons.chevron_left, color: AppColors.textMuted, size: 20),
    rightChevronIcon: Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
  );

  static const _daysOfWeekStyle = DaysOfWeekStyle(
    weekdayStyle: TextStyle(fontSize: 10, color: AppColors.textMuted),
    weekendStyle: TextStyle(fontSize: 10, color: AppColors.textMuted),
  );

  // ── 選択表示のミニカレンダーの寸法 ───────────────────
  // table_calendarは日付の丸(today/selected)を「セル - cellMargin」の領域に
  // 描き、マーカーは Stack(alignment: markersAlignment) の子として置く。
  // 下端揃えのマーカーと丸が同じ領域を奪い合うため、cellMarginの下側に
  // ドット専用の帯を確保して丸を上へ逃がす。
  static const double _dotSize = 4;
  // ドットのために空ける帯の高さ。丸はこの分だけ小さく・上寄りになる。
  static const double _dotBandHeight = 14;
  // 帯の中でドットをセル下端から浮かせる量。
  static const double _dotBottomInset = 3;
  static const EdgeInsets _miniCellMargin = EdgeInsets.only(
    top: 4, left: 6, right: 6, bottom: _dotBandHeight,
  );
  // 最終週のドットはセル下端の _dotBottomInset 上にあるだけなので、
  // カレンダーの直下に区切り線が来ると予定リストと近接して見える。
  // ドットを上げると日付の丸と重なるため、下に余白を足して離す。
  static const double _miniBottomGap = 10;

  StartingDayOfWeek get _startingDayOfWeek =>
      _weekStartsMonday ? StartingDayOfWeek.monday : StartingDayOfWeek.sunday;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        title: const Text('カレンダー'),
        actions: [
          IconButton(
            tooltip: '予定を検索',
            icon: const Icon(Icons.search, color: AppColors.textSecond),
            onPressed: _openSearch,
          ),
          IconButton(
            tooltip: '2人の空き時間',
            icon: const Icon(Icons.free_breakfast_outlined, color: AppColors.textSecond),
            onPressed: _openFreeTime,
          ),
          IconButton(
            tooltip: '設定',
            icon: const Icon(Icons.settings_outlined, color: AppColors.textSecond),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: StreamBuilder<Map<DateTime, List<AimaruEvent>>>(
        stream: _eventsStream,
        builder: (context, snap) {
          // hasDataだけを見ていると、権限エラー等でストリームがエラーに
          // 落ちたときに「予定が無いだけ」に見える空のカレンダーで固まる
          // （todos_screen.dartと同じ理由でここも明示的にハンドリングする）。
          if (snap.hasError) {
            return const Center(
              child: Text('読み込みに失敗しました\nしばらくしてから開き直してください',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
            );
          }
          // 毎年繰り返す予定は1件しか保存されていないので、表示する年の
          // 発生日へ展開する。前後の月が別の年に食い込むため±1年を含める。
          final eventsMap = expandRecurringEvents(
            snap.data ?? {},
            years: [_focusedDay.year - 1, _focusedDay.year, _focusedDay.year + 1],
          );
          final syncedIds = _syncedGoogleIds(eventsMap);
          return _expandedView
              ? _buildExpandedCalendar(eventsMap, syncedIds)
              : _buildSelectedDayView(eventsMap, syncedIds);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
    );
  }

  // ── 全体表示: 月グリッド全体を使い、各日に予定のプレビューを表示 ──
  Widget _buildExpandedCalendar(
    Map<DateTime, List<AimaruEvent>> eventsMap,
    Set<String> syncedIds,
  ) {
    const daysOfWeekHeight = 22.0;
    const headerHeight = 56.0; // ヘッダー行の実測より少し余裕を持たせ、はみ出しを防ぐ
    const fabReserve = 84.0; // FABがスクロールなしの初期表示で最終行に被らないための余白

    return LayoutBuilder(
      builder: (context, constraints) {
        // 下限を上げ、極端に小さい画面では(はみ出すより)スクロールさせる。
        // セル内に入るチップ数はこのrowHeightから逆算するため、
        // ここが小さすぎるとチップが0件になり得るが、はみ出して被って見えるよりは安全。
        final rowHeight = ((constraints.maxHeight - headerHeight - daysOfWeekHeight - fabReserve) / 6)
            .clamp(64.0, 140.0);

        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 88), // FAB/下部ナビに最終行が隠れないように
          child: TableCalendar<AimaruEvent>(
          locale: 'ja_JP',
          firstDay: DateTime(2020, 1, 1),
          lastDay: DateTime(2100, 12, 31),
          focusedDay: _focusedDay,
          // 全体表示では「選択中」の概念を使わない。
          // trueを返す日を作ると、todayBuilder等が適用されずデフォルト表示に
          // フォールバックしてしまう（＝当日の予定が消えて見える不具合の原因だった）。
          selectedDayPredicate: (d) => false,
          startingDayOfWeek: _startingDayOfWeek,
          sixWeekMonthsEnforced: true,
          rowHeight: rowHeight,
          daysOfWeekHeight: daysOfWeekHeight,
          onDaySelected: _handleDaySelected,
          onPageChanged: (focused) {
            _focusedDay = focused;
            _syncGoogleCalendarForMonth(focused);
          },
          headerStyle: _headerStyle,
          daysOfWeekStyle: _daysOfWeekStyle,
          calendarStyle: const CalendarStyle(outsideDaysVisible: true),
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (context, day, focusedDay) => _dayCell(context, day, eventsMap, syncedIds, cellHeight: rowHeight),
            outsideBuilder: (context, day, focusedDay) => _dayCell(context, day, eventsMap, syncedIds, cellHeight: rowHeight, isOutside: true),
            todayBuilder: (context, day, focusedDay) => _dayCell(context, day, eventsMap, syncedIds, cellHeight: rowHeight, isToday: true),
          ),
        ));
      },
    );
  }

  Widget _memberDot(BuildContext context, String uid, {double size = 6}) => Container(
    width: size, height: size,
    margin: const EdgeInsets.only(right: 3),
    decoration: BoxDecoration(color: _memberColor(context, uid), shape: BoxShape.circle),
  );

  Widget _memberAvatar(BuildContext context, String uid, {double radius = 9}) {
    final member = _members[uid];
    final color = _memberColor(context, uid);
    if (member?.photoUrl != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.navySurface,
        backgroundImage: NetworkImage(member!.photoUrl!),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.25),
      child: Text(_memberInitial(uid), style: TextStyle(
        fontSize: radius * 0.9, fontWeight: FontWeight.w700, color: color,
      )),
    );
  }

  Widget _dayCell(
    BuildContext context,
    DateTime day,
    Map<DateTime, List<AimaruEvent>> eventsMap,
    Set<String> syncedIds, {
    required double cellHeight,
    bool isToday = false,
    bool isOutside = false,
  }) {
    final events     = eventsMap[_key(day)] ?? [];
    final gcalEvents = _gcalFor(day, syncedIds);
    final holidayName = _showHolidays ? JapanHolidays.nameFor(day) : null;

    final chips = <(String label, Color categoryColor, String uid)>[
      ...events.map((e) => ('${e.type.emoji} ${e.title}', _dotColor(e.type), e.createdBy)),
      ...gcalEvents.map((e) => ('📅 ${e.event.title}', _gcalColor, e.uid)),
    ];

    // セルの実際の高さから収まるチップ数を逆算する。固定件数を常に表示しようと
    // すると、画面が小さい端末でセルの高さを超えてはみ出す
    // （＝見た目が被って見える）ことがあったため、確実に収まる件数に抑える。
    const chipHeight = 14.5;
    const dayNumberHeight = 20.0;
    const holidayChipHeight = 14.0;
    const overflowLabelReserve = 10.0;
    const containerChrome = 3.0 * 2 + 1.5 * 2; // padding + margin
    final usedByHeader = dayNumberHeight + (holidayName != null ? holidayChipHeight : 2.0);
    final availableForChips = cellHeight - containerChrome - usedByHeader - overflowLabelReserve;
    final maxChips = (availableForChips / chipHeight).floor().clamp(0, 3);

    Color numberColor;
    if (isToday) {
      numberColor = Colors.white;
    } else if (isOutside) {
      numberColor = AppColors.textMuted;
    } else if (holidayName != null || day.weekday == DateTime.sunday) {
      numberColor = _sundayColor;
    } else if (day.weekday == DateTime.saturday) {
      numberColor = _saturdayColor;
    } else {
      numberColor = AppColors.textSecond;
    }

    return Container(
      margin: const EdgeInsets.all(1.5),
      padding: const EdgeInsets.all(3),
      alignment: Alignment.topLeft,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: isToday
                ? BoxDecoration(color: appAccentSoft(context), shape: BoxShape.circle)
                : null,
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                color: numberColor,
              ),
            ),
          ),
          if (holidayName != null)
            Container(
              margin: const EdgeInsets.only(top: 1, bottom: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: _holidayChipColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                holidayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 8, color: _sundayColor, fontWeight: FontWeight.w600),
              ),
            )
          else
            const SizedBox(height: 2),
          ...chips.take(maxChips).map((c) => Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: c.$2.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _memberDot(context, c.$3, size: 5),
                Expanded(
                  child: Text(
                    c.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 8.5, color: AppColors.cream, height: 1.2),
                  ),
                ),
              ],
            ),
          )),
          if (chips.length > maxChips)
            Text('+${chips.length - maxChips}',
                style: const TextStyle(fontSize: 8, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  // ── 選択表示: 小さめカレンダー(ドット) + 下部に選択日の予定リスト ──
  Widget _buildSelectedDayView(
    Map<DateTime, List<AimaruEvent>> eventsMap,
    Set<String> syncedIds,
  ) {
    final selectedEvents     = eventsMap[_key(_selectedDay)] ?? [];
    final selectedGcalEvents = _gcalFor(_selectedDay, syncedIds);
    final totalCount         = selectedEvents.length + selectedGcalEvents.length;
    final holidayName        = _showHolidays ? JapanHolidays.nameFor(_selectedDay) : null;

    return Column(
      children: [
        // ミニカレンダーを下方向にドラッグすると全体表示に戻る
        GestureDetector(
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) > 200) {
              setState(() => _expandedView = true);
            }
          },
          child: TableCalendar<AimaruEvent>(
            locale: 'ja_JP',
            firstDay: DateTime(2020, 1, 1),
            lastDay: DateTime(2100, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
            eventLoader: (d) => eventsMap[_key(d)] ?? [],
            holidayPredicate: (d) => _showHolidays && JapanHolidays.isHoliday(d),
            startingDayOfWeek: _startingDayOfWeek,
            // 縦方向はミニカレンダーの折りたたみ(週表示)には使わず、
            // 全体表示へ戻すジェスチャーに専用させる
            availableGestures: AvailableGestures.horizontalSwipe,
            // デフォルト(52)だと週が詰まって予定ドットが窮屈に見えるため広げる
            rowHeight: 58,
            onDaySelected: _handleDaySelected,
            onPageChanged: (focused) {
              _focusedDay = focused;
              _syncGoogleCalendarForMonth(focused);
            },
            headerStyle: _headerStyle,
            daysOfWeekStyle: _daysOfWeekStyle,
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              defaultTextStyle: const TextStyle(fontSize: 12, color: AppColors.textSecond),
              weekendTextStyle: const TextStyle(fontSize: 12, color: _saturdayColor),
              holidayTextStyle: const TextStyle(fontSize: 12, color: _sundayColor),
              // table_calendarのデフォルトは祝日に丸枠が付くため、文字色だけにする
              holidayDecoration: const BoxDecoration(),
              // 日付の丸は「セル - cellMargin」いっぱいに描かれるため、下側に
              // ドット用の帯を空けておかないと丸の下端とドットが重なる。
              cellMargin: _miniCellMargin,
              todayDecoration: BoxDecoration(color: appAccentSoft(context), shape: BoxShape.circle),
              todayTextStyle: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700),
              selectedDecoration: BoxDecoration(color: appAccent(context), shape: BoxShape.circle),
              selectedTextStyle: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700),
              markersAlignment: Alignment.bottomCenter,
            ),
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, day, events) {
                final hasGcal = _gcalFor(day, syncedIds).isNotEmpty;
                if (events.isEmpty && !hasGcal) return null;
                final types = events.map((e) => e.type).toSet().take(3);
                // markerBuilderを渡すと、返したWidgetがそのまま
                // Stack(alignment: markersAlignment) の子になる。
                // CalendarStyleのmarkerSize/markerMargin/markersAnchorは
                // 一切参照されないので、位置はここで自分で決める。
                return Padding(
                  padding: const EdgeInsets.only(bottom: _dotBottomInset),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...types.map((t) => Container(
                        width: _dotSize, height: _dotSize,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(color: _dotColor(t), shape: BoxShape.circle),
                      )),
                      if (hasGcal)
                        Container(
                          width: _dotSize, height: _dotSize,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: const BoxDecoration(color: _gcalColor, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: _miniBottomGap),
        const Divider(height: 1, color: AppColors.hairline),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Text(
                  DateFormat('M月d日（E）', 'ja').format(_selectedDay),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecond),
                ),
                if (holidayName != null) ...[
                  const SizedBox(width: 6),
                  Text(holidayName, style: const TextStyle(fontSize: 11.5, color: _sundayColor, fontWeight: FontWeight.w600)),
                ],
              ]),
              Text('$totalCount件', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
        ),
        Expanded(
          child: totalCount == 0
              ? const Center(
                  child: Text('予定はありません', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 88),
                  children: [
                    ...selectedEvents.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onTap: () => _openDetail(e),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.navySurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.hairline),
                          ),
                          child: Row(children: [
                            Container(width: 3, height: 34, decoration: BoxDecoration(
                              color: _dotColor(e.type), borderRadius: BorderRadius.circular(2),
                            )),
                            const SizedBox(width: 10),
                            _memberAvatar(context, e.createdBy),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  if (e.visibility == EventVisibility.private) ...[
                                    const Icon(Icons.lock_outline, size: 12, color: AppColors.textMuted),
                                    const SizedBox(width: 3),
                                  ],
                                  Flexible(
                                    child: Text('${e.type.emoji} ${e.title}', style: const TextStyle(
                                      fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.cream,
                                    )),
                                  ),
                                ]),
                                const SizedBox(height: 3),
                                Text(
                                  [
                                    e.allDay ? '終日' : DateFormat('HH:mm').format(e.date),
                                    if (e.location != null) e.location!,
                                  ].join(' · '),
                                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                ),
                              ]),
                            ),
                            const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
                          ]),
                        ),
                      ),
                    )),
                    ...selectedGcalEvents.map((e) {
                      final isMine = e.uid == _selfUid;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GestureDetector(
                          onTap: isMine ? () => _openGoogleEventEdit(e.event) : null,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.navySurface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _gcalColor.withValues(alpha: 0.3)),
                            ),
                            child: Row(children: [
                              Container(width: 3, height: 34, decoration: const BoxDecoration(
                                color: _gcalColor, borderRadius: BorderRadius.all(Radius.circular(2)),
                              )),
                              const SizedBox(width: 10),
                              _memberAvatar(context, e.uid),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    if (e.event.visibility == EventVisibility.private) ...[
                                      const Icon(Icons.lock_outline, size: 12, color: AppColors.textMuted),
                                      const SizedBox(width: 3),
                                    ],
                                    Flexible(
                                      child: Text('📅 ${e.event.title}', style: const TextStyle(
                                        fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.cream,
                                      )),
                                    ),
                                  ]),
                                  const SizedBox(height: 3),
                                  Text(
                                    e.event.allDay
                                        ? '終日 · Googleカレンダー'
                                        : '${DateFormat('HH:mm').format(e.event.start)} · Googleカレンダー',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                  ),
                                ]),
                              ),
                              if (isMine)
                                const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
                            ]),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
        ),
      ],
    );
  }
}
