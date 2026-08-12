import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import '../models/models.dart';

const kGCalNotSignedIn = 'Googleアカウントに接続できていません。設定から連携し直してください';

// ── Googleカレンダーへの書き込み結果 ──────────────────
// 失敗理由を画面まで運ぶ。握り潰すと「消えないのに成功に見える」状態になる。
class GCalResult {
  final bool ok;
  final String? error;

  const GCalResult.success() : ok = true, error = null;
  const GCalResult.failure(this.error) : ok = false;
}

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

  // ── Googleカレンダー上の既存の予定を直接更新（GCalEventSummary起点）──
  // AimaruEventを介さず、このアプリのカレンダー画面から直接タイトル/日時を
  // 編集する場合に使う。戻り値は成功可否。
  // start/end を省略すると日時は触らない。タイトルだけ変えたいときに日時を
  // 送り直すと、終日/時刻指定の取り違えで元の予定を壊しうるため。
  Future<GCalResult> updateGoogleEvent({
    required String eventId,
    required String title,
    DateTime? start,
    DateTime? end,
    bool allDay = false,
  }) async {
    final api = await _api();
    if (api == null) return const GCalResult.failure(kGCalNotSignedIn);

    final gEvent = gcal.Event()..summary = title;
    if (start == null || end == null) {
      // 日時は据え置き
    } else if (allDay) {
      // 呼び出し側は end に「最終日（その日を含む）」を渡す。Google の end.date は
      // 排他的なので翌日へ送る。
      final startDay = DateTime(start.year, start.month, start.day);
      var endDay     = DateTime(end.year, end.month, end.day).add(const Duration(days: 1));
      if (!endDay.isAfter(startDay)) endDay = startDay.add(const Duration(days: 1));
      gEvent.start = gcal.EventDateTime(date: startDay);
      gEvent.end   = gcal.EventDateTime(date: endDay);
    } else {
      gEvent.start = gcal.EventDateTime(dateTime: start.toUtc(), timeZone: 'Asia/Tokyo');
      gEvent.end   = gcal.EventDateTime(dateTime: end.toUtc(), timeZone: 'Asia/Tokyo');
    }

    try {
      // events.update はリソース全体の置き換えなので、ここで送っていない
      // description / location / recurrence / attendees が消える。
      // 送ったフィールドだけを変える patch を使う。
      await api.events.patch(gEvent, 'primary', eventId);
      return const GCalResult.success();
    } catch (e) {
      return GCalResult.failure(_describe(e));
    }
  }

  // ── Google カレンダーから削除 ──────────────────────
  // 失敗を黙って握り潰すと、消えていないのに成功したように見えるため理由を返す。
  Future<GCalResult> deleteEvent(String googleEventId) async {
    final api = await _api();
    if (api == null) return const GCalResult.failure(kGCalNotSignedIn);
    try {
      await api.events.delete('primary', googleEventId);
      return const GCalResult.success();
    } catch (e) {
      // 相手が主催の予定や、すでに消えている予定はここに来る
      if (_isAlreadyGone(e)) return const GCalResult.success();
      return GCalResult.failure(_describe(e));
    }
  }

  bool _isAlreadyGone(Object error) {
    final s = error.toString();
    return s.contains('404') || s.contains('410') || s.contains('notFound') ||
        s.contains('deleted');
  }

  String _describe(Object error) {
    final s = error.toString();
    if (s.contains('403') || s.contains('forbidden') || s.contains('insufficient')) {
      return 'この予定を変更する権限がありません（主催者が別の人の可能性があります）';
    }
    if (s.contains('401') || s.contains('invalid_grant') || s.contains('unauthenticated')) {
      return 'Googleの認証が切れています。設定から連携し直してください';
    }
    // 原因を絞り込めないときは、そのまま見せたほうが次の手を打てる
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
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
        final isAllDay = e.start?.dateTime == null;
        final startDt = _normalize(e.start?.dateTime ?? e.start?.date, isAllDay);
        final endDt   = _normalize(e.end?.dateTime ?? e.end?.date, isAllDay);
        return GCalEventSummary(
          id:     e.id ?? '',
          title:  e.summary ?? '(無題の予定)',
          start:  startDt ?? start,
          end:    endDt ?? (startDt ?? start),
          allDay: isAllDay,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // googleapis が返す dateTime は RFC3339 をパースしたUTC値なので、そのまま
  // 表示すると9時間ずれる。終日予定の date は「日付だけ」を表すUTC値で、
  // toLocal() するとタイムゾーンによって前日へずれるため年月日をそのまま使う。
  static DateTime? _normalize(DateTime? value, bool isAllDay) {
    if (value == null) return null;
    if (isAllDay) return DateTime(value.year, value.month, value.day);
    return value.toLocal();
  }

  gcal.Event _toGoogleEvent(AimaruEvent event) {
    final gEvent = gcal.Event()
      ..summary = '${event.type.emoji} ${event.title}'
      ..description = event.memo
      ..location = event.location;

    if (event.allDay) {
      final day = DateTime(event.date.year, event.date.month, event.date.day);
      // 終日の end.date は排他的なので、終了日の翌日を送る
      final lastDay = event.endDate ?? event.date;
      var next = DateTime(lastDay.year, lastDay.month, lastDay.day)
          .add(const Duration(days: 1));
      if (!next.isAfter(day)) next = day.add(const Duration(days: 1));
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
