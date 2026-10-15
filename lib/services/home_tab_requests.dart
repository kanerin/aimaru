import 'package:flutter/foundation.dart';

// ホーム（_HomeShell、main.dart）の下部ナビのタブ。並びはNavigationBarと同じ。
enum HomeTab { calendar, chat, anniversary, questions }

// 画面の外（通知タップなど）から「ホームのこのタブを開いて」と頼むための受け口。
// ホームがまだ表示されていない（通知からの起動でログイン確認中、ペア情報の
// 読み込み中など）ときに頼まれても取りこぼさないよう、ホームが受け取るまで
// 保留しておき、ホームは表示されたときと通知を受けたときにtake()で取り出す。
class HomeTabRequests extends ChangeNotifier {
  static final HomeTabRequests instance = HomeTabRequests();

  HomeTab? _pending;

  void request(HomeTab tab) {
    _pending = tab;
    notifyListeners();
  }

  // 保留中の依頼を取り出す（同じ依頼を二度処理しないよう空にする）。
  HomeTab? take() {
    final tab = _pending;
    _pending = null;
    return tab;
  }
}
