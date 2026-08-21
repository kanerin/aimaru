import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/models.dart';
import '../services/event_service.dart';
import '../services/storage_service.dart';
import '../services/google_calendar_service.dart';
import '../services/settings_service.dart';
import '../utils/app_theme.dart';
import '../widgets/event_datetime_fields.dart';
import '../widgets/section_label.dart';

// ── 予定の新規作成・編集フォーム（共用）───────────────
class EventFormScreen extends StatefulWidget {
  final String coupleId;
  final AimaruEvent? existing;   // null なら新規作成
  final DateTime? initialDate;
  // やりたいことリストから「カレンダーに登録」した場合など、新規作成時に
  // タイトルだけ引き継ぎたいケース用。existingがある場合はそちらを優先する。
  final String? initialTitle;

  const EventFormScreen({
    super.key,
    required this.coupleId,
    this.existing,
    this.initialDate,
    this.initialTitle,
  });

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  final _eventService    = EventService();
  final _storageService  = StorageService();
  final _calendarService = GoogleCalendarService();
  final _picker          = ImagePicker();

  late final _titleCtrl    =
      TextEditingController(text: widget.existing?.title ?? widget.initialTitle ?? '');
  late final _locationCtrl = TextEditingController(text: widget.existing?.location ?? '');
  late final _memoCtrl     = TextEditingController(text: widget.existing?.memo ?? '');

  late DateTime  _date       = widget.existing?.date ?? widget.initialDate ?? DateTime.now();
  late DateTime  _endDate    = widget.existing?.endDate ??
      (widget.existing?.date ?? widget.initialDate ?? DateTime.now()).add(const Duration(hours: 1));
  late EventType _type       = widget.existing?.type ?? EventType.date;
  late bool      _recurring  = widget.existing?.recurring ?? false;
  late bool      _allDay     = widget.existing?.allDay ?? false;
  late EventVisibility _visibility = widget.existing?.visibility ?? EventVisibility.shared;
  bool _syncGoogle = false;
  late final List<String> _existingImages = List.from(widget.existing?.imageUrls ?? []);

  final List<File> _newImages = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _syncGoogle = widget.existing!.googleCalendarEventId != null;
    } else {
      // 新規作成時は設定画面のデフォルト値を反映
      SettingsService().getDefaultSyncGoogleCalendar().then((value) {
        if (mounted) setState(() => _syncGoogle = value);
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locationCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final files = await _picker.pickMultiImage();
    if (files.isNotEmpty) {
      setState(() => _newImages.addAll(files.map((f) => File(f.path))));
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('タイトルを入力してください')),
      );
      return;
    }
    setState(() => _saving = true);

    try {
      final location = _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim();
      final memo     = _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim();

      AimaruEvent event;
      if (_isEdit) {
        final e = widget.existing!;
        event = AimaruEvent(
          id: e.id, coupleId: e.coupleId,
          title: _titleCtrl.text.trim(), date: _date, endDate: _endDate,
          type: _type, location: location, memo: memo,
          imageUrls: _existingImages, createdBy: e.createdBy,
          recurring: _recurring, allDay: _allDay,
          googleCalendarEventId: e.googleCalendarEventId,
          visibility: _visibility,
        );
        await _eventService.updateEvent(event);
      } else {
        event = await _eventService.addEvent(widget.coupleId, AimaruEvent(
          id: '', coupleId: widget.coupleId,
          title: _titleCtrl.text.trim(), date: _date, endDate: _endDate,
          type: _type, location: location, memo: memo,
          createdBy: '', recurring: _recurring, allDay: _allDay,
          visibility: _visibility,
        ));
      }

      // 新しい画像をアップロードして紐付け
      if (_newImages.isNotEmpty) {
        final uploaded = await Future.wait(
          _newImages.map((f) => _storageService.uploadEventImage(widget.coupleId, event.id, f)),
        );
        event = event.copyWith(imageUrls: [..._existingImages, ...uploaded]);
        await _eventService.updateEvent(event);
      }

      // Googleカレンダー同期
      if (_syncGoogle) {
        final gId = await _calendarService.pushEvent(event);
        if (gId != null) {
          await _eventService.updateEvent(event.copyWith(googleCalendarEventId: gId));
        }
      } else if (event.googleCalendarEventId != null) {
        // 同期をOFFにした場合はGoogle側からも削除
        await _calendarService.deleteEvent(event.googleCalendarEventId!);
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存に失敗しました。もう一度お試しください')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        title: Text(_isEdit ? '予定を編集' : '新しい予定'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: appAccent(context)),
                  )
                : Text('保存', style: TextStyle(color: appAccentSoft(context), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtrl,
            style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
            decoration: const InputDecoration(hintText: 'タイトル（例: 水族館デート）'),
          ),
          const SizedBox(height: 16),

          const SectionLabel('種類'),
          Wrap(
            spacing: 8,
            children: EventType.values.map((t) => ChoiceChip(
              label: Text('${t.emoji} ${t.label}'),
              selected: _type == t,
              onSelected: (_) => setState(() => _type = t),
              selectedColor: appAccent(context),
              backgroundColor: AppColors.navySurface,
              labelStyle: TextStyle(
                fontSize: 12,
                color: _type == t ? Colors.white : AppColors.textSecond,
              ),
              side: const BorderSide(color: AppColors.hairline),
            )).toList(),
          ),
          const SizedBox(height: 16),

          const SectionLabel('日時'),
          EventDateTimeFields(
            start: _date,
            end: _endDate,
            allDay: _allDay,
            onStartChanged: (v) => setState(() => _date = v),
            onEndChanged: (v) => setState(() => _endDate = v),
            onAllDayChanged: (v) => setState(() => _allDay = v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('毎年繰り返す', style: TextStyle(fontSize: 13, color: AppColors.textSecond)),
              Switch(
                value: _recurring,
                onChanged: (v) => setState(() => _recurring = v),
                activeThumbColor: appAccent(context),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text('自分だけに表示（相手には見えません）',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecond)),
              ),
              Switch(
                value: _visibility == EventVisibility.private,
                onChanged: (v) => setState(
                  () => _visibility = v ? EventVisibility.private : EventVisibility.shared,
                ),
                activeThumbColor: appAccent(context),
              ),
            ],
          ),
          const SizedBox(height: 8),

          const SectionLabel('場所（任意）'),
          TextField(
            controller: _locationCtrl,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: const InputDecoration(hintText: '例: 新江ノ島水族館'),
          ),
          const SizedBox(height: 16),

          const SectionLabel('メモ（任意）'),
          TextField(
            controller: _memoCtrl,
            maxLines: 3,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: const InputDecoration(hintText: 'メモを書く...'),
          ),
          const SizedBox(height: 16),

          const SectionLabel('写真'),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              ..._existingImages.map((url) => _ImageThumb.network(
                url,
                onRemove: () => setState(() => _existingImages.remove(url)),
              )),
              ..._newImages.map((file) => _ImageThumb.file(
                file,
                onRemove: () => setState(() => _newImages.remove(file)),
              )),
              GestureDetector(
                onTap: _pickImages,
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
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.navySurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Googleカレンダーに同期', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                Switch(
                  value: _syncGoogle,
                  onChanged: (v) => setState(() => _syncGoogle = v),
                  activeThumbColor: appAccent(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
        ),
      ),
    );
  }
}

class _ImageThumb extends StatelessWidget {
  final String? url;
  final File? file;
  final VoidCallback onRemove;

  const _ImageThumb.network(String this.url, {required this.onRemove}) : file = null;
  const _ImageThumb.file(File this.file, {required this.onRemove}) : url = null;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: url != null
            ? Image.network(url!, width: 72, height: 72, fit: BoxFit.cover)
            : Image.file(file!, width: 72, height: 72, fit: BoxFit.cover),
      ),
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
