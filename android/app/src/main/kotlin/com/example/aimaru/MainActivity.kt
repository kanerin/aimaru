package com.example.aimaru

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth（アプリロックの指紋・顔認証）はandroidx.biometricのBiometricPromptを
// 使うため、ホストがFragmentActivityであることを要求する。FlutterActivityのままだと
// 認証ダイアログを出す時点で "local_auth requires activity to be a FragmentActivity"
// と失敗するので、FlutterFragmentActivityを継承する。
class MainActivity : FlutterFragmentActivity()
