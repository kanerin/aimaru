import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import '../models/models.dart';

// ── Googleカレンダー同期 ──────────────────────────────
// auth_service.dart の GoogleSignIn と同じスコープ（email + calendar.events）で
// インスタンス化することで、ログイン時に許可された同一セッションを利用する。
class GoogleCalendarService {
  final _googleSignIn = GoogleSignIn(scopes: [
    'email',
    gcal.CalendarApi.calendarEventsScope,
  ]);

  Future<gcal.CalendarApi?> _api() async {
    var account = _googleSignIn.currentUser;
    account ??= await _googleSignIn.signInSilently();
    if (account == null) return null;

    final client = await _googleSignIn.authenticatedClient();
    if (client == null) return null;

    return gcal.CalendarApi(client);
  }

  // ── AimaruEvent を Google カレンダーに作成・更新 ──
  // 戻り値: Google 側のイベントID（保存して googleCalendarEventId に紐付ける）
  Future<String?> pushEvent(AimaruEvent event) async {
    final api = await _api();
    if (api == null) return null;

    final gEvent = _toGoogleEvent(event);

    try {
      if (event.googleCalendarEventId != null) {
        final updated = await api.events.update(
          gEvent, 'primary', event.googleCalendarEventId!,
        );
        return updated.id;
      } else {
        final created = await api.events.insert(gEvent, 'primary');
        return created.id;
      }
    } catch (_) {
      return null;
    }
  }

  // ── Google カレンダーから削除 ──────────────────────
  Future<void> deleteEvent(String googleEventId) async {
    final api = await _api();
    if (api == null) return;
    try {
      await api.events.delete('primary', googleEventId);
    } catch (_) {
      // すでに削除済み・権限なしなどは無視
    }
  }

  // ── 指定期間のGoogleカレンダーの予定を取得（表示用）──
  Future<List<GCalEventSummary>> fetchEvents({
    required DateTime start,
    required DateTime end,
  }) async {
    final api = await _api();
    if (api == null) return [];

    try {
      final result = await api.events.list(
        'primary',
        timeMin: start.toUtc(),
        timeMax: end.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
        maxResults: 100,
      );

      final items = result.items ?? [];
      return items.where((e) => e.status != 'cancelled').map((e) {
        final startDt = e.start?.dateTime ?? e.start?.date;
        final endDt   = e.end?.dateTime ?? e.end?.date;
        return GCalEventSummary(
          id:     e.id ?? '',
          title:  e.summary ?? '(無題の予定)',
          start:  startDt ?? start,
          end:    endDt ?? (startDt ?? start),
          allDay: e.start?.dateTime == null,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  gcal.Event _toGoogleEvent(AimaruEvent event) {
    final isAllDay = event.recurring || event.type == EventType.anniversary || event.type == EventType.celebrity;

    final gEvent = gcal.Event()
      ..summary = '${event.type.emoji} ${event.title}'
      ..description = event.memo
      ..location = event.location;

    if (isAllDay) {
      final day = DateTime(event.date.year, event.date.month, event.date.day);
      final next = day.add(const Duration(days: 1));
      gEvent.start = gcal.EventDateTime(date: day);
      gEvent.end   = gcal.EventDateTime(date: next);
      if (event.recurring) {
        gEvent.recurrence = ['RRULE:FREQ=YEARLY'];
      }
    } else {
      final end = event.endDate ?? event.date.add(const Duration(hours: 1));
      gEvent.start = gcal.EventDateTime(dateTime: event.date, timeZone: 'Asia/Tokyo');
      gEvent.end   = gcal.EventDateTime(dateTime: end, timeZone: 'Asia/Tokyo');
    }

    return gEvent;
  }
}
