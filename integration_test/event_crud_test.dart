// 結合テスト: 予定の追加・表示・削除が、実際のUI操作とFirestore（エミュレータ）
// の両方で成立していることを確認する。
//
// 「画面には出るがFirestoreに保存されていない」「保存はされたが画面に出ない」の
// どちらの壊れ方も検出できるよう、UIとバックエンドの両方を検証する。
// EventServiceにfirestoreを差し込む単体テストでは、実際のFirestoreの
// クエリ・セキュリティルール・ストリーム反映までは通らないため、
// この経路は結合テストでしか守れない。
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/calendar_screen.dart';
import 'package:aimaru/services/event_service.dart';

import 'helpers/e2e.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initE2E();
  });

  // テストごとに新しい匿名ユーザー・新しいカップルを作るので、
  // テスト同士がデータを踏み合うことがない
  setUp(() async {
    await signInAndSeedCouple();
  });

  tearDown(() async {
    await signOutTestUser();
  });

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchEventDocs() async {
    final snap = await FirebaseFirestore.instance
        .collection('couples')
        .doc(testCoupleId)
        .collection('events')
        .get();
    return snap.docs;
  }

  testWidgets('FABから予定を追加すると、カレンダーとFirestoreの両方に反映される',
      (tester) async {
    const title = '水族館デート';

    await pumpScreen(tester, CalendarScreen(coupleId: testCoupleId));

    // ── 追加フォームを開く ──
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    expect(find.text('新しい予定'), findsOneWidget,
        reason: 'FABをタップしても予定作成フォームが開かない');

    // ── タイトルを入れて保存 ──
    await tester.enterText(textFieldWithHint('タイトル'), title);
    await settle(tester);
    await tester.tap(find.text('保存'));
    await settle(tester);

    // ── フォームが閉じてカレンダーに戻る ──
    await pumpUntil(
      tester,
      () => find.text('新しい予定').evaluate().isEmpty,
      reason: '保存後もフォームが閉じない（保存に失敗している可能性）',
    );

    // ── Firestoreに実際に保存されている ──
    await pumpUntilAsync(
      tester,
      () async => (await fetchEventDocs()).isNotEmpty,
      reason: 'Firestoreに予定が保存されていない',
    );

    final docs = await fetchEventDocs();
    expect(docs, hasLength(1));
    final data = docs.first.data();
    expect(data['title'], title);
    expect(data['createdBy'], testUid, reason: '作成者が自分になっていない');
    expect(data['deletedAt'], isNull, reason: '新規作成なのに削除済みになっている');

    // ── カレンダー上にも出る（種類のデフォルトは「デート」なので💕） ──
    await pumpUntil(
      tester,
      () => find.textContaining(title).evaluate().isNotEmpty,
      reason: '追加した予定がカレンダーに表示されない',
    );

    expectNoLayoutOverflow(tester, context: '予定追加フロー');
  });

  testWidgets('タイトルが空のまま保存しようとすると保存されない', (tester) async {
    await pumpScreen(tester, CalendarScreen(coupleId: testCoupleId));

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);

    // タイトルを入れずに保存
    await tester.tap(find.text('保存'));
    await settle(tester);

    expect(find.text('タイトルを入力してください'), findsOneWidget,
        reason: '未入力時のエラーメッセージが出ない');
    expect(find.text('新しい予定'), findsOneWidget,
        reason: '未入力なのにフォームが閉じてしまった');
    expect(await fetchEventDocs(), isEmpty,
        reason: 'タイトル未入力なのにFirestoreへ保存されている');
  });

  testWidgets('予定を詳細画面から削除するとゴミ箱行きになり、カレンダーから消える',
      (tester) async {
    const title = '記念日ディナー';

    // 事前にFirestoreへ予定を入れておく（UIの削除操作だけを検証したいため）
    await EventService().addEvent(
      testCoupleId,
      AimaruEvent(
        id: '',
        coupleId: testCoupleId,
        title: title,
        date: DateTime.now(),
        type: EventType.date,
        createdBy: '',
      ),
    );

    await pumpScreen(tester, CalendarScreen(coupleId: testCoupleId));

    // ── 月表示のセル内チップをタップ → その日の予定リスト表示に切り替わる ──
    await pumpUntil(
      tester,
      () => find.textContaining(title).evaluate().isNotEmpty,
      reason: '既存の予定がカレンダーに表示されない',
    );
    await tester.tap(find.textContaining(title).first);
    await settle(tester);

    // ── リストのカードをタップして詳細画面へ ──
    await tester.tap(find.textContaining(title).first);
    await settle(tester);
    expect(find.text('この予定を削除'), findsOneWidget,
        reason: '予定の詳細画面に遷移していない');

    // ── 削除 → 確認ダイアログ ──
    await tester.tap(find.text('この予定を削除'));
    await settle(tester);
    expect(find.text('この予定を削除しますか？'), findsOneWidget);
    await tester.tap(find.text('削除する'));
    await settle(tester);

    // ── 即時削除ではなくdeletedAtが立つ（30日間は復元できる仕様） ──
    await pumpUntilAsync(
      tester,
      () async {
        final docs = await fetchEventDocs();
        return docs.isNotEmpty && docs.first.data()['deletedAt'] != null;
      },
      reason: '削除操作をしてもdeletedAtが立たない',
    );

    // ── カレンダーの表示からは消えている ──
    await pumpUntil(
      tester,
      () => find.textContaining(title).evaluate().isEmpty,
      reason: '削除したのにカレンダーに残っている',
    );
  });
}
