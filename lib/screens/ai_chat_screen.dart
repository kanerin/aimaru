import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../services/gemini_service.dart';
import '../../services/event_service.dart';
import '../../utils/app_theme.dart';

class AiChatScreen extends StatefulWidget {
  final String coupleId;
  const AiChatScreen({super.key, required this.coupleId});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _gemini       = GeminiService();
  final _eventService = EventService();
  final _controller   = TextEditingController();
  final _scrollCtrl   = ScrollController();

  final List<_ChatItem> _messages = [];
  bool _thinking = false;

  // サジェストチップ
  final _suggestions = [
    '星野源の誕生日を追加',
    '来週の土曜デートしたい',
    '付き合って1年の記念日',
    '雨の日のプランを提案して',
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatItem.ai(
      '2人のスケジュール管理をお手伝いします ✦\n'
      '「星野源の誕生日追加して」のように話しかけてみてください',
    ));
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    _controller.clear();

    setState(() {
      _messages.add(_ChatItem.user(text));
      _thinking = true;
    });
    _scrollToBottom();

    // まず予定として解析を試みる（複数件になる場合もある）
    final parsedList = await _gemini.parseEventFromText(text);

    if (parsedList != null && parsedList.isNotEmpty) {
      // 予定として解析できた → 確認カードを表示（複数可）
      setState(() {
        _thinking = false;
        if (parsedList.length > 1) {
          _messages.add(_ChatItem.ai('${parsedList.length}件の予定が見つかりました。確認して追加してください'));
        }
        for (final e in parsedList) {
          _messages.add(_ChatItem.eventPreview(e));
        }
      });
    } else {
      // 通常チャット
      final history = _messages
          .where((m) => m.type != _ChatType.eventPreview)
          .map((m) => {'role': m.isAi ? 'assistant' : 'user', 'text': m.text ?? ''})
          .toList();
      final reply = await _gemini.chat(text, history);

      setState(() {
        _thinking = false;
        _messages.add(_ChatItem.ai(reply));
      });
    }
    _scrollToBottom();
  }

  Future<void> _confirmEvent(_ChatItem item, GeminiParsedEvent event) async {
    // 確認カードを「追加済み」に更新（この特定のカードだけを対象にする）
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
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('AIMARU AI', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text('オンライン', style: TextStyle(fontSize: 10, color: AppColors.success)),
          ]),
        ]),
      ),
      body: Column(
        children: [
          // ── メッセージ一覧 ──
          Expanded(
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

    final isAi = item.isAi;
    return Padding(
      padding: EdgeInsets.only(
        bottom: 12,
        left: isAi ? 0 : 48,
        right: isAi ? 48 : 0,
      ),
      child: Align(
        alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
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
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _Dot(delay: 0),
            const SizedBox(width: 4),
            _Dot(delay: 200),
            const SizedBox(width: 4),
            _Dot(delay: 400),
          ]),
        ),
      ),
    );
  }
}

// ── チャットアイテムモデル ──────────────────────────
enum _ChatType { user, ai, eventPreview }

class _ChatItem {
  final _ChatType type;
  final String? text;
  final GeminiParsedEvent? event;

  _ChatItem._({required this.type, this.text, this.event});

  factory _ChatItem.user(String t)                   => _ChatItem._(type: _ChatType.user, text: t);
  factory _ChatItem.ai(String t)                     => _ChatItem._(type: _ChatType.ai, text: t);
  factory _ChatItem.eventPreview(GeminiParsedEvent e)=> _ChatItem._(type: _ChatType.eventPreview, event: e);

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
