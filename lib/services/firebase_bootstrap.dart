import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

// ── 結合テスト(integration_test)用: Firebaseをローカルエミュレータへ向ける ──
//
// 通常のビルド（テスター配布・本番・開発中のflutter run）では
// USE_FIREBASE_EMULATOR が未定義なので false になり、この仕組みは完全に無効。
// 本番の挙動には一切影響しない。
//
// 結合テスト時のみこう渡してエミュレータに繋ぐ:
//   flutter test integration_test --dart-define=USE_FIREBASE_EMULATOR=true
//
// これにより結合テストが本番のFirestore・認証・Storageを汚さずに済む。
const bool useFirebaseEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');

// Androidエミュレータから見たホストマシンのアドレスは 10.0.2.2 固定。
// iOSシミュレータや実機から動かす場合は
// --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 のように上書きする。
const String firebaseEmulatorHost =
    String.fromEnvironment('FIREBASE_EMULATOR_HOST', defaultValue: '10.0.2.2');

// firebase.json の emulators 設定と一致させること
const int _authEmulatorPort = 9099;
const int _firestoreEmulatorPort = 8080;
const int _storageEmulatorPort = 9199;

bool _connected = false;

/// エミュレータへの接続をプロセスごとに1回だけ行う。
///
/// Firestoreは一度でも読み書きしたあとに useFirestoreEmulator を呼ぶと例外に
/// なるため、二重呼び出しをここで防いでいる（main()とテストのsetUpの両方から
/// 呼ばれても安全にするための措置）。
Future<void> connectFirebaseEmulators() async {
  if (!useFirebaseEmulator || _connected) return;
  _connected = true;

  await FirebaseAuth.instance.useAuthEmulator(
    firebaseEmulatorHost,
    _authEmulatorPort,
  );
  FirebaseFirestore.instance.useFirestoreEmulator(
    firebaseEmulatorHost,
    _firestoreEmulatorPort,
  );
  await FirebaseStorage.instance.useStorageEmulator(
    firebaseEmulatorHost,
    _storageEmulatorPort,
  );
}
