import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/common.dart';

/// Tab Tài khoản (dùng chung cho sinh viên và nhân viên): hồ sơ, giao diện, máy chủ, đăng xuất.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text('Giỏ hàng vẫn được lưu trên máy cho lần đăng nhập sau.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ở lại')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Đăng xuất')),
        ],
      ),
    );
    if (ok == true) await auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final profile = context.watch<AuthProvider>().profile;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          MaxWidthBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (profile != null) _ProfileHeader(profile),
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader('Giao diện'),
                const SizedBox(height: AppSpacing.xs),
                Padding(
                  padding: AppSpacing.pagePadding,
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Sáng')),
                      ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Tối')),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_outlined),
                        label: Text('Hệ thống'),
                      ),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (s) => settings.setThemeMode(s.first),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader('Kết nối'),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('Địa chỉ máy chủ'),
                  subtitle: Text(settings.apiBaseUrl),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pushNamed(context, AppRoutes.serverSettings),
                ),
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: AppSpacing.pagePadding,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.4)),
                    ),
                    onPressed: () => _confirmSignOut(context),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Đăng xuất'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader(this.profile);

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              UserAvatar(profile: profile, size: 64),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.fullName,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(profile.email, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      children: [
                        _Tag(icon: Icons.verified_user_outlined, text: profile.role.label),
                        if (profile.studentCode != null) _Tag(icon: Icons.school_outlined, text: profile.studentCode!),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(color: context.appColors.subtleBrand, borderRadius: AppRadius.smAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Ảnh đại diện: ảnh thật nếu có, không thì chữ cái đầu trên nền cam nhạt.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.profile, this.size = 40});

  final UserProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (profile.avatarUrl != null) {
      return AppNetworkImage(
        profile.avatarUrl,
        width: size,
        height: size,
        borderRadius: BorderRadius.circular(size / 2),
        icon: Icons.person_rounded,
      );
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      child: Text(
        profile.initials,
        style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
      ),
    );
  }
}
