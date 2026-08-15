import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/couple_service.dart';
import 'package:aimaru/widgets/anniversary_card.dart';

void main() {
  Widget wrap({
    DateTime? initialAnniversary,
    ValueChanged<DateTime>? onSaved,
    CoupleService? coupleService,
    Future<DateTime?> Function(BuildContext, DateTime?)? pickDateOverride,
    DateTime Function()? nowOverride,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: AnniversaryCard(
            coupleId: 'couple-1',
            initialAnniversary: initialAnniversary,
            onSaved: onSaved,
            coupleServiceOverride: coupleService,
            pickDateOverride: pickDateOverride,
            nowOverride: nowOverride,
          ),
        ),
      );

  testWidgets('未設定のときは案内文と追加ボタンを表示する', (tester) async {
    await tester.pumpWidget(wrap());

    expect(find.textContaining('設定すると、経過日数'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('設定済みのときは経過日数・節目・周年を表示する', (tester) async {
    await tester.pumpWidget(wrap(
      initialAnniversary: DateTime(2026, 1, 1),
      nowOverride: () => DateTime(2026, 4, 10),
    ));

    expect(find.textContaining('付き合って100日目'), findsOneWidget);
    expect(find.textContaining('今日は100日記念日です'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });

  testWidgets('日付を選ぶとCoupleServiceに保存され、表示が更新される', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('couples').doc('couple-1').set({
      'memberIds': ['user-me'],
      'inviteCode': 'ABC123',
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'anniversary': null,
    });
    final coupleService = CoupleService(firestore: db, uid: 'user-me');

    DateTime? savedDate;
    await tester.pumpWidget(wrap(
      coupleService: coupleService,
      nowOverride: () => DateTime(2026, 8, 15),
      pickDateOverride: (context, initial) async => DateTime(2026, 8, 1),
      onSaved: (d) => savedDate = d,
    ));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(savedDate, DateTime(2026, 8, 1));
    expect(find.textContaining('付き合って15日目'), findsOneWidget);

    final doc = await db.collection('couples').doc('couple-1').get();
    expect((doc.data()?['anniversary'] as Timestamp).toDate(), DateTime(2026, 8, 1));
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
