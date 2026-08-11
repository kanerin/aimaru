import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../utils/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _authService = AuthService();
  bool _loading = false;

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      final user = await _authService.signInWithGoogle();
      if (user != null && mounted) {
        context.go('/pairing');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ログインに失敗しました')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // ── ロゴ・タイトル ──
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: AppColors.navySurface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: const Center(
                  child: Text('✦', style: TextStyle(fontSize: 32)),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'AIMARU',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w300,
                  color: AppColors.cream,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '2人のスケジュールを、もっと近くに',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  letterSpacing: 1,
                ),
              ),

              const Spacer(flex: 2),

              // ── Googleログインボタン ──
              SizedBox(
                width: double.infinity,
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(color: appAccent(context)),
                      )
                    : OutlinedButton.icon(
                        onPressed: _signIn,
                        icon: Text('G', style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: appAccent(context),
                        )),
                        label: const Text('Googleでログイン'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.hairlineStrong),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
              ),

              const SizedBox(height: 16),
              const Text(
                'ログインすることでプライバシーポリシーに同意します',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
