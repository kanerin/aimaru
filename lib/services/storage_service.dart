import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  // getterにしてあるのは、テスト用のサブクラス（メソッドをoverrideして
  // Firebaseに触れないようにする）を生成しただけでFirebaseStorage.instanceへ
  // アクセスしてしまわないようにするため。
  FirebaseStorage get _storage => FirebaseStorage.instance;

  // ── 予定に添付する画像をアップロード ──────────────
  Future<String> uploadEventImage(String coupleId, String eventId, File file) async {
    final ext = file.path.split('.').last;
    final ref = _storage
        .ref('couples/$coupleId/events/$eventId/${const Uuid().v4()}.$ext');
    final task = await ref.putFile(file);
    return task.ref.getDownloadURL();
  }

  // ── チャットに送る画像をアップロード ──────────────
  Future<String> uploadChatImage(String coupleId, File file) async {
    final ext = file.path.split('.').last;
    final ref = _storage
        .ref('couples/$coupleId/chat/${const Uuid().v4()}.$ext');
    final task = await ref.putFile(file);
    return task.ref.getDownloadURL();
  }

  // ── バグ報告・機能要望に添付する画像をアップロード ──────
  // reportIdはsubmitBugReportが受理した報告のFirestoreドキュメントID。
  // storage.rulesがそのドキュメントのcreatedByと一致する本人だけに
  // 書き込みを許可しているため、受理された（accepted: true）報告に対して
  // しか呼べない。
  Future<String> uploadBugReportImage(String reportId, File file) async {
    final ext = file.path.split('.').last;
    final ref = _storage
        .ref('bugReports/$reportId/${const Uuid().v4()}.$ext');
    final task = await ref.putFile(file);
    return task.ref.getDownloadURL();
  }

  // ── 画像を削除（URLから）──────────────────────────
  Future<void> deleteImage(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {
      // すでに削除済みなどは無視
    }
  }
}
