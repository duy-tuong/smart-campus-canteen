import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/money.dart';
import '../../data/firebase/realtime_service.dart';
import '../../data/local/order_dao.dart';
import '../../data/remote/order_api.dart';
import '../../models/enums.dart';
import '../../models/live.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/home_tabs.dart';
import '../../widgets/state_views.dart';

/// Thanh toán chuyển khoản: QR VietQR (qr_flutter) + thông tin chuyển tay có nút sao chép + đếm ngược.
///
/// Nghe Firebase `orders/{id}` (RealtimeService.watchOrder): ngân hàng báo có tiền → backend cập nhật →
/// màn hình chuyển sang "thành công" NGAY. Dự phòng: tự hỏi máy chủ mỗi [pollInterval] nếu Firebase chậm.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.order, this.pollInterval = const Duration(seconds: 15)});

  final OrderDetail order;
  final Duration pollInterval;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late OrderDetail _order = widget.order;
  late final OrderApi _api = context.read<OrderApi>();
  Timer? _ticker;
  Timer? _poller;
  StreamSubscription<OrderLive?>? _liveSub;
  Duration _remaining = Duration.zero;
  bool _syncing = false;
  bool _done = false;

  PaymentInfo get _payment => _order.payment!;

  @override
  void initState() {
    super.initState();
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _poller = Timer.periodic(widget.pollInterval, (_) => _refresh(silent: true));
    _liveSub = context.read<RealtimeService>().watchOrder(widget.order.id).listen((live) {
      if (live == null) return;
      // Có tiền hoặc đơn bị hủy → tải chi tiết đầy đủ rồi chuyển màn / hiện trạng thái hủy.
      if (live.paymentStatus == PaymentStatus.paid || live.status == OrderStatus.cancelled) _refresh(silent: true);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _poller?.cancel();
    _liveSub?.cancel();
    super.dispose();
  }

  void _tick() {
    final expires = _payment.expiresAt;
    final left = expires == null ? Duration.zero : expires.difference(DateTime.now().toUtc());
    setState(() => _remaining = left.isNegative ? Duration.zero : left);
  }

  bool get _expired => _payment.expiresAt != null && _remaining == Duration.zero;

  /// [silent]: lượt tự kiểm tra nền (không báo gì nếu chưa có tiền).
  Future<void> _refresh({bool silent = false}) async {
    if (_done || _syncing) return;
    if (!silent) setState(() => _syncing = true);
    try {
      final order = silent ? await _api.getOrder(_order.id) : await _api.syncPayment(_order.id);
      if (!mounted) return;
      // Đã trả tiền → chuyển màn luôn (đơn đã trả không còn mã QR để vẽ lại).
      if (order.paymentStatus == PaymentStatus.paid) {
        await _finish(order);
        return;
      }
      setState(() => _order = order);
      if (order.status == OrderStatus.cancelled) {
        _stopTimers();
      } else if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa nhận được tiền. Ngân hàng có thể chậm vài phút — app sẽ tự cập nhật.')),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ErrorView.messageOf(e))));
      }
    } finally {
      if (mounted && !silent) setState(() => _syncing = false);
    }
  }

  void _stopTimers() {
    _ticker?.cancel();
    _poller?.cancel();
    _liveSub?.cancel();
  }

  Future<void> _finish(OrderDetail order) async {
    _done = true;
    _stopTimers();
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid != null) await context.read<OrderDao>().upsertDetail(order, uid);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.orderPlaced, arguments: order);
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Đã sao chép $label'), duration: const Duration(seconds: 2)));
  }

  Future<void> _openCheckout() async {
    final url = _payment.checkoutUrl;
    if (url == null) return;
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không mở được trang thanh toán.')));
    }
  }

  void _backToMenu() {
    context.read<HomeTabs>().select(HomeTabs.orders);
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final cancelled = _order.status == OrderStatus.cancelled;
    return Scaffold(
      appBar: AppBar(title: const Text('Chuyển khoản')),
      body: cancelled || _expired
          ? EmptyState(
              icon: Icons.timer_off_outlined,
              title: cancelled ? 'Đơn đã bị hủy' : 'Hết thời gian thanh toán',
              message: cancelled
                  ? (_order.cancelReason ?? 'Đơn chuyển khoản không được thanh toán kịp nên đã tự hủy.')
                  : 'Nếu bạn đã chuyển khoản, bấm "Kiểm tra lại". Đơn chưa thanh toán sẽ tự hủy.',
              actionLabel: cancelled ? 'Xem đơn hàng' : 'Kiểm tra lại',
              onAction: cancelled ? _backToMenu : _refresh,
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                final qr = _QrCard(payment: _payment, remaining: _remaining, total: _order.totalAmount);
                final details = _TransferDetails(order: _order, onCopy: _copy);
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: MaxWidthBox(
                    maxWidth: wide ? 960 : Breakpoints.maxContentWidth,
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: qr),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(child: details),
                            ],
                          )
                        : Column(
                            children: [
                              qr,
                              const SizedBox(height: AppSpacing.md),
                              details,
                            ],
                          ),
                  ),
                );
              },
            ),
      bottomNavigationBar: cancelled || _expired
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: _syncing ? null : _refresh,
                      icon: _syncing
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : const Icon(Icons.verified_outlined),
                      label: const Text('Tôi đã chuyển khoản'),
                    ),
                    if (_payment.checkoutUrl != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      OutlinedButton.icon(
                        onPressed: _openCheckout,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Mở trang thanh toán payOS'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.payment, required this.remaining, required this.total});

  final PaymentInfo payment;
  final Duration remaining;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urgent = remaining.inMinutes < 3;
    final mm = remaining.inMinutes.toString().padLeft(2, '0');
    final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Text('Quét mã bằng app ngân hàng', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xxs),
            SizedBox(
              height: 40,
              child: FittedBox(
                child: Text(
                  Money.format(total),
                  style: theme.textTheme.headlineSmall?.tabular.copyWith(color: context.appColors.price),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // QR luôn nền trắng (kể cả giao diện tối) để app ngân hàng quét được.
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.mdAll),
              child: payment.qrCode == null
                  ? const SizedBox.square(
                      dimension: 220,
                      child: Icon(Icons.qr_code_2_rounded, size: 96, color: Colors.black26),
                    )
                  : QrImageView(
                      data: payment.qrCode!,
                      size: 220,
                      backgroundColor: Colors.white,
                      semanticsLabel: 'Mã VietQR thanh toán đơn hàng',
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer_outlined, size: 18, color: urgent ? context.appColors.cancelled : null),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  'Còn $mm:$ss để thanh toán',
                  style: theme.textTheme.bodyMedium?.tabular.copyWith(
                    color: urgent ? context.appColors.cancelled : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferDetails extends StatelessWidget {
  const _TransferDetails({required this.order, required this.onCopy});

  final OrderDetail order;
  final void Function(String label, String value) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = order.payment!;
    Widget row(String label, String? value, {bool copy = false, bool strong = false}) => value == null
        ? const SizedBox.shrink()
        : ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            subtitle: Text(
              value,
              style: (strong ? theme.textTheme.titleSmall : theme.textTheme.bodyLarge)?.tabular.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            trailing: copy
                ? IconButton(
                    tooltip: 'Sao chép $label',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () => onCopy(label.toLowerCase(), value),
                  )
                : null,
          );

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row('Mã đơn', order.pickupCode, strong: true),
            row('Chủ tài khoản', p.bankAccountName),
            row('Số tài khoản', p.bankAccountNumber, copy: true),
            row('Số tiền', Money.format(p.amount), strong: true),
            row('Nội dung chuyển khoản', p.transferContent, copy: true, strong: true),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: context.appColors.warning),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Ghi ĐÚNG nội dung chuyển khoản để hệ thống tự nhận tiền. Căn-tin bắt đầu nấu ngay khi nhận được tiền.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
