import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aimaru/services/couple_service.dart';

// ペアリングの分岐を、Firebaseに接続せずインメモリのFirestoreで検証する。
//
// ペアリングはこのアプリの一番細い導線で、ここが壊れると
// 「相手が参加できない = アプリの価値がゼロ」になるため厚めに見る。
void main() {
  late FakeFirebaseFirestore db;

  const meUid      = 'user-me';
  const partnerUid = 'user-partner';
  const otherUid   = 'user-other';

  CoupleService serviceFor(String uid) =>
      CoupleService(firestore: db, uid: uid);

  // 招待コード付きのペアを1件作る
  Future<String> seedCouple({
    required String code,
    required List<String> memberIds,
  }) async {
    final ref = db.collection('couples').doc();
    await ref.set({
      'memberIds': memberIds,
      'inviteCode': code,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'anniversary': null,
    });
    return ref.id;
  }

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  group('招待コードの生成', () {
    test('6桁で紛らわしい文字を含まない', () async {
      const forbidden = {'I', 'O', '0', '1'};

      for (var i = 0; i < 200; i++) {
        db = FakeFirebaseFirestore();
        final code = await serviceFor(meUid).createInviteCode();

        expect(code, hasLength(6));
        expect(
          code.split('').where(forbidden.contains),
          isEmpty,
          reason: '紛らわしい文字が混ざっている: $code',
        );
      }
    });

    test('連番にならず、連続生成しても重複しない', () async {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final codes = <String>[];

      for (var i = 0; i < 200; i++) {
        db = FakeFirebaseFirestore();
        codes.add(await serviceFor(meUid).createInviteCode());
      }

      // 以前の実装は現在時刻＋インデックスで文字を選んでいたため、
      // 6文字が文字表の連番（例: ABCDEF）になっていた。
      for (final code in codes) {
        final isSequential = List.generate(5, (i) {
          final cur  = chars.indexOf(code[i]);
          final next = chars.indexOf(code[i + 1]);
          return next == (cur + 1) % chars.length;
        }).every((e) => e);

        expect(isSequential, isFalse, reason: 'コードが連番になっている: $code');
      }

      // 32^6 通りあるので、200件で重複が出るなら乱数が効いていない
      expect(codes.toSet(), hasLength(codes.length));
    });

    test('すでにペアがあるなら既存のコードを返す', () async {
      final service = serviceFor(meUid);
      final first   = await service.createInviteCode();
      final second  = await service.createInviteCode();

      expect(second, first);
      final snap = await db.collection('couples').get();
      expect(snap.docs, hasLength(1), reason: 'ペアが二重に作られている');
    });
  });

  group('招待コードによる参加', () {
    test('1名のペアには参加でき、メンバーが2名になる', () async {
      await seedCouple(code: 'A3K9PZ', memberIds: [partnerUid]);

      final couple = await serviceFor(meUid).joinWithCode('A3K9PZ');

      expect(couple, isNotNull);
      expect(couple!.memberIds, containsAll([partnerUid, meUid]));
      expect(couple.memberIds, hasLength(2));
    });

    test('小文字・前後空白付きのコードでも参加できる', () async {
      await seedCouple(code: 'A3K9PZ', memberIds: [partnerUid]);

      final couple = await serviceFor(meUid).joinWithCode('  a3k9pz  ');

      expect(couple, isNotNull);
      expect(couple!.memberIds, hasLength(2));
    });

    test('存在しないコードでは参加できない', () async {
      await seedCouple(code: 'A3K9PZ', memberIds: [partnerUid]);

      final couple = await serviceFor(meUid).joinWithCode('ZZZZZZ');

      expect(couple, isNull);
    });

    test('すでに2名いるペアには参加できない', () async {
      final id = await seedCouple(
        code: 'A3K9PZ',
        memberIds: [partnerUid, otherUid],
      );

      final couple = await serviceFor(meUid).joinWithCode('A3K9PZ');

      expect(couple, isNull);
      final doc = await db.collection('couples').doc(id).get();
      expect(doc.data()!['memberIds'], hasLength(2), reason: '3人目が入っている');
    });

    test('自分が作ったペアには参加できない', () async {
      final id = await seedCouple(code: 'A3K9PZ', memberIds: [meUid]);

      final couple = await serviceFor(meUid).joinWithCode('A3K9PZ');

      expect(couple, isNull);
      final doc = await db.collection('couples').doc(id).get();
      expect(doc.data()!['memberIds'], hasLength(1), reason: '自分が二重登録された');
    });
  });

  group('ペアの参照', () {
    test('自分が属するペアだけを返す', () async {
      await seedCouple(code: 'AAAAAA', memberIds: [partnerUid, otherUid]);
      final mine = await seedCouple(code: 'BBBBBB', memberIds: [meUid]);

      final couple = await serviceFor(meUid).getMyCouple();

      expect(couple, isNotNull);
      expect(couple!.id, mine);
    });

    test('どのペアにも属していなければnullを返す', () async {
      await seedCouple(code: 'AAAAAA', memberIds: [partnerUid, otherUid]);

      expect(await serviceFor(meUid).getMyCouple(), isNull);
    });

    test('パートナーの表示名を取得できる', () async {
      final id = await seedCouple(
        code: 'A3K9PZ',
        memberIds: [meUid, partnerUid],
      );
      await db.collection('users').doc(partnerUid).set({'displayName': 'あいこ'});

      final service = serviceFor(meUid);
      final couple  = await service.getMyCouple();
      final name    = await service.getPartnerName(couple!);

      expect(name, 'あいこ');
      expect(id, couple.id);
    });

    test('相手がまだいなければパートナー名はnull', () async {
      await seedCouple(code: 'A3K9PZ', memberIds: [meUid]);

      final service = serviceFor(meUid);
      final couple  = await service.getMyCouple();

      expect(await service.getPartnerName(couple!), isNull);
    });
  });

  group('記念日', () {
    test('設定した記念日が読み戻せる', () async {
      final id = await seedCouple(code: 'A3K9PZ', memberIds: [meUid]);
      final service = serviceFor(meUid);

      await service.setAnniversary(id, DateTime(2023, 4, 1));

      final couple = await service.getMyCouple();
      expect(couple!.anniversary, DateTime(2023, 4, 1));
    });
  });

  group('次に会う日', () {
    test('設定した次に会う日が読み戻せる', () async {
      final id = await seedCouple(code: 'A3K9PZ', memberIds: [meUid]);
      final service = serviceFor(meUid);

      await service.setNextMeetingDate(id, DateTime(2026, 9, 1));

      final couple = await service.getMyCouple();
      expect(couple!.nextMeetingDate, DateTime(2026, 9, 1));
    });

    test('nullを渡すと解除できる', () async {
      final id = await seedCouple(code: 'A3K9PZ', memberIds: [meUid]);
      final service = serviceFor(meUid);
      await service.setNextMeetingDate(id, DateTime(2026, 9, 1));

      await service.setNextMeetingDate(id, null);

      final couple = await service.getMyCouple();
      expect(couple!.nextMeetingDate, isNull);
    });
  });
}
