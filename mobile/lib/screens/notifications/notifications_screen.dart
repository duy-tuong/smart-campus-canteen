import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/vn_time.dart';
import '../../data/firebase/realtime_service.dart';
import '../../data/remote/notification_api.dart';
import '../../models/live.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/state_views.dart';

/// Tab Thông báo — StreamBuilder trên Firebase `notifications/{uid}` (thông báo mới hiện ngay, không cần kéo
/// làm mới). Chạm → đánh dấu đã đọc (REST) và mở đúng đơn hàng.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Stream<List<AppNotification>> _stream;

  /// Đã chạm nhưng Firebase chưa kịp phản hồi isRead → hiện là đã đọc ngay (lạc quan).
  final Set<int> _readLocally = {};

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final uid = context.read<AuthProvider>().user!.uid;
    _stream = context.read<RealtimeService>().watchNotifications(uid);
  }

  bool _isRead(AppNotification n) => n.isRead || _readLocally.contains(n.id);

  Future<void> _open(AppNotification n) async {
    if (!_isRead(n)) {
      setState(() => _readLocally.add(n.id));
      context.read<NotificationApi>().markRead(n.id).catchError((_) {});
    }
    if (n.type == NotificationType.orderStatus && n.refId != null) {
      await Navigator.pushNamed(context, AppRoutes.order, arguments: n.refId);
    }
  }

  Future<void> _readAll(List<AppNotification> items) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _readLocally.addAll(items.map((n) => n.id)));
    try {
      await context.read<NotificationApi>().markAllRead();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ErrorView.messageOf(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppNotification>>(
      stream: _stream,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <AppNotification>[];
        final unread = items.where((n) => !_isRead(n)).length;
        return Scaffold(
          appBar: AppBar(
            title: Text(unread > 0 ? 'Thông báo ($unread)' : 'Thông báo'),
            actions: [if (unread > 0) TextButton(onPressed: () => _readAll(items), child: const Text('Đọc tất cả'))],
          ),
          body: switch (snapshot.connectionState) {
            ConnectionState.none || ConnectionState.waiting => const SkeletonList(),
            _ when snapshot.hasError => ErrorView(error: snapshot.error!, onRetry: () => setState(_subscribe)),
            _ when items.isEmpty => const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'Chưa có thông báo',
              message: 'Khi món của bạn sẵn sàng, thông báo sẽ hiện ở đây ngay lập tức.',
            ),
            _ => MaxWidthBox(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(indent: 72),
                itemBuilder: (context, i) =>
                    _NotificationTile(notification: items[i], isRead: _isRead(items[i]), onTap: () => _open(items[i])),
              ),
            ),
          },
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.isRead, required this.onTap});

  final AppNotification notification;
  final bool isRead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final (icon, color) = switch (notification.type) {
      NotificationType.orderStatus => (Icons.receipt_long_rounded, colors.received),
      NotificationType.promotion => (Icons.local_offer_rounded, theme.colorScheme.primary),
      NotificationType.review => (Icons.rate_review_rounded, colors.rating),
      NotificationType.system => (Icons.info_rounded, colors.completed),
    };
    return ListTile(
      onTap: onTap,
      tileColor: isRead ? null : colors.subtleBrand,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, color: color),
      ),
      title: Text(notification.title, style: isRead ? theme.textTheme.bodyLarge : theme.textTheme.titleSmall),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(notification.body, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 2),
          Text(VnTime.relative(notification.createdAt)),
        ],
      ),
      trailing: isRead
          ? null
          : Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
            ),
    );
  }
}
