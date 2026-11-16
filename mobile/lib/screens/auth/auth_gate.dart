import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/firebase/auth_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/state_views.dart';
import '../home/home_shell.dart';
import '../staff/staff_shell.dart';
import 'complete_profile_screen.dart';
import 'login_screen.dart';
import 'widgets/auth_layout.dart';

enum _Gate { splash, signingOut, login, completeProfile, locked, error, student, staff }

/// Cửa ngõ của app — chọn màn theo trạng thái đăng nhập:
///
///  StreamBuilder nghe `authStateChanges()` của Firebase:
///   - đang chờ          → màn chờ
///   - chưa đăng nhập    → Đăng nhập
///   - đã đăng nhập      → theo hồ sơ backend (AuthProvider):
///       404 → Hoàn tất hồ sơ · 403 bị khóa → Tài khoản bị khóa · lỗi mạng → Thử lại
///       có hồ sơ → khung Sinh viên hoặc khung Nhân viên/Quản trị theo vai trò.
///
/// Khi chuyển sang màn gốc khác (đăng nhập xong, đăng xuất, bị khóa...), các màn đang mở chồng lên
/// (Đăng ký, Cài đặt...) được đóng hết để người dùng thấy ngay màn mới.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Tạo stream MỘT lần (không tạo trong build, tránh đăng ký lại mỗi lần rebuild).
  late final Stream<AuthUser?> _authChanges = context.read<AuthService>().authStateChanges();
  _Gate? _current;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthUser?>(
      stream: _authChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return _show(_Gate.splash);
        if (snapshot.data == null) return _show(_Gate.login);

        final auth = context.watch<AuthProvider>();
        return switch (auth.status) {
          AuthStatus.needsProfile => _show(_Gate.completeProfile),
          AuthStatus.locked => _show(_Gate.locked),
          AuthStatus.error => _show(_Gate.error),
          // Đóng cả các màn đang mở chồng lên (VD: Theo dõi đơn) để mọi listener Firebase được hủy trước khi đăng xuất.
          AuthStatus.signingOut => _show(_Gate.signingOut),
          AuthStatus.ready when auth.profile!.role.isStaffOrAdmin => _show(_Gate.staff),
          AuthStatus.ready => _show(_Gate.student),
          // unknown / loadingProfile / signedOut (stream đã báo đăng nhập, provider chưa kịp cập nhật)
          _ => _show(_Gate.splash),
        };
      },
    );
  }

  Widget _show(_Gate gate) {
    if (_current != null && _current != gate && gate != _Gate.splash) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
    }
    _current = gate;
    return switch (gate) {
      _Gate.splash || _Gate.signingOut => const SplashView(),
      _Gate.login => const LoginScreen(),
      _Gate.completeProfile => const CompleteProfileScreen(),
      _Gate.locked => const AccountLockedScreen(),
      _Gate.error => const SessionErrorScreen(),
      _Gate.student => const HomeShell(),
      _Gate.staff => const StaffShell(),
    };
  }
}

/// Màn chờ lúc mở app / đang tải hồ sơ.
class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLogo(size: 72),
          const SizedBox(height: AppSpacing.lg),
          Text('Smart Canteen', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.lg),
          const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
        ],
      ),
    ),
  );
}

/// 403 ACCOUNT_LOCKED.
class AccountLockedScreen extends StatelessWidget {
  const AccountLockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: EmptyState(
                icon: Icons.lock_person_rounded,
                title: 'Tài khoản đã bị khóa',
                message:
                    'Tài khoản ${auth.user?.email ?? ''} tạm thời không thể đặt món. '
                    'Vui lòng liên hệ quầy căn-tin hoặc quản trị viên để được mở khóa.',
                actionLabel: 'Kiểm tra lại',
                onAction: auth.loadProfile,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextButton(onPressed: auth.signOut, child: const Text('Đăng xuất')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Không tải được hồ sơ (mất mạng, sai địa chỉ máy chủ, máy chủ lỗi).
class SessionErrorScreen extends StatelessWidget {
  const SessionErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Cài đặt máy chủ',
            icon: const Icon(Icons.dns_outlined),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.serverSettings),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ErrorView(error: auth.error ?? 'unknown', onRetry: auth.loadProfile),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextButton(onPressed: auth.signOut, child: const Text('Đăng xuất')),
            ),
          ],
        ),
      ),
    );
  }
}
