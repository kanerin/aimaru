import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final _auth       = FirebaseAuth.instance;
  // ── scopes: 'email' はログイン用、calendar.events は
  //    google_calendar_service.dart の同期機能で使う（同一セッションを共有）
  final _googleSign = GoogleSignIn(scopes: [
    'email',
    'https://www.googleapis.com/auth/calendar.events',
  ]);
  final _db         = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Google ログイン ───────────────────────────────
  Future<User?> signInWithGoogle() async {
    final googleUser = await _googleSign.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken:     googleAuth.idToken,
    );

    final result = await _auth.signInWithCredential(credential);
    final user   = result.user;
    if (user == null) return null;

    // Firestoreにユーザー情報を保存
    final userRef  = _db.collection('users').doc(user.uid);
    final existing = await userRef.get();
    final profile  = {
      'uid':         user.uid,
      'displayName': user.displayName,
      'email':       user.email,
      'photoUrl':    user.photoURL,
    };

    if (!existing.exists) {
      // 初回ログイン時のみ: 作成日時と通知設定のデフォルト値をセット
      await userRef.set({
        ...profile,
        'createdAt':             FieldValue.serverTimestamp(),
        'notifyOnNewEvent':      true,
        'remindersEnabled':      true,
        'reminderMinutesBefore': 60,
      });
    } else {
      await userRef.set(profile, SetOptions(merge: true));
    }

    return user;
  }

  // ── サインアウト ──────────────────────────────────
  Future<void> signOut() async {
    await _googleSign.signOut();
    await _auth.signOut();
  }

  // ── ユーザー表示名取得 ────────────────────────────
  Future<String?> getDisplayName(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['displayName'] as String?;
  }

  // ── 退会（アカウント削除）────────────────────────
  // Firebase Authのユーザーを削除し、続けて users/{uid} の個人データを消す。
  // ペア（couples）側の後始末はここでは行わない。呼び出し側が
  // CoupleService.leaveCouple を先に呼ぶこと（このクラスはAuth/自分の
  // プロフィールだけを扱い、他サービスには依存しない設計を保つため）。
  //
  // サインインから時間が経っていると、Firebaseは削除のような機微な操作を
  // requires-recent-loginで拒否する。その場合はGoogleへ再ログインしてから
  // 1回だけ再試行する。
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final uid = user.uid;

    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login') rethrow;
      await _reauthenticate();
      await _auth.currentUser!.delete();
    }

    await _db.collection('users').doc(uid).delete();
    await _googleSign.signOut();
  }

  Future<void> _reauthenticate() async {
    final googleUser = await _googleSign.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'reauthentication-cancelled',
        message: '再ログインがキャンセルされました',
      );
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken:     googleAuth.idToken,
    );

    await _auth.currentUser!.reauthenticateWithCredential(credential);
  }
}
