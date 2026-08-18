import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/couple_service.dart';
import 'package:aimaru/widgets/next_meeting_card.dart';

void main() {
  Widget wrap({
    DateTime? initialNextMeetingDate,
    ValueChanged<DateTime?>? onSaved,
    CoupleService? coupleService,
    Future<DateTime?> Function(BuildContext, DateTime?)? pickDateOverride,
    DateTime Function()? nowOverride,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: NextMeetingCard(
            coupleId: 'couple-1',
            initialNextMeetingDate: initialNextMeetingDate,
            onSaved: onSaved,
            coupleServiceOverride: coupleService,
            pickDateOverride: pickDateOverride,
            nowOverride: nowOverride,
          ),
        ),
      );

  testWidgets('未設定のときは案内文と追加ボタンを表示する', (tester) async {
    await tester.pumpWidget(wrap());

    expect(find.textContaining('設定すると、会えるまでの日数'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('未来の日付が設定済みのときは会えるまでの日数を表示する', (tester) async {
    await tester.pumpWidget(wrap(
      initialNextMeetingDate: DateTime(2026, 4, 10),
      nowOverride: () => DateTime(2026, 4, 1),
    ));

    expect(find.textContaining('会えるまであと9日'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('当日のときは「今日、会えます」と表示する', (tester) async {
    await tester.pumpWidget(wrap(
      initialNextMeetingDate: DateTime(2026, 4, 1),
      nowOverride: () => DateTime(2026, 4, 1),
    ));

    expect(find.textContaining('今日、会えます'), findsOneWidget);
  });

  testWidgets('過ぎた日付のときは更新を促すメッセージを表示する', (tester) async {
    await tester.pumpWidget(wrap(
      initialNextMeetingDate: DateTime(2026, 1, 1),
      nowOverride: () => DateTime(2026, 4, 1),
    ));

    expect(find.textContaining('予定の日を過ぎています'), findsOneWidget);
  });

  testWidgets('日付を選ぶとCoupleServiceに保存され、表示が更新される', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('couples').doc('couple-1').set({
      'memberIds': ['user-me'],
      'inviteCode': 'ABC123',
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'anniversary': null,
      'nextMeetingDate': null,
    });
    final coupleService = CoupleService(firestore: db, uid: 'user-me');

    DateTime? savedDate;
    await tester.pumpWidget(wrap(
      coupleService: coupleService,
      nowOverride: () => DateTime(2026, 8, 15),
      pickDateOverride: (context, initial) async => DateTime(2026, 8, 20),
      onSaved: (d) => savedDate = d,
    ));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(savedDate, DateTime(2026, 8, 20));
    expect(find.textContaining('会えるまであと5日'), findsOneWidget);

    final doc = await db.collection('couples').doc('couple-1').get();
    expect((doc.data()?['nextMeetingDate'] as Timestamp).toDate(), DateTime(2026, 8, 20));
  });

  testWidgets('クリアボタンでnextMeetingDateを解除できる', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('couples').doc('couple-1').set({
      'memberIds': ['user-me'],
      'inviteCode': 'ABC123',
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'anniversary': null,
      'nextMeetingDate': Timestamp.fromDate(DateTime(2026, 8, 20)),
    });
    final coupleService = CoupleService(firestore: db, uid: 'user-me');

    DateTime? savedDate = DateTime(2026, 8, 20);
    await tester.pumpWidget(wrap(
      initialNextMeetingDate: DateTime(2026, 8, 20),
      coupleService: coupleService,
      nowOverride: () => DateTime(2026, 8, 15),
      onSaved: (d) => savedDate = d,
    ));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(savedDate, isNull);
    expect(find.textContaining('設定すると、会えるまでの日数'), findsOneWidget);

    final doc = await db.collection('couples').doc('couple-1').get();
    expect(doc.data()?['nextMeetingDate'], isNull);
  });

  testWidgets('保存に失敗しても無限ローディングにならない', (tester) async {
    // couplesドキュメントが存在しない状態でupdate()するとFirestoreはエラーを返す。
    // ここで無限ローディングになるのが実際にtodos_screenで踏んだ不具合と同種のもの。
    await tester.pumpWidget(wrap(
      pickDateOverride: (context, initial) async => DateTime(2026, 1, 1),
      coupleService: CoupleService(firestore: FakeFirebaseFirestore(), uid: 'user-me'),
    ));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('保存に失敗'), findsOneWidget);
  });
}
