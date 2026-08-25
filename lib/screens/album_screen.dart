import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import '../services/album_service.dart';
import '../services/storage_service.dart';
import '../utils/app_theme.dart';
import 'image_detail_screen.dart';

// ── 共有アルバム ────────────────────────────────────────
// 予定に紐づかない写真を気軽に置ける場所。COUPPLY・Betweenなど主要な
// カップルアプリはいずれも専用の共有アルバムを持つが、AIMARUには
// これまで予定へ添付する形でしか写真を残せなかった
// （2026年8月時点の競合調査）。
class AlbumScreen extends StatefulWidget {
  final String coupleId;
  // テスト用の注入ポイント。未指定時は本番のFirestore/Storageを使う。
  final AlbumService? albumServiceOverride;
  final StorageService? storageServiceOverride;
  // テストからエラー/データを直接流し込むための注入ポイント。
  final Stream<List<AlbumPhoto>>? photosStreamOverride;
  // 実機のImagePickerを操作せずに「選択済み」の状態からアップロード
  // フローを検証できるようにするテスト用の注入ポイント
  // （bug_report_screen.dartのinitialImagesForTestと同じ設計）。
  final List<File>? imagesToUploadForTest;

  const AlbumScreen({
    super.key,
    required this.coupleId,
    this.albumServiceOverride,
    this.storageServiceOverride,
    this.photosStreamOverride,
    this.imagesToUploadForTest,
  });

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  // AlbumService()/StorageService() は生成時にFirebaseへ即座に触れるため、
  // override系を使うテストではFirebase初期化なしに動けるよう
  // 実際に使うときまで生成を遅らせる。
  AlbumService? _albumServiceInstance;
  AlbumService get _albumService =>
      _albumServiceInstance ??= widget.albumServiceOverride ?? AlbumService();
  StorageService? _storageServiceInstance;
  StorageService get _storageService =>
      _storageServiceInstance ??= widget.storageServiceOverride ?? StorageService();

  late final Stream<List<AlbumPhoto>> _photosStream =
      widget.photosStreamOverride ?? _albumService.watchPhotos(widget.coupleId);

  final _picker = ImagePicker();
  bool _uploading = false;

  Future<void> _addPhotos() async {
    final files = widget.imagesToUploadForTest ??
        (await _picker.pickMultiImage()).map((f) => File(f.path)).toList();
    if (files.isEmpty) return;

    setState(() => _uploading = true);
    try {
      for (final file in files) {
        final url = await _storageService.uploadAlbumImage(widget.coupleId, file);
        await _albumService.addPhoto(widget.coupleId, url);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('写真の追加に失敗しました')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmDelete(AlbumPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('この写真を削除しますか？'),
        content: const Text('削除すると元に戻せません'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _storageService.deleteImage(photo.imageUrl);
      await _albumService.deletePhoto(photo);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('削除に失敗しました')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        title: const Text('共有アルバム'),
        actions: [
          IconButton(
            icon: _uploading
                ? SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: appAccent(context)),
                  )
                : const Icon(Icons.add_photo_alternate_outlined),
            tooltip: '写真を追加',
            onPressed: _uploading ? null : _addPhotos,
          ),
        ],
      ),
      body: StreamBuilder<List<AlbumPhoto>>(
        stream: _photosStream,
        builder: (context, snap) {
          // hasDataだけを見ていると、権限エラー等でストリームがエラーに
          // 落ちたときに無限ローディングのまま固まる
          // （本番でFirestoreルール未反映のまま実際に発生した不具合と同じ経路）。
          if (snap.hasError) {
            return const Center(
              child: Text('読み込みに失敗しました\nしばらくしてから開き直してください',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
            );
          }
          if (!snap.hasData) {
            return Center(child: CircularProgressIndicator(color: appAccent(context)));
          }
          final photos = snap.data!;
          if (photos.isEmpty) {
            return const Center(
              child: Text('まだ写真がありません\n右上のボタンから追加できます',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: photos.length,
            itemBuilder: (ctx, i) => _buildTile(photos[i]),
          );
        },
      ),
    );
  }

  Widget _buildTile(AlbumPhoto photo) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ImageDetailScreen(imageUrl: photo.imageUrl)),
      ),
      onLongPress: () => _confirmDelete(photo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: photo.imageUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: AppColors.navySurface),
          errorWidget: (_, __, ___) => Container(
            color: AppColors.navySurface,
            child: const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
