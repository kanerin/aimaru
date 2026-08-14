import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/event_service.dart';
import '../services/ics_import_service.dart';
import '../utils/app_theme.dart';
import '../utils/ics_parser.dart';

enum _LoadStatus { idle, loading, error, loaded }

// ── 他社カレンダーからのインポート ──────────────────────
// TimeTree・Googleカレンダーなど他社アプリのiCalendar(.ics)エクスポートURL、
// または.icsファイルの中身をそのまま貼り付けて予定を取り込む。
// Pairyのようにサービス終了したアプリからの移行者を含め、他社アプリからの
// 乗り換え導線が無い状態を解消する（docs/open-issues.md 課題12）。
class IcsImportScreen extends StatefulWidget {
  final String coupleId;
  // テスト用の注入ポイント。未指定時は本番のIcsImportService/EventServiceを使う。
  // 入力がhttp(s)/webcal始まりならURL取得、それ以外はicsテキストそのものとして扱う。
  final Future<String> Function(String input)? loadIcsTextOverride;
  final EventService? eventServiceOverride;

  const IcsImportScreen({
    super.key,
    required this.coupleId,
    this.loadIcsTextOverride,
    this.eventServiceOverride,
  });

  @override
  State<IcsImportScreen> createState() => _IcsImportScreenState();
}

class _IcsImportScreenState extends State<IcsImportScreen> {
  EventService? _eventServiceInstance;
  EventService get _eventService => widget.eventServiceOverride ?? (_eventServiceInstance ??= EventService());
  final _icsService = IcsImportService();
  final _inputController = TextEditingController();

  _LoadStatus _status = _LoadStatus.idle;
  String? _errorMessage;
  List<IcsParsedEvent> _events = const [];
  List<bool> _selected = const [];
  bool _importing = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<String> _loadIcsText(String input) {
    if (widget.loadIcsTextOverride != null) return widget.loadIcsTextOverride!(input);
    final looksLikeUrl = input.startsWith('http://') ||
        input.startsWith('https://') ||
        input.startsWith('webcal://');
    return looksLikeUrl ? _icsService.fetchIcsText(input) : Future.value(input);
  }

  Future<void> _load() async {
    final input = _inputController.text.trim();
    if (input.isEmpty) return;

    setState(() {
      _status = _LoadStatus.loading;
      _errorMessage = null;
    });

    try {
      final text = await _loadIcsText(input);
      final events = parseIcsEvents(text);
      if (!mounted) return;
      setState(() {
        _events = events;
        _selected = List<bool>.filled(events.length, true);
        _status = _LoadStatus.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _LoadStatus.error;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _importSelected() async {
    final toImport = <IcsParsedEvent>[
      for (var i = 0; i < _events.length; i++)
        if (_selected[i]) _events[i],
    ];
    if (toImport.isEmpty) return;

    setState(() => _importing = true);
    for (final parsed in toImport) {
      await _eventService.addEvent(
        widget.coupleId,
        AimaruEvent(
          id: '',
          coupleId: widget.coupleId,
          title: parsed.title,
          date: parsed.start,
          endDate: parsed.end,
          type: EventType.plan,
          location: parsed.location,
          memo: parsed.description,
          createdBy: '',
          allDay: parsed.allDay,
        ),
      );
    }
    if (!mounted) return;
    setState(() => _importing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${toImport.length}件の予定を追加しました')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('他のカレンダーからインポート')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'TimeTreeやGoogleカレンダーのiCal(.ics)エクスポートURL、または.icsファイルの中身を貼り付けてください',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _inputController,
                maxLines: 4,
                minLines: 1,
                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'https://... または BEGIN:VCALENDAR...',
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _status == _LoadStatus.loading ? null : _load,
                  child: const Text('読み込む'),
                ),
              ),
            ]),
          ),
          const Divider(height: 1, color: AppColors.hairline),
          Expanded(child: _buildBody(context)),
        ],
      ),
      bottomNavigationBar: _status == _LoadStatus.loaded && _events.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _importing ? null : _importSelected,
                  child: _importing
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text('選択した${_selected.where((v) => v).length}件を追加'),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_status) {
      case _LoadStatus.idle:
        return const Center(
          child: Text('URLまたはicsテキストを入力して読み込んでください',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
        );
      case _LoadStatus.loading:
        return Center(child: CircularProgressIndicator(color: appAccent(context)));
      case _LoadStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('読み込みに失敗しました\n${_errorMessage ?? ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
          ),
        );
      case _LoadStatus.loaded:
        if (_events.isEmpty) {
          return const Center(
            child: Text('取り込める予定が見つかりませんでした',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _events.length,
          itemBuilder: (ctx, i) => _buildEventTile(context, i),
        );
    }
  }

  Widget _buildEventTile(BuildContext context, int i) {
    final e = _events[i];
    final dateLabel = e.allDay
        ? DateFormat('M月d日（E）', 'ja').format(e.start)
        : DateFormat('M月d日（E） HH:mm', 'ja').format(e.start);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Material(
        color: Colors.transparent,
        child: CheckboxListTile(
          value: _selected[i],
          onChanged: (v) => setState(() => _selected = [
            for (var j = 0; j < _selected.length; j++) j == i ? (v ?? false) : _selected[j],
          ]),
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: appAccent(context),
          title: Text(e.title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          subtitle: Text(
            e.location != null ? '$dateLabel ・ ${e.location}' : dateLabel,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
