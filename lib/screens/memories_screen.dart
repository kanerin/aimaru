import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/event_service.dart';
import '../services/image_save_service.dart';
import '../utils/app_theme.dart';

class _Photo {
  final String url;
  final AimaruEvent event;
  _Photo(this.url, this.event);
}

// ── 思い出（予定に添付された画像の一覧）───────────────
class MemoriesScreen extends StatefulWidget {
  final String coupleId;
  const MemoriesScreen({super.key, required this.coupleId});

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  final _eventService = EventService();
  EventType? _filter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('思い出')),
      body: StreamBuilder<Map<DateTime, List<AimaruEvent>>>(
        stream: _eventService.watchEventsAsMap(widget.coupleId),
        builder: (context, snap) {
          final eventsMap = snap.data ?? {};
          final withPhotos = eventsMap.values
              .expand((list) => list)
              .where((e) => e.imageUrls.isNotEmpty)
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));

          final filtered = _filter == null
              ? withPhotos
              : withPhotos.where((e) => e.type == _filter).toList();

          final photos = <_Photo>[
            for (final e in filtered)
              for (final url in e.imageUrls) _Photo(url, e),
          ];

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('すべての写真', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    Text('${photos.length}枚', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _FilterChip(label: 'すべて', selected: _filter == null, onTap: () => setState(() => _filter = null)),
                      const SizedBox(width: 8),
                      ...EventType.values.map((t) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _FilterChip(
                          label: '${t.emoji} ${t.label}',
                          selected: _filter == t,
                          onTap: () => setState(() => _filter = t),
                        ),
                      )),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: photos.isEmpty
                    ? const Center(
                        child: Text('まだ写真がありません\n予定に写真を追加してみましょう',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.6)),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6,
                        ),
                        itemCount: photos.length,
                        itemBuilder: (ctx, i) {
                          final p = photos[i];
                          return GestureDetector(
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => _PhotoViewer(photo: p),
                            )),
                            child: Hero(
                              tag: p.url,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Stack(fit: StackFit.expand, children: [
                                  CachedNetworkImage(
                                    imageUrl: p.url, fit: BoxFit.cover,
                                    memCacheWidth: 240, // グリッドのサムネイル用に抑える
                                    placeholder: (_, __) => Container(color: AppColors.navySurface),
                                  ),
                                  Positioned(
                                    top: 4, left: 4,
                                    child: Text(p.event.type.emoji, style: const TextStyle(fontSize: 12)),
                                  ),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? appAccent(context) : AppColors.navySurface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: selected ? Colors.transparent : AppColors.hairline),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 12, color: selected ? Colors.white : AppColors.textSecond, fontWeight: FontWeight.w600,
      )),
    ),
  );
}

class _PhotoViewer extends StatefulWidget {
  final _Photo photo;
  const _PhotoViewer({required this.photo});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  final _imageSaveService = ImageSaveService();
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await _imageSaveService.saveFromUrl(widget.photo.url);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '画像を保存しました' : '保存に失敗しました'),
        backgroundColor: ok ? AppColors.success : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    return Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      elevation: 0,
      title: Text(photo.event.title, style: const TextStyle(fontSize: 14)),
      actions: [
        IconButton(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.download_outlined),
        ),
      ],
    ),
    body: Column(children: [
      Expanded(
        child: Center(
          child: Hero(
            tag: photo.url,
            child: InteractiveViewer(
              child: CachedNetworkImage(imageUrl: photo.url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          DateFormat('yyyy年M月d日（E）', 'ja').format(photo.event.date),
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ),
    ]),
  );
  }
}
