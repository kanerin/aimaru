import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/couple_service.dart';
import '../../utils/app_theme.dart';
import '../services/deep_link_service.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen>
    with SingleTickerProviderStateMixin {
  final _coupleService = CoupleService();
  late final TabController _tab;

  String? _myCode;
  String? _codeError;
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;
  StreamSubscription? _coupleSub;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadCode();
    pendingInviteCode.addListener(_onPendingCodeChanged);
    _onPendingCodeChanged(); // 画面が開く前にリンクを受け取っていた場合に備える
    // 自分が発行したコードを相手が使ってペアが成立したら自動で遷移する
    _coupleSub = _coupleService.watchMyCouple().listen((couple) {
      if (mounted && couple != null && couple.memberIds.length >= 2) {
        context.go('/home');
      }
    });
  }

  Future<void> _loadCode() async {
    setState(() => _codeError = null);
    try {
      final code = await _coupleService.createInviteCode()
          .timeout(const Duration(seconds: 15));
      if (mounted) setState(() => _myCode = code);
    } catch (e) {
      if (mounted) setState(() => _codeError = '招待コードを取得できませんでした\n$e');
    }
  }

  // ── QR/リンク経由で受け取ったコードを自動入力して参加 ──
  void _onPendingCodeChanged() {
    final code = pendingInviteCode.value;
    if (code == null || code.isEmpty) return;
    pendingInviteCode.value = null; // 一度きり消費
    _codeController.text = code;
    _tab.animateTo(1);
    _joinWithCode();
  }

  Future<void> _joinWithCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = '6文字のコードを入力してください');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final couple = await _coupleService.joinWithCode(code)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;

      if (couple != null) {
        context.go('/home');
      } else {
        setState(() {
          _loading = false;
          _error   = 'コードが見つかりません。確認してもう一度試してください';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error   = '通信エラーが発生しました。もう一度お試しください';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('2人をつなぐ')),
      body: Column(
        children: [
          // ── タブ ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.navySurface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TabBar(
                controller: _tab,
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(4),
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                indicator: BoxDecoration(
                  color: appAccent(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textMuted,
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: '招待する'),
                  Tab(text: '参加する'),
                ],
              ),
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildCreateTab(),
                _buildJoinTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 招待コード作成タブ ────────────────────────────
  Widget _buildCreateTab() {
    final link = _myCode == null ? null : buildInviteLink(_myCode!);

    if (_codeError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 32),
            const SizedBox(height: 12),
            Text(_codeError!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _loadCode,
              style: OutlinedButton.styleFrom(
                foregroundColor: appAccent(context),
                side: BorderSide(color: appAccent(context)),
              ),
              child: const Text('再試行'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),

          const Text(
            '彼女に渡す招待コード',
            style: TextStyle(fontSize: 14, color: AppColors.textSecond),
          ),
          const SizedBox(height: 20),

          // QRコード
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: SizedBox(
              width: 160,
              height: 160,
              child: link == null
                  ? Center(child: CircularProgressIndicator(color: appAccent(context)))
                  : QrImageView(
                      data: link,
                      version: QrVersions.auto,
                      backgroundColor: Colors.white,
                    ),
            ),
          ),
          const SizedBox(height: 20),

          // コード表示
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.navySurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.hairline),
            ),
            child: _myCode == null
                ? CircularProgressIndicator(color: appAccent(context))
                : Text(
                    _myCode!.split('').join(' '),  // A 3 K 9 P Z
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: AppColors.cream,
                      letterSpacing: 8,
                    ),
                  ),
          ),
          const SizedBox(height: 20),

          // コピーボタン
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _myCode == null ? null : () {
                  Clipboard.setData(ClipboardData(text: _myCode!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('コードをコピーしました')),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('コード'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: appAccent(context),
                  side: BorderSide(color: appAccent(context)),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: link == null ? null : () {
                  Clipboard.setData(ClipboardData(text: link));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('リンクをコピーしました')),
                  );
                },
                icon: const Icon(Icons.link, size: 16),
                label: const Text('リンク'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: appAccent(context),
                  side: BorderSide(color: appAccent(context)),
                ),
              ),
            ],
          ),

          const Spacer(),

          const Text(
            '彼女がQRを読み取るかリンクを開くと\n2人の共有カレンダーが始まります ✦',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.8),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── 招待コード入力タブ ────────────────────────────
  Widget _buildJoinTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),

          const Text(
            '彼氏から受け取ったコードを入力',
            style: TextStyle(fontSize: 14, color: AppColors.textSecond),
          ),
          const SizedBox(height: 24),

          // コード入力
          TextField(
            controller: _codeController,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            style: const TextStyle(
              fontSize: 28,
              letterSpacing: 8,
              fontWeight: FontWeight.w700,
              color: AppColors.cream,
            ),
            decoration: const InputDecoration(
              hintText: '------',
              counterText: '',
            ),
            onChanged: (_) => setState(() => _error = null),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
          ],

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _joinWithCode,
              child: _loading
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('つながる'),
            ),
          ),

          const Spacer(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    pendingInviteCode.removeListener(_onPendingCodeChanged);
    _coupleSub?.cancel();
    _tab.dispose();
    _codeController.dispose();
    super.dispose();
  }
}
