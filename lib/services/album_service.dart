import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/models.dart';

class AlbumService {
  // 引数なしで生成すると本番のFirebaseを使う（既存の呼び出しはそのまま）。
  // テストからは firestore / uid を差し込んでFirebaseに触れずに検証する。
  AlbumService({FirebaseFirestore? firestore, String? uid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _overrideUid = uid;

  final FirebaseFirestore _db;
  final String? _overrideUid;

  String get _uid => _overrideUid ?? FirebaseAuth.instance.currentUser!.uid;

  CollectionReference _photosRef(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('albumPhotos');

  // ── 写真を追加 ────────────────────────────────────
  // 実ファイルのアップロード（StorageService.uploadAlbumImage）は呼び出し側
  // （AlbumScreen）が行い、ここでは出来上がったURLをメタデータとして保存する。
  Future<AlbumPhoto> addPhoto(String coupleId, String imageUrl) async {
    final ref = _photosRef(coupleId).doc();
    final photo = AlbumPhoto(
      id:         ref.id,
      coupleId:   coupleId,
      imageUrl:   imageUrl,
      uploadedBy: _uid,
      createdAt:  DateTime.now(),
    );
    await ref.set(photo.toMap());
    return photo;
  }

  // ── 写真を削除 ────────────────────────────────────
  // Storage側の実ファイル削除は呼び出し側がStorageService.deleteImageで
  // 別途行う（このサービスはFirestoreのメタデータだけを扱う）。
  Future<void> deletePhoto(AlbumPhoto photo) async {
    await _photosRef(photo.coupleId).doc(photo.id).delete();
  }

  // ── 一覧をリアルタイム取得（新しい順）───────────────
  Stream<List<AlbumPhoto>> watchPhotos(String coupleId) {
    return _photosRef(coupleId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(AlbumPhoto.fromDoc).toList());
  }
}
