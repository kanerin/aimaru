import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../services/gemini_service.dart';
import '../../services/event_service.dart';
import '../../services/google_calendar_cache_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/recurring_events.dart';

class AiChatScreen extends StatefulWidget {
  final String coupleId;
  // テスト用の差し替え口（本番は未指定でImagePicker/GeminiServiceを直接使う）。
  final EventService? eventServiceOverride;
  final Future<XFile?> Function()? pickImageOverride;
  final Future<GeminiReply> Function(
    Uint8List imageBytes,
    String mimeType, {
    required List<Map<String, String>> history,
    required String eventsContext,
  })? analyzeImageOverride;

  const AiChatScreen({
    super.key,
    required this.coupleId,
    this.eventServiceOverride,
    this.pickImageOverride,
    this.analyzeImageOverride,
  });

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> with WidgetsBindingObserver {
  final _gemini             = GeminiService();
  late final _eventService  = widget.eventServiceOverride ?? EventService();
  final _gcalCacheService   = GoogleCalendarCacheService();
  final _picker             = ImagePicker();
  final _controller         = TextEditingController();
  final _scrollCtrl         = ScrollController();
  bool _pickingImage = false;

  String get _selfUid => FirebaseAuth.instance.currentUser!.uid;

  final List<_ChatItem> _messages = [];
  bool _thinking = false;

  // サジェストチップ（実在の人物名は使わない）
  final _suggestions = [
    '好きなアーティストの誕生日を追加',
    '来週の土曜デートしたい',
    '付き合って1年の記念日',
    '来週の予定を教えて',
  ];

  static const _greeting =
      '2人のスケジュール管理をお手伝いします ✦\n'
      '「来週の土曜デートしたい」のように話しかけたり、「来週の予定は？」と聞いたりしてみてください';

  // IndexedStackで4画面を保持しているため、アプリを閉じてもプロセスが生きていれば
  // 会話が残り続ける。一度アプリを離れたら、戻ってきた時点で新しい会話から始める。
  bool _wasPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messages.add(_ChatItem.ai(_greeting));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasPaused = true;
      return;
    }
    if (state != AppLifecycleState.resumed) return;

    final wasPaused = _wasPaused;
    _wasPaused = false;
    if (!wasPaused) return;
    // 送信の途中で戻ってきた場合に応答を捨てると混乱するので、そのときは触らない
    if (_thinking) return;
    if (_messages.length <= 1) return;
    _resetConversation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('会話をリセットしますか？'),
        content: const Text(
          'これまでのやり取りを消して最初から始めます。追加済みの予定はそのまま残ります。',
          style: TextStyle(color: AppColors.textSecond, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('リセット')),
        ],
      ),
    );
    if (confirmed == true) _resetConversation();
  }

  void _resetConversation() {
    setState(() {
      _messages
        ..clear()
        ..add(_ChatItem.ai(_greeting));
      _thinking = false;
    });
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    _controller.clear();

    setState(() {
      _messages.add(_ChatItem.user(text));
      _thinking = true;
    });
    _scrollToBottom();

    try {
      final history = _historyForRequest();
      final eventsContext = await _eventsContextWithFallback();

      final reply = await _gemini.respond(text, history, eventsContext: eventsContext);
      if (!mounted) return;

      setState(() {
        _thinking = false;
        _applyReply(reply);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _thinking = false;
        _messages.add(_ChatItem.ai('エラーが発生しました。もう一度試してください'));
      });
    }
    _scrollToBottom();
  }

  // ── 画像（他社カレンダーのスクショ、招待状など）から予定候補を抽出する ──
  Future<void> _sendImage() async {
    if (_pickingImage) return;

    setState(() => _pickingImage = true);
    XFile? file;
    try {
      file = await (widget.pickImageOverride?.call() ??
          _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600));
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final mimeType = file.mimeType ?? 'image/jpeg';

    setState(() {
      _messages.add(_ChatItem.userImage(bytes));
      _thinking = true;
    });
    _scrollToBottom();

    try {
      final history = _historyForRequest();
      final eventsContext = await _eventsContextWithFallback();

      final reply = await (widget.analyzeImageOverride?.call(
            bytes, mimeType,
            history: history, eventsContext: eventsContext,
          ) ??
          _gemini.respondToImage(bytes, mimeType, history: history, eventsContext: eventsContext));
      if (!mounted) return;

      setState(() {
        _thinking = false;
        _applyReply(reply);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _thinking = false;
        _messages.add(_ChatItem.ai('画像の解析に失敗しました。もう一度試してください'));
      });
    }
    _scrollToBottom();
  }

  // 直前に送信したメッセージ（テキストまたは画像）は履歴とAI呼び出しの
  // 両方に含めないよう除いた上で、テキストの会話履歴だけを組み立てる。
  List<Map<String, String>> _historyForRequest() {
    final withoutLast =
        _messages.length > 1 ? _messages.sublist(0, _messages.length - 1) : const <_ChatItem>[];
    return withoutLast
        .where((m) => m.type == _ChatType.user || m.type == _ChatType.ai)
        .map((m) => {'role': m.isAi ? 'assistant' : 'user', 'text': m.text ?? ''})
        .toList();
  }

  // 予定の参照に使う直近の予定一覧（このアプリの予定 + Googleカレンダーの
  // 自分/パートナーの予定）。取得に失敗しても会話自体は続けられるように、
  // ここだけ個別にフォールバックする（例: 通信が不安定な状態から復帰した直後など）。
  Future<String> _eventsContextWithFallback() async {
    try {
      return await _buildEventsContext().timeout(const Duration(seconds: 6));
    } catch (_) {
      return 'なし';
    }
  }

  void _applyReply(GeminiReply reply) {
    if (reply.kind == GeminiReplyKind.events) {
      if (reply.events.length > 1) {
        final batchId = DateTime.now().microsecondsSinceEpoch;
        _messages.add(_ChatItem.bulkAdd(reply.events, batchId));
        for (final e in reply.events) {
          _messages.add(_ChatItem.eventPreview(e, batchId: batchId));
        }
      } else {
        _messages.add(_ChatItem.eventPreview(reply.events.first));
      }
    } else {
      _messages.add(_ChatItem.ai(reply.text));
    }
  }

  // AIに渡す「直近の予定」テキストを組み立てる。
  // このアプリの予定(Firestore)と、Googleカレンダーの自分・パートナー双方の
  // 予定をまとめる（このアプリから同期済みのGoogle予定は重複するので除く）。
  Future<String> _buildEventsContext() async {
    final aimaru = await _eventService.watchUpcomingEvents(widget.coupleId, limit: 30).first;
    final recurring = await _eventService.watchRecurringEvents(widget.coupleId).first;
    final syncedIds = {
      for (final e in aimaru)
        if (e.googleCalendarEventId != null) e.googleCalendarEventId!,
    };

    final gcalByUid = await _gcalCacheService.watchAll(widget.coupleId).first;

    final entries = <({DateTime date, String line})>[];
    final seen = <String>{};
    for (final e in aimaru) {
      seen.add(e.id);
      final dateStr = DateFormat('yyyy-MM-dd(E) HH:mm', 'ja').format(e.date);
      final loc = e.location != null ? ' @ ${e.location}' : '';
      entries.add((date: e.date, line: '- $dateStr ${e.title}$loc'));
    }

    // 誕生日や記念日は生年月日など過去の日付で登録されるため、
    // 「今後の予定」には出てこない。次の発生日を足しておかないと、
    // 「◯◯の誕生日は登録されている?」に答えられず、AIが推測で答えてしまう。
    final now0 = DateTime.now();
    for (final e in recurring) {
      if (seen.contains(e.id)) continue;
      final next = nextOccurrence(e.date, from: now0);
      final dateStr = DateFormat('yyyy-MM-dd(E)', 'ja').format(next);
      entries.add((date: next, line: '- $dateStr ${e.title}（毎年繰り返し）'));
    }

    final now = DateTime.now();
    gcalByUid.forEach((uid, events) {
      final who = uid == _selfUid ? '自分' : 'パートナー';
      for (final e in events) {
        if (syncedIds.contains(e.id)) continue;
        if (e.start.isBefore(now)) continue;
        final dateStr = DateFormat('yyyy-MM-dd(E) HH:mm', 'ja').format(e.start);
        entries.add((date: e.start, line: '- $dateStr ${e.title}（Googleカレンダー・$whoの予定）'));
      }
    });

    if (entries.isEmpty) return 'なし';
    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries.map((e) => e.line).join('\n');
  }

  Future<void> _confirmEvent(_ChatItem item, GeminiParsedEvent event) async {
    setState(() {
      final idx = _messages.indexOf(item);
      if (idx >= 0) _messages[idx] = _ChatItem.ai('「${event.title}」をカレンダーに追加しました ✅');
    });

    await _eventService.addFromGemini(widget.coupleId, event);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${event.title} を追加しました'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _confirmBulk(_ChatItem item) async {
    final events = item.events!;
    final batchId = item.batchId;

    setState(() {
      final idx = _messages.indexOf(item);
      if (idx >= 0) _messages[idx] = _ChatItem.ai('${events.length}件まとめてカレンダーに追加しました ✅');
      if (batchId != null) {
        for (var i = 0; i < _messages.length; i++) {
          final m = _messages[i];
          if (m.type == _ChatType.eventPreview && m.batchId == batchId) {
            _messages[i] = _ChatItem.ai('「${m.event!.title}」を追加しました ✅');
          }
        }
      }
    });

    await Future.wait(events.map((e) => _eventService.addFromGemini(widget.coupleId, e)));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${events.length}件の予定を追加しました'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        title: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [appAccent(context), AppColors.pinkAccent],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(child: Text('✦', style: TextStyle(fontSize: 14))),
          ),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AIMARU AI', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text('オンライン', style: TextStyle(fontSize: 10, color: AppColors.success)),
          ]),
        ]),
        actions: [
          IconButton(
            tooltip: '会話をリセット',
            icon: const Icon(Icons.refresh, color: AppColors.textSecond),
            onPressed: _messages.length <= 1 ? null : _confirmReset,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── メッセージ一覧 ──
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).unfocus(),
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_thinking ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i == _messages.length) return _buildThinking();
                  return _buildMessage(_messages[i]);
                },
              ),
            ),
          ),

          // ── サジェストチップ（初回のみ）──
          if (_messages.length <= 1)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: _suggestions.map((s) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _send(s),
                    child: Chip(
                      label: Text(s, style: const TextStyle(fontSize: 12)),
                      backgroundColor: AppColors.navySurface,
                      side: const BorderSide(color: AppColors.hairline),
                    ),
                  ),
                )).toList(),
              ),
            ),

          // ── 入力欄 ──
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            decoration: const BoxDecoration(
              color: AppColors.navyCard,
              border: Border(top: BorderSide(color: AppColors.hairline)),
            ),
            child: Row(
              children: [
                Tooltip(
                  message: '画像から予定を読み取る',
                  child: GestureDetector(
                    onTap: _pickingImage ? null : _sendImage,
                    child: Container(
                      width: 40, height: 40,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: AppColors.navySurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: _pickingImage
                          ? const Padding(
                              padding: EdgeInsets.all(11),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.add_photo_alternate_outlined,
                              color: AppColors.textSecond, size: 20,
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: '予定を追加、プランを相談...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: _send,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _send(_controller.text),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: appAccent(context),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.arrow_upward, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(_ChatItem item) {
    if (item.type == _ChatType.eventPreview) {
      return _buildEventPreview(item);
    }
    if (item.type == _ChatType.bulkAdd) {
      return _buildBulkAdd(item);
    }
    if (item.type == _ChatType.userImage) {
      return _buildUserImage(item);
    }

    final isAi = item.isAi;
    return Padding(
      padding: EdgeInsets.only(
        bottom: 12,
        left: isAi ? 0 : 48,
        right: isAi ? 48 : 0,
      ),
      child: Align(
        alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
        child: GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: item.text ?? ''));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('コピーしました'), duration: Duration(seconds: 1)),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isAi ? AppColors.navySurface : appAccent(context),
              borderRadius: BorderRadius.circular(18).copyWith(
                bottomLeft: isAi ? const Radius.circular(4) : null,
                bottomRight: !isAi ? const Radius.circular(4) : null,
              ),
              border: isAi ? Border.all(color: AppColors.hairline) : null,
            ),
            child: Text(
              item.text ?? '',
              style: TextStyle(
                fontSize: 13,
                color: isAi ? AppColors.textPrimary : Colors.white,
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBulkAdd(_ChatItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 48),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _confirmBulk(item),
            icon: const Icon(Icons.playlist_add_check, size: 18),
            label: Text('${item.events!.length}件まとめて追加する', style: const TextStyle(fontSize: 13)),
          ),
        ),
      ),
    );
  }

  Widget _buildUserImage(_ChatItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 48),
      child: Align(
        alignment: Alignment.centerRight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: const Radius.circular(4),
          ),
          child: Image.memory(
            item.imageBytes!,
            width: 160,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  Widget _buildEventPreview(_ChatItem item) {
    final event = item.event!;
    final dateStr = DateFormat('M月d日（E）', 'ja').format(event.date);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 48),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.navySurface,
            borderRadius: BorderRadius.circular(18).copyWith(
              bottomLeft: const Radius.circular(4),
            ),
            border: Border.all(color: appAccent(context).withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI PARSE',
                style: TextStyle(
                  fontSize: 9, letterSpacing: 2,
                  color: appAccentSoft(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${event.type.emoji} ${event.title}',
                style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.cream,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$dateStr${event.recurring ? ' · 毎年繰り返し' : ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecond),
              ),
              if (event.location != null) ...[
                const SizedBox(height: 2),
                Text('📍 ${event.location}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecond)),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _confirmEvent(item, event),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('追加する', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      final idx = _messages.indexOf(item);
                      if (idx >= 0) _messages[idx] = _ChatItem.ai('キャンセルしました。何か変更はありますか？');
                    }),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: AppColors.hairlineStrong),
                      foregroundColor: AppColors.textSecond,
                    ),
                    child: const Text('変更する', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThinking() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.navySurface,
            borderRadius: BorderRadius.circular(18).copyWith(
              bottomLeft: const Radius.circular(4),
            ),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            _Dot(delay: 0),
            SizedBox(width: 4),
            _Dot(delay: 200),
            SizedBox(width: 4),
            _Dot(delay: 400),
          ]),
        ),
      ),
    );
  }
}

// ── チャットアイテムモデル ──────────────────────────
enum _ChatType { user, ai, eventPreview, bulkAdd, userImage }

class _ChatItem {
  final _ChatType type;
  final String? text;
  final GeminiParsedEvent? event;
  final List<GeminiParsedEvent>? events;
  final int? batchId;
  final Uint8List? imageBytes;

  _ChatItem._({
    required this.type,
    this.text,
    this.event,
    this.events,
    this.batchId,
    this.imageBytes,
  });

  factory _ChatItem.user(String t) => _ChatItem._(type: _ChatType.user, text: t);
  factory _ChatItem.ai(String t)   => _ChatItem._(type: _ChatType.ai, text: t);
  factory _ChatItem.eventPreview(GeminiParsedEvent e, {int? batchId}) =>
      _ChatItem._(type: _ChatType.eventPreview, event: e, batchId: batchId);
  factory _ChatItem.bulkAdd(List<GeminiParsedEvent> events, int batchId) =>
      _ChatItem._(type: _ChatType.bulkAdd, events: events, batchId: batchId);
  factory _ChatItem.userImage(Uint8List bytes) =>
      _ChatItem._(type: _ChatType.userImage, imageBytes: bytes);

  bool get isAi => type == _ChatType.ai;
}

// ── ローディングドット ─────────────────────────────
class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
    _anim = Tween(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(
      width: 6, height: 6,
      decoration: BoxDecoration(
        color: appAccentSoft(context),
        shape: BoxShape.circle,
      ),
    ),
  );

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
}
