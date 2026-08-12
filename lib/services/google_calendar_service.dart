import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import '../models/models.dart';

const kGCalNotSignedIn = 'Googleアカウントに接続できていません。設定から連携し直してください';

// ── googleapis が返す日時をアプリで扱う値へ直す ──────────
// EventDateTime.fromJson は DateTime.parse を使うため、オフセット付きRFC3339は
// UTCとして返る。そのまま表示すると9時間ずれる。終日の date は「日付だけ」を
// 表すUTC値で、toLocal() するとタイムゾーンによって前日へずれるため、
// 年月日をそのままローカルの日付として扱う。
// ウィジェットから切り出してあるのは、ここが単体テストの対象になるため。
DateTime? normalizeGCalDateTime(DateTime? value, {required bool isAllDay}) {
  if (value == null) return null;
  if (isAllDay) return DateTime(value.year, value.month, value.day);
  return value.toLocal();
}

// ── 終日予定の end.date（排他的）を求める ────────────────
// アプリ内は「最終日（その日を含む）」で扱い、Googleへ送るときだけ翌日にする。
DateTime allDayEndExclusive({required DateTime start, required DateTime lastDay}) {
  final startDay = DateTime(start.year, start.month, start.day);
  final next = DateTime(lastDay.year, lastDay.month, lastDay.day)
      .add(const Duration(days: 1));
  return next.isAfter(startDay) ? next : startDay.add(const Duration(days: 1));
}

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

    try {
      // 既存のリソースを取ってから必要な箇所だけ差し替えて全体を送る。
      //
      // patch はネストしたオブジェクトをマージするため、時刻指定の予定へ
      // start.date だけを送ると既存の start.dateTime が残って date と同居し、
      // Google が「Invalid start time」(400) を返す。両者は排他なので、
      // 片方を消すには null を明示的に送る必要があるが、googleapis の
      // toJson は null のフィールドを落とすため patch では表現できない。
      // update（全体の置き換え）なら曖昧さが無く、取得した現物を土台にする
      // ことで description / location / recurrence / attendees も保たれる。
      final event = await api.events.get('primary', eventId);
      event.summary = title;

      if (start != null && end != null) {
        if (allDay) {
          // 呼び出し側は end に「最終日（その日を含む）」を渡す
          event.start = gcal.EventDateTime(
              date: DateTime(start.year, start.month, start.day));
          event.end = gcal.EventDateTime(
              date: allDayEndExclusive(start: start, lastDay: end));
        } else {
          event.start = gcal.EventDateTime(dateTime: start.toUtc(), timeZone: 'Asia/Tokyo');
          event.end   = gcal.EventDateTime(dateTime: end.toUtc(), timeZone: 'Asia/Tokyo');
        }
      }

      await api.events.update(event, 'primary', eventId);
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
        final startDt = normalizeGCalDateTime(
            e.start?.dateTime ?? e.start?.date, isAllDay: isAllDay);
        final endDt = normalizeGCalDateTime(
            e.end?.dateTime ?? e.end?.date, isAllDay: isAllDay);
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

  gcal.Event _toGoogleEvent(AimaruEvent event) {
    final gEvent = gcal.Event()
      ..summary = '${event.type.emoji} ${event.title}'
      ..description = event.memo
      ..location = event.location;

    if (event.allDay) {
      final day = DateTime(event.date.year, event.date.month, event.date.day);
      gEvent.start = gcal.EventDateTime(date: day);
      gEvent.end = gcal.EventDateTime(date: allDayEndExclusive(
          start: event.date, lastDay: event.endDate ?? event.date));
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
