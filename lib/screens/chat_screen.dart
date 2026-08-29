import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/chat_service.dart';
import '../services/storage_service.dart';
import '../services/couple_service.dart';
import '../services/image_save_service.dart';
import '../utils/app_theme.dart';
import '../utils/chat_date_divider.dart';
import '../utils/chat_read_status.dart';
import 'image_detail_screen.dart';

// ── カップル間の通常チャット（AIチャットとは別）───────
class ChatScreen extends StatefulWidget {
  final String coupleId;
  // ホーム画面のIndexedStackはタブを離れてもこの画面をマウントしたまま
  // 保持する（main.dart参照）ため、「表示中のタブかどうか」は親から
  // 明示的に渡してもらう必要がある。
  final bool isActive;
  // テストからFirebaseに触れずに検証するためのオーバーライド（本番の呼び出しはそのまま）。
  final ChatService? chatServiceOverride;
  final CoupleService? coupleServiceOverride;
  final String? currentUidOverride;
  final Stream<List<ChatMessage>>? messagesStreamOverride;

  const ChatScreen({
    super.key,
    required this.coupleId,
    required this.isActive,
    this.chatServiceOverride,
    this.coupleServiceOverride,
    this.currentUidOverride,
    this.messagesStreamOverride,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final _chatService     = widget.chatServiceOverride ?? ChatService();
  final _storageService  = StorageService();
  late final _coupleService   = widget.coupleServiceOverride ?? CoupleService();
  final _imageSaveService = ImageSaveService();
  final _picker          = ImagePicker();
  final _controller      = TextEditingController();
  final _scrollCtrl      = ScrollController();

  // build()の中で作ると、入力のたびの再ビルドで購読し直して履歴が一瞬消える。
  // ストリームは1本だけ作って使い回す。
  late final Stream<List<ChatMessage>> _messagesStream =
      widget.messagesStreamOverride ?? _chatService.watchMessages(widget.coupleId);

  String get _myUid => widget.currentUidOverride ?? FirebaseAuth.instance.currentUser!.uid;
  String? _partnerName;
  // パートナーのuidが分かるまでは既読ストリームを作れないためnullable。
  Stream<DateTime?>? _partnerReadStream;
  bool _sendingImage = false;

  // メッセージ一覧を購読し、このタブを表示している間だけ、初回・新着のたびに
  // 自分の既読時刻を更新する（画面を開いている＝既読、が自然なチャットの既読UX）。
  // isActiveを見ずに更新すると、IndexedStackで裏に隠れている間に届いた
  // メッセージまで既読扱いになってしまう（パートナーが見ていないのに
  // 「既読」と出る不具合の原因だった）。
  late final StreamSubscription<List<ChatMessage>> _readMarkerSub;

  @override
  void initState() {
    super.initState();
    _loadPartner();
    _readMarkerSub = _messagesStream.listen(
      (_) {
        if (widget.isActive) {
          _chatService.markAsRead(widget.coupleId);
        }
      },
      // 通信・権限エラーはStreamBuilder側の表示で扱うので、ここでは
      // 拾い手のない例外として落ちないよう握りつぶす。
      onError: (_) {},
    );
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 裏に隠れている間に届いたメッセージも、タブを開いた瞬間に既読にする。
    if (widget.isActive && !oldWidget.isActive) {
      _chatService.markAsRead(widget.coupleId);
    }
  }

  @override
  void dispose() {
    _readMarkerSub.cancel();
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPartner() async {
    final couple = await _coupleService.getMyCouple();
    if (couple == null) return;
    final partnerId = couple.memberIds.firstWhere((id) => id != _myUid, orElse: () => '');
    final name = await _coupleService.getPartnerName(couple);
    if (!mounted) return;
    setState(() {
      _partnerName = name;
      if (partnerId.isNotEmpty) {
        _partnerReadStream = _chatService.watchPartnerLastReadAt(widget.coupleId, partnerId);
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await _chatService.sendMessage(widget.coupleId, text: text);
    _scrollToBottom();
  }

  Future<void> _sendImage() async {
    // トーク画面が重くならないよう、送信前に解像度・容量を抑える
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1440,
    );
    if (file == null) return;

    setState(() => _sendingImage = true);
    try {
      final url = await _storageService.uploadChatImage(widget.coupleId, File(file.path));
      await _chatService.sendMessage(widget.coupleId, imageUrl: url);
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  void _copyText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('コピーしました'), duration: Duration(seconds: 1)),
    );
  }

  void _openImageDetail(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ImageDetailScreen(imageUrl: url)),
    );
  }

  Future<void> _saveImageToDevice(String url) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('保存中...'), duration: Duration(seconds: 1)),
    );
    final ok = await _imageSaveService.saveFromUrl(url);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '画像を保存しました' : '保存に失敗しました'),
        backgroundColor: ok ? AppColors.success : null,
      ),
    );
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
              gradient: LinearGradient(colors: [AppColors.pinkAccent, appAccent(context)]),
              shape: BoxShape.circle,
            ),
            child: Center(child: Text(
              (_partnerName != null && _partnerName!.isNotEmpty) ? _partnerName!.substring(0, 1) : '2',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
            )),
          ),
          const SizedBox(width: 10),
          Text(_partnerName ?? 'パートナー', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).unfocus(),
              child: StreamBuilder<DateTime?>(
                stream: _partnerReadStream ?? const Stream<DateTime?>.empty(),
                builder: (context, readSnap) {
                  final partnerLastReadAt = readSnap.data;
                  return StreamBuilder<List<ChatMessage>>(
                    stream: _messagesStream,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return const Center(
                          child: Text('メッセージの読み込みに失敗しました',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                        );
                      }
                      final messages = snap.data ?? [];
                      if (!snap.hasData) {
                        return Center(child: CircularProgressIndicator(color: appAccent(context)));
                      }
                      if (messages.isEmpty) {
                        return const Center(
                          child: Text('まだメッセージがありません\n最初のひとことを送ってみましょう',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
                        );
                      }
                      _scrollToBottom();
                      final lastMyIndex = messages.lastIndexWhere((m) => m.senderId == _myUid);
                      return ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (ctx, i) {
                          final message = messages[i];
                          final showDivider = shouldShowDateDivider(
                            i == 0 ? null : messages[i - 1].timestamp,
                            message.timestamp,
                          );
                          final showRead = i == lastMyIndex &&
                              isReadByPartner(message.timestamp, partnerLastReadAt);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showDivider) _buildDateDivider(message.timestamp),
                              _buildBubble(message, showRead: showRead),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            decoration: const BoxDecoration(
              color: AppColors.navyCard,
              border: Border(top: BorderSide(color: AppColors.hairline)),
            ),
            child: Row(children: [
              GestureDetector(
                onTap: _sendingImage ? null : _sendImage,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: AppColors.navySurface, borderRadius: BorderRadius.circular(18)),
                  child: _sendingImage
                      ? Padding(padding: const EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2, color: appAccentSoft(context)))
                      : const Icon(Icons.camera_alt_outlined, size: 16, color: AppColors.textSecond),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'メッセージを入力...',
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _send,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: appAccent(context), shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_upward, color: Colors.white, size: 18),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // 日付を跨いだところに出すセンターラインの区切り（#68）。
  // LINEなどのトーク画面と同じく、その日最初のメッセージの上に表示する。
  Widget _buildDateDivider(DateTime date) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.navySurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            DateFormat('M月d日（E）', 'ja').format(date),
            style: const TextStyle(
              fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(ChatMessage m, {bool showRead = false}) {
    final isMe = m.senderId == _myUid;
    final timeStr = DateFormat('HH:mm').format(m.timestamp);

    Widget content;
    if (m.imageUrl != null) {
      content = Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16).copyWith(
              bottomLeft: isMe ? null : const Radius.circular(4),
              bottomRight: isMe ? const Radius.circular(4) : null,
            ),
            child: GestureDetector(
              onTap: () => _openImageDetail(m.imageUrl!),
              onLongPress: () => _saveImageToDevice(m.imageUrl!),
              child: CachedNetworkImage(
                imageUrl: m.imageUrl!, width: 180, fit: BoxFit.cover,
                memCacheWidth: 360, // 表示サイズに対して過大な解像度でデコードしない
                placeholder: (_, __) => Container(width: 180, height: 140, color: AppColors.navySurface),
              ),
            ),
          ),
          Positioned(
            right: 6, bottom: 6,
            child: GestureDetector(
              onTap: () => _saveImageToDevice(m.imageUrl!),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.download_rounded, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      );
    } else {
      content = GestureDetector(
        onLongPress: () => _copyText(m.text),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMe ? appAccent(context) : AppColors.navySurface,
            borderRadius: BorderRadius.circular(18).copyWith(
              bottomLeft: isMe ? null : const Radius.circular(4),
              bottomRight: isMe ? const Radius.circular(4) : null,
            ),
            border: isMe ? null : Border.all(color: AppColors.hairline),
          ),
          child: Text(m.text, style: TextStyle(
            fontSize: 13, color: isMe ? Colors.white : AppColors.textPrimary, height: 1.5,
          )),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 4, left: isMe ? 48 : 0, right: isMe ? 0 : 48),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          content,
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showRead) ...[
                  Text('既読', style: TextStyle(fontSize: 9.5, color: appAccentSoft(context))),
                  const SizedBox(width: 4),
                ],
                Text(timeStr, style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
