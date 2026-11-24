import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/money.dart';
import '../../core/utils/vn_time.dart';
import '../../data/remote/stats_api.dart';
import '../../models/admin_user.dart';
import '../../models/enums.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/state_views.dart';
import '../profile/account_screen.dart';
import '../staff/manage_hub_screen.dart';
import 'users_screen.dart';

/// Chi tiết tài khoản (admin): thông tin, thống kê đơn (FutureBuilder), đổi vai trò, khóa / mở khóa.
/// Không cho tự đổi vai trò / tự khóa chính mình (backend cũng chặn: 403 CANNOT_MODIFY_SELF).
class UserDetailScreen extends StatefulWidget {
  const UserDetailScreen({super.key, required this.user, this.onChanged});

  /// Bản rút gọn từ danh sách — hiện ngay phần đầu trong lúc tải chi tiết.
  final AdminUser user;
  final ValueChanged<AdminUser>? onChanged;

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  late final AdminApi _api = context.read<AdminApi>();
  late Future<AdminUser> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _api.user(widget.user.id);
  }

  static String _roleRights(UserRole role) => switch (role) {
    UserRole.student => 'chỉ đặt món và theo dõi đơn của mình',
    UserRole.staff => 'xử lý đơn, quản lý thực đơn / voucher / đánh giá, xem thống kê',
    UserRole.admin => 'toàn quyền, kể cả quản lý tài khoản',
  };

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    bool danger = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Thôi')),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _run(Future<AdminUser> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() {
        _future = Future.value(updated);
      });
      widget.onChanged?.call(updated);
      messenger.showSnackBar(SnackBar(content: Text(done), duration: const Duration(seconds: 2)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ErrorView.messageOf(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeRole(AdminUser user, UserRole role) async {
    if (role == user.role) return;
    final ok = await _confirm(
      title: 'Đổi vai trò thành "${role.label}"?',
      message: '${user.fullName} sẽ có quyền: ${_roleRights(role)}. Có hiệu lực ngay.',
      action: 'Đổi vai trò',
    );
    if (ok) await _run(() => _api.changeRole(user.id, role), 'Đã đổi vai trò thành ${role.label}.');
  }

  Future<void> _toggleLock(AdminUser user) async {
    final lock = user.isActive;
    final ok = await _confirm(
      title: lock ? 'Khóa tài khoản này?' : 'Mở khóa tài khoản?',
      message: lock
          ? '${user.fullName} sẽ bị đăng xuất và không đăng nhập được nữa cho tới khi được mở khóa.'
          : '${user.fullName} sẽ đăng nhập và đặt món lại được.',
      action: lock ? 'Khóa' : 'Mở khóa',
      danger: lock,
    );
    if (ok) await _run(() => _api.setActive(user.id, !lock), lock ? 'Đã khóa tài khoản.' : 'Đã mở khóa tài khoản.');
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.select<AuthProvider, String?>((a) => a.profile?.id);
    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      body: FutureBuilder<AdminUser>(
        future: _future,
        builder: (context, snapshot) {
          // Trong lúc tải: hiện phần đầu từ dữ liệu danh sách, phần số liệu là skeleton.
          final loading = snapshot.connectionState != ConnectionState.done;
          if (!loading && snapshot.hasError) {
            return ErrorView(
              error: snapshot.error!,
              onRetry: () => setState(() {
                _future = _api.user(widget.user.id);
              }),
            );
          }
          final user = snapshot.data ?? widget.user;
          final isMe = user.id == myId;
          return formWidth(
            ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _Header(user: user),
                const SizedBox(height: AppSpacing.md),
                loading ? const SkeletonBox(height: 88, radius: AppRadius.lg) : _OrderStats(user),
                const SizedBox(height: AppSpacing.md),
                _InfoCard(user),
                const SizedBox(height: AppSpacing.md),
                _AdminActions(
                  user: user,
                  isMe: isMe,
                  enabled: !loading && !_busy && !isMe,
                  onRole: (r) => _changeRole(user, r),
                  onToggleLock: () => _toggleLock(user),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        UserAvatar(profile: user.asProfile, size: 88),
        const SizedBox(height: AppSpacing.sm),
        Text(user.fullName, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        Text(user.email, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [RoleBadge(user.role), if (!user.isActive) const LockedBadge()],
        ),
      ],
    );
  }
}

class _OrderStats extends StatelessWidget {
  const _OrderStats(this.user);

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String label, String value) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            cell('Đơn đã đặt', '${user.orderCount ?? 0}'),
            cell('Đã nhận món', '${user.completedOrderCount ?? 0}'),
            cell('Đã chi', Money.format(user.totalSpent ?? 0)),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(this.user);

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    ListTile row(IconData icon, String label, String value) =>
        ListTile(dense: true, leading: Icon(icon), title: Text(label), trailing: Text(value));
    return Card(
      child: Column(
        children: [
          row(Icons.badge_outlined, 'Mã số sinh viên', user.studentCode ?? '—'),
          row(Icons.phone_outlined, 'Số điện thoại', user.phone ?? '—'),
          row(Icons.calendar_today_outlined, 'Ngày tạo', VnTime.date(user.createdAt)),
          row(
            Icons.login_rounded,
            'Đăng nhập gần nhất',
            user.lastLoginAt == null ? 'Chưa đăng nhập' : VnTime.relative(user.lastLoginAt!),
          ),
        ],
      ),
    );
  }
}

class _AdminActions extends StatelessWidget {
  const _AdminActions({
    required this.user,
    required this.isMe,
    required this.enabled,
    required this.onRole,
    required this.onToggleLock,
  });

  final AdminUser user;
  final bool isMe;
  final bool enabled;
  final ValueChanged<UserRole> onRole;
  final VoidCallback onToggleLock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = theme.colorScheme.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Vai trò', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            // Màn hẹp (< 480) bỏ icon để chữ "Nhân viên" không bị xuống dòng.
            SegmentedButton<UserRole>(
              showSelectedIcon: false,
              segments: [
                for (final (role, label, icon) in const [
                  (UserRole.student, 'Sinh viên', Icons.school_outlined),
                  (UserRole.staff, 'Nhân viên', Icons.storefront_outlined),
                  (UserRole.admin, 'Quản trị', Icons.admin_panel_settings_outlined),
                ])
                  ButtonSegment(
                    value: role,
                    label: Text(label, maxLines: 1, softWrap: false),
                    icon: MediaQuery.sizeOf(context).width >= 480 ? Icon(icon) : null,
                  ),
              ],
              selected: {user.role},
              onSelectionChanged: enabled ? (s) => onRole(s.first) : null,
            ),
            const SizedBox(height: AppSpacing.md),
            if (isMe)
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Đây là tài khoản của bạn — không thể tự đổi vai trò hay tự khóa.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              )
            else
              user.isActive
                  ? OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: danger,
                        side: BorderSide(color: danger),
                      ),
                      onPressed: enabled ? onToggleLock : null,
                      icon: const Icon(Icons.lock_outline_rounded),
                      label: const Text('Khóa tài khoản'),
                    )
                  : FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: context.appColors.success),
                      onPressed: enabled ? onToggleLock : null,
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text('Mở khóa tài khoản'),
                    ),
          ],
        ),
      ),
    );
  }
}
