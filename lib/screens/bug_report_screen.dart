import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import '../services/bug_report_service.dart';
import '../services/storage_service.dart';
import '../utils/app_theme.dart';
import '../widgets/section_label.dart';

const kBugReportMaxImages = 5;

// ── バグ報告・機能要望フォーム ─────────────────────────────
// 送信するとサーバー側でGeminiによる厳格な判定にかけられ、有効なバグ報告・
// 機能要望だけがストックされる。ストックされた内容は別の自動化ワークフロー
// （fix-bug-reports.yml）が定期的に読み取り、実装・PR作成・auto-mergeまで行う。
// 送信フォームの下に、自分が過去に送った報告の状況（未着手・対応中・
// 対応済み・見送り）を一覧表示する。
class BugReportScreen extends StatefulWidget {
  // テスト用の注入ポイント。未指定時は本番のBugReportServiceを使う。
  final BugReportService? serviceOverride;
  // テスト用の注入ポイント。未指定時は本番のStorageServiceを使う。
  final StorageService? storageServiceOverride;
  // 自分の報告一覧のテスト用注入ポイント。未指定時はBugReportService経由で
  // 本番のFirestoreストリームを使う。
  final Stream<List<BugReportRecord>>? myReportsStreamOverride;
  // テスト用の注入ポイント。実機のImagePickerを操作せずに「画像が選択済み」
  // の状態から送信フローを検証できるようにする。
  final List<File>? initialImagesForTest;

  const BugReportScreen({
    super.key,
    this.serviceOverride,
    this.storageServiceOverride,
    this.myReportsStreamOverride,
    this.initialImagesForTest,
  });

  @override
  State<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends State<BugReportScreen> {
  // BugReportService() は生成時にFirebaseFunctions.instanceへ触れるため、
  // serviceOverrideを使うテストではFirebase初期化なしに動けるよう
  // 実際に使うときまで生成を遅らせる。
  BugReportService? _serviceInstance;
  BugReportService get _service => widget.serviceOverride ?? (_serviceInstance ??= BugReportService());
  StorageService? _storageServiceInstance;
  StorageService get _storageService =>
      widget.storageServiceOverride ?? (_storageServiceInstance ??= StorageService());

  late final Stream<List<BugReportRecord>> _myReportsStream =
      widget.myReportsStreamOverride ?? _service.watchMyReports();

  final _controller = TextEditingController();
  final _picker = ImagePicker();
  late final List<File> _images = List.from(widget.initialImagesForTest ?? const []);
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remaining = kBugReportMaxImages - _images.length;
    if (remaining <= 0) {
      _showMessage('画像は最大$kBugReportMaxImages件までです');
      return;
    }
    final files = await _picker.pickMultiImage(limit: remaining);
    if (files.isNotEmpty) {
      setState(() => _images.addAll(files.take(remaining).map((f) => File(f.path))));
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final result = await _service.submit(_controller.text);
      if (!mounted) return;
      if (result.accepted) {
        final label = result.classification == BugReportClassification.bug ? 'バグ報告' : '機能要望';
        // 画像の添付は受理された後の追加ステップなので、ここで失敗しても
        // テキストの報告自体は既に受け付けられている。画像だけ失敗した旨を
        // 別メッセージで伝え、送信全体が失敗したかのような誤解を避ける。
        if (_images.isNotEmpty && result.id != null) {
          try {
            final urls = await Future.wait(
              _images.map((f) => _storageService.uploadBugReportImage(result.id!, f)),
            );
            await _service.attachImages(result.id!, urls);
          } catch (_) {
            if (mounted) {
              _showMessage('$labelとして受け付けましたが、画像の添付に失敗しました。ありがとうございます');
            }
            _controller.clear();
            setState(() => _images.clear());
            return;
          }
        }
        _controller.clear();
        setState(() => _images.clear());
        _showMessage('$labelとして受け付けました。ありがとうございます');
      } else {
        _showMessage('バグ報告・機能要望として判定できませんでした。内容を具体的にして再度お試しください');
      }
    } on BugReportSubmissionException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (_) {
      if (mounted) _showMessage(kBugReportUnknownMessage);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('バグ報告・機能要望')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'アプリの不具合や、こんな機能が欲しいという要望を自由に書いてください。'
            '内容はAIが確認した上で、開発チームの対応キューに追加されます。',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.6),
          ),
          const SizedBox(height: 20),
          const SectionLabel('内容'),
          TextField(
            controller: _controller,
            maxLines: 8,
            maxLength: 2000,
            enabled: !_submitting,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: '例: カレンダーで複数日の予定を登録すると、2日目以降が表示されません',
            ),
          ),
          const SizedBox(height: 16),
          const SectionLabel('画像（任意・最大$kBugReportMaxImages件）'),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              ..._images.map((file) => _BugReportImageThumb(
                file: file,
                onRemove: _submitting ? null : () => setState(() => _images.remove(file)),
              )),
              if (_images.length < kBugReportMaxImages)
                GestureDetector(
                  onTap: _submitting ? null : _pickImages,
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.navySurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: const Icon(Icons.add_photo_alternate_outlined, color: AppColors.textMuted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('送信する'),
            ),
          ),
          const SizedBox(height: 28),
          const SectionLabel('送った報告'),
          _MyReportsList(stream: _myReportsStream),
        ],
      ),
    );
  }
}

// 自分が過去に送った報告の一覧。新しい順、状況（未着手・対応中・対応済み・
// 見送り）ごとにバッジで表示する。他人の報告はfirestore.rulesで読めない。
class _MyReportsList extends StatelessWidget {
  final Stream<List<BugReportRecord>> stream;
  const _MyReportsList({required this.stream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BugReportRecord>>(
      stream: stream,
      builder: (context, snap) {
        // hasDataだけを見ていると、権限エラー等でストリームがエラーに
        // 落ちたときに無限ローディングのまま固まる
        // （本番でFirestoreルール未反映のまま実際に発生した不具合と同じ経路）。
        if (snap.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('読み込みに失敗しました\nしばらくしてから開き直してください',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
          );
        }
        if (!snap.hasData) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator(color: appAccent(context))),
          );
        }
        final reports = snap.data!;
        if (reports.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('まだ報告はありません',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          );
        }
        return Column(children: reports.map(_buildTile).toList());
      },
    );
  }

  Widget _buildTile(BugReportRecord report) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  report.classification == 'bug' ? '🐛 バグ報告' : '💡 機能要望',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ),
              _StatusBadge(status: report.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(report.summary, style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary)),
          if (report.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: report.imageUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(report.imageUrls[i], width: 48, height: 48, fit: BoxFit.cover),
                ),
              ),
            ),
          ],
          if (report.status == 'rejected') ...[
            const SizedBox(height: 6),
            Text(
              describeBugReportRejectCategory(report.rejectCategory),
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  static const _labels = {
    'pending': '未着手',
    'in_progress': '対応中',
    'done': '対応済み',
    'rejected': '見送り',
  };

  static const _colors = {
    'pending': AppColors.textMuted,
    'in_progress': Colors.amberAccent,
    'done': Colors.greenAccent,
    'rejected': Colors.redAccent,
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[status] ?? AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _labels[status] ?? status,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _BugReportImageThumb extends StatelessWidget {
  final File file;
  final VoidCallback? onRemove;
  const _BugReportImageThumb({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(file, width: 72, height: 72, fit: BoxFit.cover),
      ),
      if (onRemove != null)
        Positioned(
          top: -6, right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20, height: 20,
              decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
    ],
  );
}
