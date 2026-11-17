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
    Stream<List<ChatMessage>>? pinnedStreamOverride,
  }) =>
      MaterialApp(
        home: ChatScreen(
          coupleId: coupleId,
          isActive: isActive,
          chatServiceOverride: meChatService,
          coupleServiceOverride: meCoupleService,
          currentUidOverride: meUid,
          messagesStreamOverride: messagesStreamOverride,
          pinnedStreamOverride: pinnedStreamOverride,
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

  group('新着メッセージの自動スクロール', () {
    List<ChatMessage> build(int n, {String lastSender = partnerUid}) => [
          for (var i = 0; i < n; i++)
            ChatMessage(
              id: 'm$i',
              coupleId: coupleId,
              text: 'メッセージ$i',
              senderId: i == n - 1 ? lastSender : partnerUid,
              timestamp: DateTime(2026, 1, 1).add(Duration(minutes: i)),
            ),
        ];

    ScrollPosition position(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    testWidgets('過去ログを読んでいる最中に相手の新着が届いても読んでいる位置から動かさない', (tester) async {
      final ctrl = StreamController<List<ChatMessage>>.broadcast();
      addTearDown(ctrl.close);
      await tester.pumpWidget(wrap(isActive: true, messagesStreamOverride: ctrl.stream));
      ctrl.add(build(40));
      await tester.pumpAndSettle();
      expect(position(tester).pixels, position(tester).maxScrollExtent);

      position(tester).jumpTo(0);
      await tester.pump();

      ctrl.add(build(41));
      await tester.pumpAndSettle();
      expect(position(tester).pixels, 0);
    });

    testWidgets('最下部付近を見ているときは新着で最下部へ追従する', (tester) async {
      final ctrl = StreamController<List<ChatMessage>>.broadcast();
      addTearDown(ctrl.close);
      await tester.pumpWidget(wrap(isActive: true, messagesStreamOverride: ctrl.stream));
      ctrl.add(build(40));
      await tester.pumpAndSettle();

      ctrl.add(build(41));
      await tester.pumpAndSettle();
      expect(position(tester).pixels, position(tester).maxScrollExtent);
    });

    testWidgets('自分が送ったメッセージは過去ログを読んでいても最下部へ送る', (tester) async {
      final ctrl = StreamController<List<ChatMessage>>.broadcast();
      addTearDown(ctrl.close);
      await tester.pumpWidget(wrap(isActive: true, messagesStreamOverride: ctrl.stream));
      ctrl.add(build(40));
      await tester.pumpAndSettle();
      position(tester).jumpTo(0);
      await tester.pump();

      ctrl.add(build(41, lastSender: meUid));
      await tester.pumpAndSettle();
      expect(position(tester).pixels, position(tester).maxScrollExtent);
    });
  });

  testWidgets('リアクションが人数付きピルで表示される', (tester) async {
    final message = ChatMessage(
      id: 'msg-1',
      coupleId: coupleId,
      text: 'こんにちは',
      senderId: partnerUid,
      timestamp: DateTime(2026, 1, 1),
      reactions: {meUid: '❤️', partnerUid: '👍'},
    );

    await tester.pumpWidget(
        wrap(isActive: true, messagesStreamOverride: Stream.value([message]).asBroadcastStream()));
    await tester.pump();

    expect(find.text('❤️ 1'), findsOneWidget);
    expect(find.text('👍 1'), findsOneWidget);
  });

  testWidgets('長押しでリアクションピッカーを開き、絵文字をタップすると保存される', (tester) async {
    await meChatService.sendMessage(coupleId, text: 'こんにちは');
    final message = (await meChatService.watchMessages(coupleId).first).single;

    await tester.pumpWidget(
        wrap(isActive: true, messagesStreamOverride: Stream.value([message]).asBroadcastStream()));
    await tester.pump();

    await tester.longPress(find.text('こんにちは'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('❤️').first);
    await tester.pumpAndSettle();

    final doc = await db
        .collection('couples')
        .doc(coupleId)
        .collection('chats')
        .doc(message.id)
        .get();
    expect((doc.data()?['reactions'] as Map)[meUid], '❤️');
  });

  testWidgets('自分がすでに付けたリアクションのピルをタップすると外れる', (tester) async {
    await meChatService.sendMessage(coupleId, text: 'こんにちは');
    final sent = (await meChatService.watchMessages(coupleId).first).single;
    await meChatService.setReaction(coupleId, sent.id, '👍');
    final message = (await meChatService.watchMessages(coupleId).first).single;

    await tester.pumpWidget(
        wrap(isActive: true, messagesStreamOverride: Stream.value([message]).asBroadcastStream()));
    await tester.pump();

    await tester.tap(find.text('👍 1'));
    await tester.pumpAndSettle();

    final doc = await db
        .collection('couples')
        .doc(coupleId)
        .collection('chats')
        .doc(message.id)
        .get();
    expect((doc.data()?['reactions'] as Map).containsKey(meUid), isFalse);
  });

  testWidgets('リアクションの保存に失敗しても例外を出さずSnackBarで知らせる', (tester) async {
    final message = ChatMessage(
      id: 'msg-1',
      coupleId: coupleId,
      text: 'こんにちは',
      senderId: partnerUid,
      timestamp: DateTime(2026, 1, 1),
      reactions: {meUid: '👍'},
    );
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(
        coupleId: coupleId,
        isActive: true,
        chatServiceOverride: _FailingReactionChatService(db),
        coupleServiceOverride: meCoupleService,
        currentUidOverride: meUid,
        messagesStreamOverride: Stream.value([message]).asBroadcastStream(),
      ),
    ));
    await tester.pump();

    // 外す経路（付与済みのピルをタップ）
    await tester.tap(find.text('👍 1'));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('リアクションを付けられませんでした。もう一度お試しください'), findsOneWidget);

    // 付ける経路（長押しピッカー）
    await tester.pump(const Duration(seconds: 5));
    await tester.longPress(find.text('こんにちは'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('❤️').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('リアクションを付けられませんでした。もう一度お試しください'), findsOneWidget);
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
    expect(find.text('読み込みに失敗しました\nしばらくしてから開き直してください'), findsOneWidget);

    await controller.close();
  });

  testWidgets('送信に失敗したら入力した文章を入力欄へ戻してSnackBarで知らせる', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(
        coupleId: coupleId,
        isActive: true,
        chatServiceOverride: _FailingSendChatService(db),
        coupleServiceOverride: meCoupleService,
        currentUidOverride: meUid,
        messagesStreamOverride: Stream.value(<ChatMessage>[]).asBroadcastStream(),
      ),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'おはよう');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();

    expect(find.text('メッセージを送信できませんでした'), findsOneWidget);
    expect(find.text('おはよう'), findsOneWidget);
  });

  testWidgets('画像メッセージの保存ボタンは読み上げラベルを持ち、44px四方のタップ領域がある', (tester) async {
    final message = ChatMessage(
      id: 'img-1',
      coupleId: coupleId,
      text: '',
      imageUrl: 'https://example.com/a.png',
      senderId: partnerUid,
      timestamp: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
        wrap(isActive: true, messagesStreamOverride: Stream.value([message]).asBroadcastStream()));
    await tester.pump();

    final tooltip = find.byTooltip('画像を端末に保存');
    expect(tooltip, findsOneWidget);
    final size = tester.getSize(find.descendant(of: tooltip, matching: find.byType(SizedBox)).first);
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('画像メッセージ本体に「写真を開く」の読み上げラベルが付く', (tester) async {
    final handle = tester.ensureSemantics();
    final message = ChatMessage(
      id: 'img-2',
      coupleId: coupleId,
      text: '',
      imageUrl: 'https://example.com/a.png',
      senderId: partnerUid,
      timestamp: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
        wrap(isActive: true, messagesStreamOverride: Stream.value([message]).asBroadcastStream()));
    await tester.pump();

    expect(find.bySemanticsLabel('写真を開く'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('パートナー情報の読み込みに失敗しても例外を出さず「パートナー」表示のまま使える', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(
        coupleId: coupleId,
        isActive: true,
        chatServiceOverride: meChatService,
        coupleServiceOverride: _FailingCoupleService(db),
        currentUidOverride: meUid,
        messagesStreamOverride: Stream.value(const <ChatMessage>[]).asBroadcastStream(),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('パートナー'), findsOneWidget);
  });

  testWidgets('既読の更新に失敗しても例外を出さず画面を使い続けられる', (tester) async {
    final controller = StreamController<List<ChatMessage>>.broadcast();
    addTearDown(controller.close);
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(
        coupleId: coupleId,
        isActive: true,
        chatServiceOverride: _FailingMarkReadChatService(db),
        coupleServiceOverride: meCoupleService,
        currentUidOverride: meUid,
        messagesStreamOverride: controller.stream,
      ),
    ));
    await tester.pump();

    controller.add(const <ChatMessage>[]);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('非アクティブから戻った瞬間の既読更新が失敗しても例外を出さない', (tester) async {
    Widget build(bool active) => MaterialApp(
          home: ChatScreen(
            coupleId: coupleId,
            isActive: active,
            chatServiceOverride: _FailingMarkReadChatService(db),
            coupleServiceOverride: meCoupleService,
            currentUidOverride: meUid,
            messagesStreamOverride: Stream.value(const <ChatMessage>[]).asBroadcastStream(),
          ),
        );
    await tester.pumpWidget(build(false));
    await tester.pump();
    await tester.pumpWidget(build(true));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
  group('ピン留め', () {
    DocumentReference<Map<String, dynamic>> chatDoc(String id) =>
        db.collection('couples').doc(coupleId).collection('chats').doc(id);

    ChatMessage message(int i, {DateTime? pinnedAt, String sender = partnerUid}) => ChatMessage(
          id: 'm$i',
          coupleId: coupleId,
          text: 'メッセージ$i',
          senderId: sender,
          timestamp: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          pinnedAt: pinnedAt,
        );

    testWidgets('長押しメニューの「ピン留め」で保存され、上部のバナーに出る', (tester) async {
      await meChatService.sendMessage(coupleId, text: '金曜19時に駅前で');
      final sent = (await meChatService.watchMessages(coupleId).first).single;

      await tester.pumpWidget(wrap(
        isActive: true,
        messagesStreamOverride: Stream.value([sent]).asBroadcastStream(),
      ));
      await tester.pump();
      expect(find.byIcon(Icons.push_pin), findsNothing);

      await tester.longPress(find.text('金曜19時に駅前で'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ピン留め'));
      await tester.pumpAndSettle();

      expect((await chatDoc(sent.id).get()).data()!['pinnedBy'], meUid);
      expect(find.textContaining('ピン留めしました'), findsOneWidget);
      // トーク本文とバナーの両方に同じ文言が出る
      expect(find.text('金曜19時に駅前で'), findsNWidgets(2));
    });

    testWidgets('ピン留め済みのメッセージは長押しメニューから外せる', (tester) async {
      await meChatService.sendMessage(coupleId, text: '金曜19時に駅前で');
      final sent = (await meChatService.watchMessages(coupleId).first).single;
      await meChatService.pinMessage(coupleId, sent.id);
      final pinned = (await meChatService.watchMessages(coupleId).first).single;

      await tester.pumpWidget(wrap(
        isActive: true,
        messagesStreamOverride: Stream.value([pinned]).asBroadcastStream(),
      ));
      await tester.pump();

      await tester.longPress(find.text('金曜19時に駅前で').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ピン留めを外す'));
      await tester.pumpAndSettle();

      expect((await chatDoc(sent.id).get()).data()!.containsKey('pinnedAt'), isFalse);
      expect(find.text('ピン留めを外しました'), findsOneWidget);
    });

    testWidgets('バナーには最新のピン留めを出し、一覧には全件を全文で出す', (tester) async {
      const longText = '来週の旅行の持ち物：パスポート、充電器、折りたたみ傘、常備薬、'
          'それから向こうで使う変換プラグイン。忘れないようにここに残しておくね';
      final messages = [
        message(0, pinnedAt: DateTime(2026, 1, 2)),
        ChatMessage(
          id: 'm1',
          coupleId: coupleId,
          text: longText,
          senderId: meUid,
          timestamp: DateTime(2026, 1, 1, 0, 1),
          pinnedAt: DateTime(2026, 1, 3),
        ),
      ];
      await tester.pumpWidget(wrap(
        isActive: true,
        messagesStreamOverride: Stream.value(messages).asBroadcastStream(),
        pinnedStreamOverride: Stream.value([messages[1], messages[0]]),
      ));
      await tester.pump();

      expect(find.text('一覧（2）'), findsOneWidget);

      await tester.tap(find.text('一覧（2）'));
      await tester.pumpAndSettle();

      expect(find.text('ピン留め（2件）'), findsOneWidget);
      expect(find.textContaining('あなた ·'), findsOneWidget);
      expect(find.textContaining('パートナー ·'), findsOneWidget);
      // 一覧では省略せず全文を読める（トーク本文・バナー・一覧で3か所）
      expect(find.text(longText), findsNWidgets(3));
    });

    testWidgets('一覧の「ピン留めを外す」で外れる', (tester) async {
      await meChatService.sendMessage(coupleId, text: '金曜19時に駅前で');
      final sent = (await meChatService.watchMessages(coupleId).first).single;
      await partnerChatService.pinMessage(coupleId, sent.id);

      await tester.pumpWidget(wrap(isActive: true));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('一覧'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('ピン留めを外す'));
      await tester.pumpAndSettle();

      expect((await chatDoc(sent.id).get()).data()!.containsKey('pinnedAt'), isFalse);
      expect(find.text('一覧'), findsNothing);
    });

    testWidgets('バナーをタップすると、ピン留めしたメッセージの位置までスクロールする', (tester) async {
      final messages = [
        for (var i = 0; i < 40; i++) message(i, pinnedAt: i == 2 ? DateTime(2026, 1, 2) : null),
      ];
      await tester.pumpWidget(wrap(
        isActive: true,
        messagesStreamOverride: Stream.value(messages).asBroadcastStream(),
        pinnedStreamOverride: Stream.value([messages[2]]),
      ));
      await tester.pumpAndSettle();
      // 初回は最下部を表示しているので、古いメッセージ2は作られていない
      expect(find.text('メッセージ2'), findsOneWidget); // バナーのみ

      await tester.tap(find.text('メッセージ2'));
      await tester.pumpAndSettle();

      expect(find.text('メッセージ2'), findsNWidgets(2)); // バナーとトーク本文
      await tester.pump(const Duration(seconds: 3)); // 目立たせる表示が消えるまで進める
    });

    testWidgets('トークに読み込まれていない古いピン留めは、バナーのタップで一覧を開く', (tester) async {
      final old = message(-500, pinnedAt: DateTime(2026, 1, 2));
      await tester.pumpWidget(wrap(
        isActive: true,
        messagesStreamOverride: Stream.value([message(0)]).asBroadcastStream(),
        pinnedStreamOverride: Stream.value([old]),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('メッセージ-500'));
      await tester.pumpAndSettle();

      expect(find.text('ピン留め（1件）'), findsOneWidget);
    });

    testWidgets('ピン留めの読み込みに失敗してもトークはそのまま使える', (tester) async {
      await tester.pumpWidget(wrap(
        isActive: true,
        messagesStreamOverride: Stream.value([message(0)]).asBroadcastStream(),
        pinnedStreamOverride: Stream.error(Exception('PERMISSION_DENIED')),
      ));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('メッセージ0'), findsOneWidget);
      expect(find.byIcon(Icons.push_pin), findsNothing);
    });

    testWidgets('ピン留めの保存に失敗しても例外を出さずSnackBarで知らせる', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ChatScreen(
          coupleId: coupleId,
          isActive: true,
          chatServiceOverride: _FailingPinChatService(db),
          coupleServiceOverride: meCoupleService,
          currentUidOverride: meUid,
          messagesStreamOverride: Stream.value([message(0)]).asBroadcastStream(),
          pinnedStreamOverride: Stream.value(const <ChatMessage>[]),
        ),
      ));
      await tester.pump();

      await tester.longPress(find.text('メッセージ0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ピン留め'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('ピン留めできませんでした。もう一度お試しください'), findsOneWidget);
    });
  });
}

class _FailingPinChatService extends ChatService {
  _FailingPinChatService(FirebaseFirestore db) : super(firestore: db, uid: 'me');

  @override
  Future<void> pinMessage(String coupleId, String messageId) async {
    throw Exception('permission-denied');
  }
}

class _FailingMarkReadChatService extends ChatService {
  _FailingMarkReadChatService(FirebaseFirestore db) : super(firestore: db, uid: 'me');

  @override
  Future<void> markAsRead(String coupleId) async {
    throw Exception('permission-denied');
  }
}

class _FailingCoupleService extends CoupleService {
  _FailingCoupleService(FirebaseFirestore db) : super(firestore: db, uid: 'me');

  @override
  Future<CoupleModel?> getMyCouple() async {
    throw Exception('permission-denied');
  }
}

class _FailingSendChatService extends ChatService {
  _FailingSendChatService(FirebaseFirestore db) : super(firestore: db, uid: 'me');

  @override
  Future<void> sendMessage(String coupleId, {String? text, String? imageUrl}) async {
    throw Exception('permission-denied');
  }
}

class _FailingReactionChatService extends ChatService {
  _FailingReactionChatService(FirebaseFirestore db) : super(firestore: db, uid: 'me');

  @override
  Future<void> setReaction(String coupleId, String messageId, String emoji) async {
    throw Exception('permission-denied');
  }

  @override
  Future<void> removeReaction(String coupleId, String messageId) async {
    throw Exception('permission-denied');
  }
}
