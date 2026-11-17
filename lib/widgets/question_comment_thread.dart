import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../utils/app_theme.dart';

// ── ふたりの質問：その日の回答へのコメント欄 ─────────────────
// 2人の回答が出そろった日のカードの下に置く。回答そのものは書き換えられない
// ので、「それ意外！」「今度行こう」のような反応はここで続ける。
// 入力欄は最初から出しておく日（今日）と、「コメントする」を押してから
// 出す日（これまでの質問。カードごとに入力欄が並ぶと読みにくいため）がある。
class QuestionCommentThread extends StatefulWidget {
  // その日のコメント（古い順に並べて渡す）。読み込み中はnull。
  final List<QuestionComment>? comments;
  // コメントの読み込みに失敗したか。回答は読めているので、画面全体ではなく
  // この欄だけで知らせる。
  final bool hasError;
  final String myUid;
  final String partnerName;
  final bool initiallyExpanded;
  final Future<void> Function(String text) onSend;

  const QuestionCommentThread({
    super.key,
    required this.comments,
    required this.myUid,
    required this.partnerName,
    required this.onSend,
    this.hasError = false,
    this.initiallyExpanded = false,
  });

  static const maxLength = 500;

  @override
  State<QuestionCommentThread> createState() => _QuestionCommentThreadState();
}

class _QuestionCommentThreadState extends State<QuestionCommentThread> {
  final _controller = TextEditingController();
  late bool _expanded = widget.initiallyExpanded;
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(text);
      _controller.clear();
    } catch (_) {
      // 失敗しても入力は消さず、押し直せる状態に戻す。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('コメントの送信に失敗しました。もう一度お試しください')),
        );
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final comments = widget.comments ?? const <QuestionComment>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.hasError)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('コメントを読み込めませんでした',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
        for (final c in comments) _buildComment(c),
        if (_expanded)
          _buildInput()
        else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = true),
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: Text(comments.isEmpty ? 'コメントする' : '返信する'),
            ),
          ),
      ],
    );
  }

  Widget _buildComment(QuestionComment c) {
    final isMine = c.senderId == widget.myUid;
    final name = isMine ? 'あなた' : widget.partnerName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isMine
                  ? appAccent(context).withValues(alpha: 0.15)
                  : AppColors.navyCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$name · ${DateFormat('M/d H:mm').format(c.createdAt)}',
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.textMuted)),
                const SizedBox(height: 2),
                Text(c.text,
                    style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textPrimary,
                        height: 1.45)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput() => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              maxLength: QuestionCommentThread.maxLength,
              textInputAction: TextInputAction.newline,
              style:
                  const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: '回答にコメント',
                counterText: '',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'コメントを送信',
            onPressed: _sending ? null : _send,
            icon: Icon(Icons.send,
                color: _sending ? AppColors.textMuted : appAccent(context)),
          ),
        ],
      );
}
