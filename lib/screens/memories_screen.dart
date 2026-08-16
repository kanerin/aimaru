import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/event_service.dart';
import '../services/image_save_service.dart';
import '../utils/app_theme.dart';
import '../utils/on_this_day_finder.dart';
import 'event_detail_screen.dart';

class _Photo {
  final String url;
  final AimaruEvent event;
  _Photo(this.url, this.event);
}

// ── 思い出（予定に添付された画像の一覧 + n年前の今日の振り返り）─────
class MemoriesScreen extends StatefulWidget {
  final String coupleId;
  // テスト用の注入ポイント。未指定時は本番のEventService/現在時刻を使う。
  final Stream<Map<DateTime, List<AimaruEvent>>>? eventsStreamOverride;
  final DateTime Function()? nowOverride;
  const MemoriesScreen({
    super.key,
    required this.coupleId,
    this.eventsStreamOverride,
    this.nowOverride,
  });

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  EventService? _eventServiceInstance;
  EventService get _eventService => _eventServiceInstance ??= EventService();
  EventType? _filter;

  // build()の中で作ると、フィルタ切替などの再ビルドのたびに購読し直して
  // 一覧が一瞬空になる。ストリームは1本だけ作って使い回す。
  late final Stream<Map<DateTime, List<AimaruEvent>>> _eventsStream =
      widget.eventsStreamOverride ?? _eventService.watchEventsAsMap(widget.coupleId);

  DateTime get _now => (widget.nowOverride ?? DateTime.now)();

  Future<void> _openDetail(AimaruEvent event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EventDetailScreen(event: event, coupleId: widget.coupleId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('思い出')),
      body: StreamBuilder<Map<DateTime, List<AimaruEvent>>>(
        stream: _eventsStream,
        builder: (context, snap) {
          // hasDataだけを見ていると、権限エラー等でストリームがエラーに
          // 落ちたときに無限ローディングのまま固まる
          // （本番でFirestoreルール未反映のまま実際に発生した）。
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

          final eventsMap = snap.data!;
          final allEvents = eventsMap.values.expand((list) => list).toList();
          final onThisDay = findOnThisDayMemories(allEvents, _now);

          final withPhotos = allEvents
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
              if (onThisDay.isNotEmpty) _OnThisDaySection(memories: onThisDay, onTap: _openDetail),
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

// ── n年前の今日の振り返り ─────────────────────────────
// サービス終了したPairyなどが持っていた「思い出を振り返る」体験を、
// カレンダー機能中心のTimeTreeには無い形で提供する。
class _OnThisDaySection extends StatelessWidget {
  final List<OnThisDayMemory> memories;
  final ValueChanged<AimaruEvent> onTap;
  const _OnThisDaySection({required this.memories, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📅 今日の思い出', style: TextStyle(
            fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
          )),
          const SizedBox(height: 8),
          ...memories.map((m) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => onTap(m.event),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.navySurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(children: [
                  if (m.event.imageUrls.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: m.event.imageUrls.first,
                        width: 44, height: 44, fit: BoxFit.cover,
                        memCacheWidth: 88,
                        placeholder: (_, __) => Container(width: 44, height: 44, color: AppColors.navyCard),
                      ),
                    )
                  else
                    Container(
                      width: 44, height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.navyCard, borderRadius: BorderRadius.circular(8)),
                      child: Text(m.event.type.emoji, style: const TextStyle(fontSize: 18)),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m.yearsAgo}年前の今日', style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, color: appAccent(context),
                        )),
                        const SizedBox(height: 2),
                        Text(m.event.title, style: const TextStyle(
                          fontSize: 13.5, color: AppColors.textPrimary,
                        )),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
                ]),
              ),
            ),
          )),
        ],
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
