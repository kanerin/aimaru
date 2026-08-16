// ── 「n年前の今日」の振り返り ─────────────────────────────
// サービス終了したPairyなどが持っていた「思い出を振り返る」体験を、
// 新しいFirestoreクエリやCloud Functionsを増やさずクライアント側だけで
// 再現する。予定一覧（既にMemoriesScreenが購読しているストリーム）から
// 月日が今日と一致する過去の予定を拾うだけの純粋関数。
//
// collectionGroupクエリに新しい条件を足すとqueryScope: COLLECTION_GROUPの
// 索引が別途要ることがあり、release-stg.ymlには索引をデプロイする経路が
// 無い（docs/open-issues.mdの課題8参照）。ここでは既存のイベント購読を
// そのまま使うことでその問題を避けている。

import '../models/models.dart';

class OnThisDayMemory {
  final AimaruEvent event;
  final int yearsAgo;
  const OnThisDayMemory({required this.event, required this.yearsAgo});
}

/// [events] のうち、月日が [today] と一致する過去の予定を、古い年→新しい年
/// （＝yearsAgoが大きい順）ではなく、直近の年から順に返す。
/// ゴミ箱（論理削除済み）の予定は対象から外す。
List<OnThisDayMemory> findOnThisDayMemories(List<AimaruEvent> events, DateTime today) {
  final memories = <OnThisDayMemory>[
    for (final e in events)
      if (e.deletedAt == null &&
          e.date.year < today.year &&
          e.date.month == today.month &&
          e.date.day == today.day)
        OnThisDayMemory(event: e, yearsAgo: today.year - e.date.year),
  ];
  memories.sort((a, b) => a.yearsAgo.compareTo(b.yearsAgo));
  return memories;
}
