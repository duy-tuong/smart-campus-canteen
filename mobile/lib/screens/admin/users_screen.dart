import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/debouncer.dart';
import '../../data/remote/stats_api.dart';
import '../../models/admin_user.dart';
import '../../models/enums.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/state_views.dart';
import '../profile/account_screen.dart';
import '../staff/manage_hub_screen.dart';
import 'user_detail_screen.dart';

/// Quản trị tài khoản (admin): tìm theo tên không dấu / email / MSSV, lọc vai trò, lọc tài khoản bị khóa,
/// cuộn vô hạn (ScrollController + phân trang API). Bấm một dòng → chi tiết, đổi vai trò, khóa / mở khóa.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late final AdminApi _api = context.read<AdminApi>();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _debouncer = Debouncer();

  UserRole? _role;
  bool _lockedOnly = false;

  final List<AdminUser> _items = [];
  int _page = 0;
  int _total = 0;
  bool _hasNext = true;
  bool _loading = false;
  Object? _error;

  /// Tăng mỗi lần đổi bộ lọc — bỏ kết quả của lượt tải cũ về muộn.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  Future<void> _reload() {
    _generation++;
    setState(() {
      _items.clear();
      _page = 0;
      _hasNext = true;
      _error = null;
      _loading = false;
    });
    return _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNext) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.users(
        search: _search.text,
        role: _role,
        isActive: _lockedOnly ? false : null,
        page: _page + 1,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _page = page.page;
        _total = page.totalCount;
        _hasNext = page.hasNext;
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _open(int index) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserDetailScreen(
          user: _items[index],
          onChanged: (updated) {
            if (!mounted) return;
            setState(() {
              final i = _items.indexWhere((u) => u.id == updated.id);
              if (i >= 0) _items[i] = updated;
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myId = context.select<AuthProvider, String?>((a) => a.profile?.id);

    return Scaffold(
      appBar: AppBar(title: const Text('Người dùng')),
      body: Column(
        children: [
          Padding(
            padding: AppSpacing.pagePadding,
            child: formWidth(
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Tên, email hoặc MSSV',
                  suffixIcon: ListenableBuilder(
                    listenable: _search,
                    builder: (context, _) => _search.text.isEmpty
                        ? const SizedBox.shrink()
                        : IconButton(
                            tooltip: 'Xóa',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _search.clear();
                              _reload();
                            },
                          ),
                  ),
                ),
                onChanged: (_) => _debouncer.run(_reload),
                onSubmitted: (_) {
                  _debouncer.cancel();
                  _reload();
                },
              ),
            ),
          ),
          // Chỉ 5 chip → SingleChildScrollView + Row (dựng hết một lần), vuốt ngang khi màn hẹp.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            child: Row(
              children: [
                for (final role in <UserRole?>[null, ...UserRole.values])
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: ChoiceChip(
                      label: Text(role == null ? 'Tất cả' : _roleShort(role)),
                      showCheckmark: false,
                      selected: _role == role,
                      onSelected: (_) {
                        setState(() => _role = role);
                        _reload();
                      },
                    ),
                  ),
                FilterChip(
                  avatar: const Icon(Icons.lock_outline_rounded, size: 18),
                  label: const Text('Đã khóa'),
                  showCheckmark: false,
                  selected: _lockedOnly,
                  onSelected: (v) {
                    setState(() => _lockedOnly = v);
                    _reload();
                  },
                ),
              ],
            ),
          ),
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xxs),
              child: formWidth(
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$_total tài khoản',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          Expanded(child: _list(myId)),
        ],
      ),
    );
  }

  Widget _list(String? myId) {
    if (_items.isEmpty) {
      if (_error != null) return ErrorView(error: _error!, onRetry: _reload);
      if (_loading || _hasNext) return const SkeletonList();
      return EmptyState(
        icon: Icons.person_search_rounded,
        title: 'Không tìm thấy tài khoản',
        message: _search.text.isEmpty ? null : 'Thử tìm bằng email hoặc mã số sinh viên.',
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: formWidth(
        ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          itemCount: _items.length + 1,
          itemBuilder: (context, i) {
            if (i == _items.length) {
              if (_error != null) {
                return TextButton(onPressed: _loadMore, child: const Text('Lỗi tải thêm — thử lại'));
              }
              return _hasNext
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : const SizedBox.shrink();
            }
            final u = _items[i];
            return _UserTile(user: u, isMe: u.id == myId, onTap: () => _open(i));
          },
        ),
      ),
    );
  }
}

String _roleShort(UserRole role) => switch (role) {
  UserRole.student => 'Sinh viên',
  UserRole.staff => 'Nhân viên',
  UserRole.admin => 'Quản trị',
};

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.isMe, required this.onTap});

  final AdminUser user;
  final bool isMe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ListTile(
      onTap: onTap,
      leading: Opacity(
        opacity: user.isActive ? 1 : 0.5,
        child: UserAvatar(profile: user.asProfile, size: 44),
      ),
      title: Row(
        children: [
          Flexible(child: Text(user.fullName, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (isMe) ...[const SizedBox(width: AppSpacing.xs), Text('(bạn)', style: muted)],
        ],
      ),
      subtitle: Text(
        [user.email, ?user.studentCode].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: muted,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          RoleBadge(user.role),
          if (!user.isActive) ...[const SizedBox(height: AppSpacing.xxs), const LockedBadge()],
        ],
      ),
    );
  }
}

/// Nhãn vai trò: màu nền nhạt + chữ (không chỉ dựa vào màu).
class RoleBadge extends StatelessWidget {
  const RoleBadge(this.role, {super.key});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (role) {
      UserRole.admin => theme.colorScheme.primary,
      UserRole.staff => context.appColors.received,
      UserRole.student => theme.colorScheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppRadius.smAll),
      child: Text(
        _roleShort(role),
        style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class LockedBadge extends StatelessWidget {
  const LockedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final color = context.appColors.cancelled;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_rounded, size: 12, color: color),
        const SizedBox(width: 2),
        Text(
          'Đã khóa',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
