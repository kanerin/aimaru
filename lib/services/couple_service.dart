import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

class CoupleService {
  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  CoupleService({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  // ── 自分がペアに属しているか確認 ─────────────────
  Future<CoupleModel?> getMyCouple() async {
    final snap = await _db
        .collection('couples')
        .where('memberIds', arrayContains: _uid)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    return CoupleModel.fromDoc(snap.docs.first);
  }

  Stream<CoupleModel?> watchMyCouple() {
    return _db
        .collection('couples')
        .where('memberIds', arrayContains: _uid)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty ? null : CoupleModel.fromDoc(snap.docs.first));
  }

  // ── 招待コードを生成してペアを作る ───────────────
  // 6桁の英数字コード（例: A3K9PZ）
  Future<String> createInviteCode() async {
    // すでにペアがある場合は既存コードを返す
    final existing = await getMyCouple();
    if (existing != null) return existing.inviteCode;

    final code     = _generateCode();
    final coupleId = const Uuid().v4();

    await _db.collection('couples').doc(coupleId).set({
      'memberIds':  [_uid],
      'inviteCode': code,
      'createdAt':  FieldValue.serverTimestamp(),
      'anniversary': null,
    });

    return code;
  }

  // ── 招待コードで参加 ──────────────────────────────
  Future<CoupleModel?> joinWithCode(String code) async {
    final upper = code.trim().toUpperCase();

    // コードでカップルを検索
    final snap = await _db
        .collection('couples')
        .where('inviteCode', isEqualTo: upper)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;

    final doc    = snap.docs.first;
    final couple = CoupleModel.fromDoc(doc);

    // すでに2人いる場合はNG
    if (couple.memberIds.length >= 2) return null;
    // 自分が作ったペアには参加できない
    if (couple.memberIds.contains(_uid)) return null;

    // 自分をメンバーに追加
    await doc.reference.update({
      'memberIds': FieldValue.arrayUnion([_uid]),
    });

    return CoupleModel.fromDoc(await doc.reference.get());
  }

  // ── 記念日を設定 ──────────────────────────────────
  Future<void> setAnniversary(String coupleId, DateTime date) async {
    await _db.collection('couples').doc(coupleId).update({
      'anniversary': Timestamp.fromDate(date),
    });
  }

  // ── 次に会う日を設定（nullで解除）────────────────
  Future<void> setNextMeetingDate(String coupleId, DateTime? date) async {
    await _db.collection('couples').doc(coupleId).update({
      'nextMeetingDate': date != null ? Timestamp.fromDate(date) : null,
    });
  }

  // ── 基本の休日を設定 ──────────────────────────────
  // 2人で共有する設定なので端末ローカルではなくカップルのドキュメントに持つ。
  // （既存の couples の update ルールでメンバーなら書き込めるため、
  //   セキュリティルールの追加は不要）
  Future<void> setDaysOff(
    String coupleId, {
    required List<int> daysOff,
    required bool holidaysAreDaysOff,
  }) async {
    await _db.collection('couples').doc(coupleId).update({
      'daysOff': daysOff..sort(),
      'holidaysAreDaysOff': holidaysAreDaysOff,
    });
  }

  // ── ペアを解消する（自分だけ抜ける）──────────────
  // 予定・チャット・写真・TODO・割り勘・ふたりの質問への回答はそのまま
  // couples/{coupleId} 側に残す。共有してきたデータを片方の操作で
  // 一方的に消してしまわないための判断（相手がまだ見返したいかもしれない）。
  // 自分しかメンバーがいない（相手がまだ参加していない、または既に抜けた）
  // 場合だけ、カップルのドキュメント自体を削除する
  // （残っていても誰の役にも立たないゴミになるだけなので）。
  //
  // サブコレクション（events等）は削除しない。memberIdsから外れた時点で
  // firestore.rulesの`request.auth.uid in couples/{coupleId}.data.memberIds`
  // 判定により、自分からは二度と読み書きできなくなる。
  Future<void> leaveCouple(String coupleId) async {
    final ref = _db.collection('couples').doc(coupleId);
    final snap = await ref.get();
    if (!snap.exists) return;

    final memberIds = List<String>.from(snap.data()?['memberIds'] ?? []);
    if (memberIds.length <= 1) {
      await ref.delete();
    } else {
      await ref.update({
        'memberIds': FieldValue.arrayRemove([_uid]),
      });
    }
  }

  // ── パートナーの表示名を取得 ──────────────────────
  Future<String?> getPartnerName(CoupleModel couple) async {
    final partnerId = couple.memberIds.firstWhere(
      (id) => id != _uid,
      orElse: () => '',
    );
    if (partnerId.isEmpty) return null;

    final doc = await _db.collection('users').doc(partnerId).get();
    return doc.data()?['displayName'] as String?;
  }

  // ── 6桁コード生成 ─────────────────────────────────
  // 以前は現在時刻(マイクロ秒)にインデックスを足して文字を選んでいたため、
  // 6文字が文字表の連番（例: ABCDEF）になり、コードが推測可能だった。
  // 招待コードは「まだ相手が決まっていないペア」への参加キーなので、
  // 推測できると第三者が横から参加できてしまう。暗号論的乱数を使う。
  static final _random = Random.secure();

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 紛らわしい文字を除外
    return List.generate(6, (_) => chars[_random.nextInt(chars.length)]).join();
  }
}
