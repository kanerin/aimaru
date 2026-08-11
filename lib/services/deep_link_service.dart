import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

// ── 招待リンクのスキーム ──────────────────────────────
// 例: aimaru://join?code=A3K9PZ
const inviteLinkScheme = 'aimaru';
const inviteLinkHost = 'join';

String buildInviteLink(String code) => '$inviteLinkScheme://$inviteLinkHost?code=$code';

// ── リンク経由で受け取った招待コード ─────────────────
// PairingScreen がこれを監視し、値が入ったら自動で参加処理を行う
final ValueNotifier<String?> pendingInviteCode = ValueNotifier<String?>(null);

class DeepLinkService {
  final _appLinks = AppLinks();

  Future<void> init() async {
    try {
      final initial = await _appLinks.getInitialLink();
      _handle(initial);
    } catch (_) {
      // 初回リンクが取得できなくても致命的ではないため無視
    }
    _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
  }

  void _handle(Uri? uri) {
    if (uri == null) return;
    final code = uri.queryParameters['code']?.trim();
    if (code != null && code.isNotEmpty) {
      pendingInviteCode.value = code.toUpperCase();
    }
  }
}
