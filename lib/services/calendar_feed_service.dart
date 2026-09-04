import 'package:cloud_functions/cloud_functions.dart';

// ── 外部カレンダー連携（iCalendar購読フィード）─────────────────
// TimeTreeは「設定 → カレンダー情報 → iCal URLをコピー」で、Googleカレンダーや
// Appleカレンダーへ読み取り専用でURL購読できるが、AIMARUはこれまでICSの取り込み
// （IcsImportService）しか持たず、外へ公開する方向（export/購読）が無かった
// （2026年9月時点の競合調査）。
//
// URLの発行・トークンの保管はサーバー側（functions/src/index.ts の
// getCalendarFeedUrl / regenerateCalendarFeedUrl）に寄せている。クライアントは
// 応答のURLをそのまま表示するだけで、トークン自体には触れない。
class CalendarFeedService {
  // 本番はFirebase Callable Functions（getCalendarFeedUrl / regenerateCalendarFeedUrl）
  // を呼ぶ。テストからは実際のFirebase呼び出しをせずに応答を差し込めるようにしてある。
  final Future<Map<String, dynamic>> Function() _invokeGet;
  final Future<Map<String, dynamic>> Function() _invokeRegenerate;

  CalendarFeedService({
    Future<Map<String, dynamic>> Function()? invokeGet,
    Future<Map<String, dynamic>> Function()? invokeRegenerate,
  })  : _invokeGet = invokeGet ?? (() => _invoke('getCalendarFeedUrl')),
        _invokeRegenerate = invokeRegenerate ?? (() => _invoke('regenerateCalendarFeedUrl'));

  static Future<Map<String, dynamic>> _invoke(String name) async {
    final callable = FirebaseFunctions.instance.httpsCallable(name);
    final result = await callable.call<Map<String, dynamic>>();
    return Map<String, dynamic>.from(result.data as Map);
  }

  // 既存のトークンがあれば使い回し、無ければ発行してURLを返す。
  Future<String> fetchUrl() async {
    final data = await _invokeGet();
    return data['url'] as String;
  }

  // 今のリンクを無効化し、新しいトークンでURLを発行し直す。リンクを誤って
  // 共有してしまった場合の取り消し手段。
  Future<String> regenerateUrl() async {
    final data = await _invokeRegenerate();
    return data['url'] as String;
  }
}
