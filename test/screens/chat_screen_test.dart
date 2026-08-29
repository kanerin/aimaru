import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aimaru/models/models.dart';
import 'package:aimaru/screens/chat_screen.dart';
import 'package:aimaru/services/chat_service.dart';
import 'package:aimaru/services/couple_service.dart';

// トーク画面はホーム画面のIndexedStackで常時マウントされたままになる
// （main.dart参照）。そのため「メッセージが更新されたら既読にする」を
// isActiveでガードせずに実装すると、パートナーが別のタブを見ている間に
// 届いたメッセージまで既読扱いになってしまう不具合があった。
void main() {
  const coupleId = 'couple-1';
  const meUid = 'me';
  const partnerUid = 'partner';

  late FakeFirebaseFirestore db;
  late ChatService meChatService;
  late ChatService partnerChatService;
  late CoupleService meCoupleService;

  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  Future<DocumentSnapshot<Map<String, dynamic>>> myReadStatusDoc() => db
      .collection('couples')
      .doc(coupleId)
      .collection('chatReadStatus')
      .doc(meUid)
      .get();

  setUp(() async {
    db = FakeFirebaseFirestore();
    meChatService = ChatService(firestore: db, uid: meUid);
    partnerChatService = ChatService(firestore: db, uid: partnerUid);
    meCoupleService = CoupleService(firestore: db, uid: meUid);

    await db.collection('couples').doc(coupleId).set({
      'memberIds': [meUid, partnerUid],
      'inviteCode': 'ABCDEF',
      'createdAt': Timestamp.now(),
      'anniversary': null,
    });
  });

  Widget wrap({
    required bool isActive,
    Stream<List<ChatMessage>>? messagesStreamOverride,
  }) =>
      MaterialApp(
        home: ChatScreen(
          coupleId: coupleId,
          isActive: isActive,
          chatServiceOverride: meChatService,
          coupleServiceOverride: meCoupleService,
          currentUidOverride: meUid,
          messagesStreamOverride: messagesStreamOverride,
        ),
      );

  testWidgets('非アクティブなタブでは新着メッセージが来ても既読にしない', (tester) async {
    await tester.pumpWidget(wrap(isActive: false));
    await tester.pump();

    await partnerChatService.sendMessage(coupleId, text: 'こんにちは');
    await tester.pump();
    await tester.pump();

    expect((await myReadStatusDoc()).exists, isFalse);
  });

  testWidgets('アクティブなタブで新着メッセージが来たら既読にする', (tester) async {
    await tester.pumpWidget(wrap(isActive: true));
    await tester.pump();

    await partnerChatService.sendMessage(coupleId, text: 'こんにちは');
    await tester.pump();
    await tester.pump();

    expect((await myReadStatusDoc()).exists, isTrue);
  });

  testWidgets('非アクティブから戻ってきた瞬間に既読にする', (tester) async {
    await tester.pumpWidget(wrap(isActive: false));
    await tester.pump();

    await partnerChatService.sendMessage(coupleId, text: '見てないうちに届いたメッセージ');
    await tester.pump();
    await tester.pump();
    expect((await myReadStatusDoc()).exists, isFalse);

    // 同じ位置に同じ型のウィジェットを再度pumpすると、Stateを保ったまま
    // didUpdateWidgetが呼ばれる（IndexedStackでタブを切り替えたときと同じ状況）。
    await tester.pumpWidget(wrap(isActive: true));
    await tester.pump();
    await tester.pump();

    expect((await myReadStatusDoc()).exists, isTrue);
  });

  testWidgets('メッセージストリームがエラーになったら無限ローディングではなくエラー表示にする', (tester) async {
    // _messagesStreamは既読マーカーの購読とStreamBuilderの両方から
    // listenされるため、本番のFirestoreの.snapshots()と同様broadcastにする。
    final controller = StreamController<List<ChatMessage>>.broadcast();
    await tester.pumpWidget(wrap(isActive: true, messagesStreamOverride: controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    controller.addError(Exception('PERMISSION_DENIED'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('メッセージの読み込みに失敗しました'), findsOneWidget);

    await controller.close();
  });
}
