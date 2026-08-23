import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/event_service.dart';
import '../services/event_comment_service.dart';
import '../services/google_calendar_service.dart';
import '../utils/app_theme.dart';
import 'event_form_screen.dart';

class EventDetailScreen extends StatefulWidget {
  final AimaruEvent event;
  final String coupleId;
  // テストからエラー/データを直接流し込むための注入ポイント。
  // 未指定時は本番のFirestoreストリームを使う。
  final Stream<List<EventComment>>? commentsStreamOverride;
  // テストからfake_cloud_firestore等を差し込むための注入ポイント。
  final EventCommentService? commentServiceOverride;
  // テストからFirebase Authに触れずに「自分」を差し込むための注入ポイント。
  final String? currentUidOverride;
  const EventDetailScreen({
    super.key,
    required this.event,
    required this.coupleId,
    this.commentsStreamOverride,
    this.commentServiceOverride,
    this.currentUidOverride,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  // EventService() は生成時にFirebaseFirestore.instanceへ即座に触れるため、
  // コメント機能のテスト（commentsStreamOverrideのみ差し込む）ではFirebase
  // 初期化なしに動けるよう、実際に使うときまで生成を遅らせる。
  EventService? _eventServiceInstance;
  EventService get _eventService => _eventServiceInstance ??= EventService();
  final _calendarService = GoogleCalendarService();

  EventCommentService? _commentServiceInstance;
  EventCommentService get _commentService =>
      _commentServiceInstance ??= widget.commentServiceOverride ?? EventCommentService();

  late final Stream<List<EventComment>> _commentsStream = widget.commentsStreamOverride ??
      _commentService.watchComments(widget.coupleId, widget.event.id);

  String get _uid => widget.currentUidOverride ?? FirebaseAuth.instance.currentUser!.uid;

  final _pageCtrl        = PageController();
  final _commentCtrl     = TextEditingController();
  int _page = 0;
  bool _deleting = false;
  bool _sendingComment = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    _commentCtrl.clear();
    setState(() => _sendingComment = true);
    try {
      await _commentService.addComment(widget.coupleId, widget.event.id, text);
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EventFormScreen(
        coupleId: widget.coupleId, existing: widget.event,
      )),
    );
    // 保存された場合は一覧側の最新データを見せるため詳細画面を閉じる
    if (saved == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('この予定を削除しますか？'),
        content: Text('「${widget.event.title}」を削除します。ゴミ箱に移動し、30日間は設定画面から復元できます。',
          style: const TextStyle(color: AppColors.textSecond, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除する', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await _eventService.deleteEvent(widget.event);
      if (widget.event.googleCalendarEventId != null) {
        await _calendarService.deleteEvent(widget.event.googleCalendarEventId!);
      }
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final dateStr = e.allDay
        ? DateFormat('M月d日（E）', 'ja').format(e.date)
        : DateFormat('M月d日（E）HH:mm', 'ja').format(e.date);

    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: _edit,
            child: const Text('編集', style: TextStyle(color: AppColors.lavenderSoft, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildContent(e, dateStr)),
          _buildCommentInput(),
        ],
      ),
    );
  }

  Widget _buildContent(AimaruEvent e, String dateStr) {
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (e.imageUrls.isNotEmpty) ...[
            SizedBox(
              height: 220,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: PageView.builder(
                      controller: _pageCtrl,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemCount: e.imageUrls.length,
                      itemBuilder: (ctx, i) => CachedNetworkImage(
                        imageUrl: e.imageUrls[i],
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: AppColors.navySurface),
                      ),
                    ),
                  ),
                  if (e.imageUrls.length > 1)
                    Positioned(
                      bottom: 10, left: 0, right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(e.imageUrls.length, (i) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          width: 5, height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _page ? Colors.white : Colors.white38,
                          ),
                        )),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          Text('${e.type.emoji} ${e.title}', style: const TextStyle(
            fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.cream,
          )),
          const SizedBox(height: 14),

          _MetaRow(icon: Icons.calendar_today, text: dateStr),
          if (e.location != null) _MetaRow(icon: Icons.location_on_outlined, text: e.location!),
          _MetaRow(icon: Icons.repeat, text: e.recurring ? '毎年繰り返し' : '繰り返しなし'),

          if (e.memo != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.navySurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Text(e.memo!, style: const TextStyle(
                fontSize: 13, color: AppColors.textSecond, height: 1.7,
              )),
            ),
          ],

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.navySurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
            ),
            height: 48,
            child: Row(children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: const Center(child: Text('G', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF4285F4),
                ))),
              ),
              const SizedBox(width: 10),
              const Expanded(child: Text('Googleカレンダー同期', style: TextStyle(
                fontSize: 12.5, color: AppColors.textSecond,
              ))),
              Text(
                e.googleCalendarEventId != null ? '同期済み' : '未同期',
                style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600,
                  color: e.googleCalendarEventId != null ? AppColors.success : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 10),
            ]),
          ),

          const SizedBox(height: 24),
          _buildCommentsSection(),

          const SizedBox(height: 28),
          Center(
            child: TextButton(
              onPressed: _deleting ? null : _delete,
              child: _deleting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                  : const Text('この予定を削除', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
          ),
        ],
    );
  }

  // 予定ごとのコメント一覧。予定の詳細画面はカレンダーから何度も開き直される
  // ため、ここも1本のストリームを作って使い回す（build()内で作ると開くたびに
  // 購読し直してしまう）。
  Widget _buildCommentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('コメント', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecond,
        )),
        const SizedBox(height: 10),
        StreamBuilder<List<EventComment>>(
          stream: _commentsStream,
          builder: (context, snap) {
            // hasDataだけを見ていると、権限エラー等でストリームがエラーに
            // 落ちたときに無限ローディングのまま固まる
            // （test/screens/todos_screen_test.dartと同じ理由）。
            if (snap.hasError) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('コメントの読み込みに失敗しました',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              );
            }
            if (!snap.hasData) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: appAccent(context)))),
              );
            }
            final comments = snap.data!;
            if (comments.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('まだコメントはありません',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              );
            }
            return Column(children: comments.map(_buildCommentTile).toList());
          },
        ),
      ],
    );
  }

  Widget _buildCommentTile(EventComment c) {
    final isMe = c.senderId == _uid;
    final timeStr = DateFormat('M/d HH:mm').format(c.createdAt);
    return Padding(
      padding: EdgeInsets.only(bottom: 8, left: isMe ? 40 : 0, right: isMe ? 0 : 40),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMe ? appAccent(context) : AppColors.navySurface,
              borderRadius: BorderRadius.circular(16).copyWith(
                bottomLeft: isMe ? null : const Radius.circular(4),
                bottomRight: isMe ? const Radius.circular(4) : null,
              ),
              border: isMe ? null : Border.all(color: AppColors.hairline),
            ),
            child: Text(c.text, style: TextStyle(
              fontSize: 13, color: isMe ? Colors.white : AppColors.textPrimary, height: 1.5,
            )),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
            child: Text(timeStr, style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: const BoxDecoration(
        color: AppColors.navyCard,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _commentCtrl,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'コメントを入力...',
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onSubmitted: (_) => _sendComment(),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _sendingComment ? null : _sendComment,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: appAccent(context), shape: BoxShape.circle),
            child: _sendingComment
                ? const Padding(padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.arrow_upward, color: Colors.white, size: 18),
          ),
        ),
      ]),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 15, color: AppColors.textMuted),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textSecond)),
    ]),
  );
}
