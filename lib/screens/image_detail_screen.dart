import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/image_save_service.dart';

// ── トーク画面などで画像をタップした際の拡大表示 ─────────
class ImageDetailScreen extends StatefulWidget {
  final String imageUrl;
  const ImageDetailScreen({super.key, required this.imageUrl});

  @override
  State<ImageDetailScreen> createState() => _ImageDetailScreenState();
}

class _ImageDetailScreenState extends State<ImageDetailScreen> {
  final _imageSaveService = ImageSaveService();
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await _imageSaveService.saveFromUrl(widget.imageUrl);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '画像を保存しました' : '保存に失敗しました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '閉じる',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_rounded),
            tooltip: '画像を保存',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: CachedNetworkImage(
            imageUrl: widget.imageUrl,
            fit: BoxFit.contain,
            placeholder: (_, __) => const CircularProgressIndicator(color: Colors.white),
            errorWidget: (_, __, ___) => const ImageDetailLoadError(),
          ),
        ),
      ),
    );
  }
}

// 拡大表示で画像を読み込めなかったときの表示。アイコンだけだと「読み込み中の
// まま固まったのか、壊れたのか」が分からず、次に何をすればよいかも伝わらない
// ため、理由と対処（戻ってもう一度開く）を文言で示す。
@visibleForTesting
class ImageDetailLoadError extends StatelessWidget {
  const ImageDetailLoadError({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: '画像を読み込めませんでした。通信状況を確認して、もう一度開いてください',
        excludeSemantics: true,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
              SizedBox(height: 12),
              Text(
                '画像を読み込めませんでした\n通信状況を確認して、もう一度開いてください',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
      );
}
