import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/money.dart';
import '../../core/utils/vn_time.dart';
import '../../data/local/order_dao.dart';
import '../../data/remote/api_exception.dart';
import '../../data/remote/order_api.dart';
import '../../models/cart_item.dart';
import '../../models/checkout.dart';
import '../../models/enums.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';
import 'idempotency.dart';
import 'voucher_picker_screen.dart';

/// Thanh toán: FutureBuilder báo giá (POST /api/orders/quote) — chạy lại khi đổi voucher hoặc sửa giỏ.
/// Lỗi theo từng món (hết suất, ngừng bán, tùy chọn sai) tô đỏ đúng dòng kèm cách sửa.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late final OrderApi _api = context.read<OrderApi>();
  final _noteController = TextEditingController();
  final _idempotency = IdempotencyKeeper();

  late Future<CanteenInfo> _infoFuture;
  late Future<Quote> _quoteFuture;
  String? _voucherCode;
  PaymentMethod _method = PaymentMethod.cash;

  /// null = lấy ngay khi món xong.
  DateTime? _pickupTime;
  bool _placing = false;

  /// Lỗi của lần bấm "Đặt món" gần nhất — hiện NGAY TRÊN nút (SnackBar nổi sẽ che mất nút cần bấm lại).
  String? _placeError;

  @override
  void initState() {
    super.initState();
    // Future tạo ở initState (không tạo trong build).
    _infoFuture = _api.canteenInfo();
    _quoteFuture = _api.quote(_items, voucherCode: _voucherCode);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  List<CartItem> get _items => context.read<CartProvider>().items;

  void _requote() => setState(() {
    _quoteFuture = _api.quote(_items, voucherCode: _voucherCode);
  });

  void _reloadAll() => setState(() {
    _infoFuture = _api.canteenInfo();
    _quoteFuture = _api.quote(_items, voucherCode: _voucherCode);
  });

  Future<void> _chooseVoucher(int subtotal) async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => VoucherPickerScreen(subtotal: subtotal, current: _voucherCode),
      ),
    );
    if (code == null || !mounted) return;
    _voucherCode = code.isEmpty ? null : code;
    _requote();
  }

  /// Sửa nhanh một dòng lỗi ngay tại màn thanh toán.
  Future<void> _fixLine(LineError error) async {
    final cart = context.read<CartProvider>();
    if (error.index >= cart.items.length) return;
    final item = cart.items[error.index];
    final remaining = error.remaining ?? 0;
    if (error.code == LineError.soldOut && remaining > 0) {
      await cart.updateQuantity(item.id!, remaining);
    } else {
      await cart.remove(item.id!);
    }
    if (!mounted) return;
    if (cart.isEmpty) {
      Navigator.pop(context);
      return;
    }
    _requote();
  }

  /// Chuỗi mô tả toàn bộ nội dung đơn — đổi bất kỳ thứ gì thì Idempotency-Key mới.
  String get _signature => [
    for (final i in _items) '${i.foodId}:${i.quantity}:${i.optionsKey}:${i.note ?? ''}',
    _voucherCode ?? '',
    _method.name,
    _pickupTime?.toIso8601String() ?? 'asap',
    _noteController.text.trim(),
  ].join('|');

  Future<void> _placeOrder() async {
    final cart = context.read<CartProvider>();
    final orderDao = context.read<OrderDao>();
    final userId = context.read<AuthProvider>().user!.uid;
    final navigator = Navigator.of(context);
    setState(() {
      _placing = true;
      _placeError = null;
    });
    try {
      final order = await _api.createOrder(
        items: cart.items,
        paymentMethod: _method,
        idempotencyKey: _idempotency.keyFor(_signature),
        voucherCode: _voucherCode,
        pickupTime: _pickupTime,
        note: _noteController.text,
      );
      _idempotency.reset();
      // Lưu hóa đơn vào SQLite (xem lại khi offline), rồi dọn giỏ.
      await orderDao.upsertDetail(order, userId);
      await cart.clear();
      if (!mounted) return;
      final awaitingTransfer = order.payment?.awaitingTransfer ?? false;
      navigator.pushReplacementNamed(awaitingTransfer ? AppRoutes.payment : AppRoutes.orderPlaced, arguments: order);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _placing = false);
      if (e.isNetwork) {
        // GIỮ key: bấm lại sẽ không tạo đơn trùng nếu lần này máy chủ thực ra đã nhận đơn.
        setState(() => _placeError = '${e.message} Bấm "Đặt món" lần nữa — đơn sẽ không bị tạo trùng.');
        return;
      }
      _idempotency.reset();
      if (e.code == ApiErrorCodes.orderItemsInvalid) {
        setState(() => _placeError = 'Một vài món vừa thay đổi — kiểm tra lại các dòng tô đỏ.');
        _reloadAll();
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(Icons.info_outline_rounded, color: context.appColors.warning),
          title: const Text('Chưa đặt được món'),
          content: Text(e.message),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Đã hiểu'))],
        ),
      );
      if (mounted) _reloadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = context.watch<CartProvider>().items;
    return Scaffold(
      appBar: AppBar(title: const Text('Thanh toán')),
      body: items.isEmpty
          ? const EmptyState(icon: Icons.shopping_bag_outlined, title: 'Giỏ hàng đang trống')
          : FutureBuilder<CanteenInfo>(
              future: _infoFuture,
              builder: (context, infoSnap) => FutureBuilder<Quote>(
                future: _quoteFuture,
                builder: (context, quoteSnap) => _buildBody(context, items, infoSnap, quoteSnap),
              ),
            ),
    );
  }

  /// Xử lý đủ ConnectionState của hai Future: chờ lần đầu → skeleton; lỗi → thử lại;
  /// đang tải lại (đã có dữ liệu cũ) → giữ nội dung + thanh tiến trình mỏng.
  Widget _buildBody(
    BuildContext context,
    List<CartItem> items,
    AsyncSnapshot<CanteenInfo> infoSnap,
    AsyncSnapshot<Quote> quoteSnap,
  ) {
    final loading =
        infoSnap.connectionState == ConnectionState.waiting || quoteSnap.connectionState == ConnectionState.waiting;
    if (infoSnap.hasError || quoteSnap.hasError) {
      final error = (infoSnap.error ?? quoteSnap.error)!;
      if (!loading) return ErrorView(error: error, onRetry: _reloadAll);
    }
    final info = infoSnap.data;
    final quote = quoteSnap.data;
    if (info == null || quote == null) return const SkeletonList(itemCount: 5);

    final sections = _Sections(
      info: info,
      quote: quote,
      items: items,
      method: _method,
      pickupTime: _pickupTime,
      voucherCode: _voucherCode,
      noteController: _noteController,
      onMethod: (m) => setState(() => _method = m),
      onPickup: (t) => setState(() => _pickupTime = t),
      onVoucher: () => _chooseVoucher(quote.subtotal),
      onRemoveVoucher: () {
        _voucherCode = null;
        _requote();
      },
      onFixLine: _fixLine,
    );

    final canPlace = info.isOpen && quote.canOrder && !loading && !_placing;
    final bar = _PlaceOrderBar(
      total: quote.totalAmount,
      enabled: canPlace,
      busy: _placing,
      error: _placeError,
      hint: !info.isOpen
          ? 'Căn-tin đang đóng (mở ${info.hoursLabel})'
          : !quote.canOrder
          ? 'Sửa các món tô đỏ để đặt'
          : null,
      onPressed: _placeOrder,
    );

    return Column(
      children: [
        if (loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 840) {
                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    MaxWidthBox(child: sections.main(context)),
                    sections.summary(context),
                  ],
                );
              }
              // Màn rộng: chi tiết bên trái, tổng tiền + nút đặt bên phải.
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ListView(padding: const EdgeInsets.all(AppSpacing.md), children: [sections.main(context)]),
                  ),
                  SizedBox(
                    width: 360,
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      children: [
                        sections.summary(context),
                        const SizedBox(height: AppSpacing.md),
                        bar,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (MediaQuery.sizeOf(context).width < 840) bar,
      ],
    );
  }
}

/// Các khối nội dung của màn Thanh toán.
class _Sections {
  const _Sections({
    required this.info,
    required this.quote,
    required this.items,
    required this.method,
    required this.pickupTime,
    required this.voucherCode,
    required this.noteController,
    required this.onMethod,
    required this.onPickup,
    required this.onVoucher,
    required this.onRemoveVoucher,
    required this.onFixLine,
  });

  final CanteenInfo info;
  final Quote quote;
  final List<CartItem> items;
  final PaymentMethod method;
  final DateTime? pickupTime;
  final String? voucherCode;
  final TextEditingController noteController;
  final ValueChanged<PaymentMethod> onMethod;
  final ValueChanged<DateTime?> onPickup;
  final VoidCallback onVoucher;
  final VoidCallback onRemoveVoucher;
  final ValueChanged<LineError> onFixLine;

  Widget main(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!info.isOpen) ...[
          _Banner(
            icon: Icons.storefront_outlined,
            color: context.appColors.warning,
            text: 'Căn-tin đang đóng cửa. Nhận đơn từ ${info.hoursLabel} mỗi ngày.',
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Text('Món của bạn', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Card(
          child: Column(
            children: [
              for (final (i, line) in quote.lines.indexed) ...[
                if (i > 0) const Divider(indent: AppSpacing.md, endIndent: AppSpacing.md),
                _LineTile(line: line, error: quote.errorAt(line.index), onFix: onFixLine),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Mã giảm giá', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        _VoucherTile(check: quote.voucher, code: voucherCode, onChoose: onVoucher, onRemove: onRemoveVoucher),
        const SizedBox(height: AppSpacing.lg),
        Text('Giờ nhận món (hôm nay)', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        _PickupPicker(info: info, selected: pickupTime, onChanged: onPickup),
        const SizedBox(height: AppSpacing.lg),
        Text('Thanh toán', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        _PaymentOption(
          method: PaymentMethod.cash,
          selected: method == PaymentMethod.cash,
          icon: Icons.payments_outlined,
          subtitle: 'Trả khi nhận món tại quầy',
          onTap: () => onMethod(PaymentMethod.cash),
        ),
        const SizedBox(height: AppSpacing.xs),
        _PaymentOption(
          method: PaymentMethod.bankTransfer,
          selected: method == PaymentMethod.bankTransfer,
          icon: Icons.qr_code_2_rounded,
          subtitle: info.bankTransferEnabled
              ? 'Quét VietQR — căn-tin nấu ngay khi nhận tiền (trong ${info.unpaidTransferTimeoutMinutes} phút)'
              : 'Tạm thời chưa nhận chuyển khoản',
          onTap: info.bankTransferEnabled ? () => onMethod(PaymentMethod.bankTransfer) : null,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Ghi chú cho đơn', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: noteController,
          maxLength: 300,
          maxLines: 2,
          minLines: 1,
          decoration: const InputDecoration(hintText: 'VD: lấy thêm muỗng, đựng riêng nước chấm...'),
        ),
      ],
    );
  }

  Widget summary(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget row(String label, String value, {TextStyle? style}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: muted)),
          Text(value, style: (style ?? theme.textTheme.bodyMedium)?.tabular),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row('Tạm tính (${quote.totalItems} phần)', Money.format(quote.subtotal)),
            if (quote.discountAmount > 0)
              row(
                'Giảm giá${quote.voucher != null ? ' (${quote.voucher!.code})' : ''}',
                Money.signed(-quote.discountAmount),
                style: theme.textTheme.bodyMedium?.copyWith(color: context.appColors.success),
              ),
            const Divider(height: AppSpacing.lg),
            Row(
              children: [
                Text('Tổng cộng', style: theme.textTheme.titleSmall),
                const SizedBox(width: AppSpacing.md),
                // FittedBox: số tiền lớn luôn vừa khung, kể cả khi chữ hệ thống phóng to.
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      Money.format(quote.totalAmount),
                      style: theme.textTheme.headlineSmall?.tabular.copyWith(color: context.appColors.price),
                    ),
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

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppRadius.mdAll),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
        ),
      ],
    ),
  );
}

/// Một dòng đã báo giá; có lỗi → viền đỏ, câu lỗi, nút sửa nhanh.
class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.error, required this.onFix});

  final PricedLine line;
  final LineError? error;
  final ValueChanged<LineError> onFix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final red = context.appColors.cancelled;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final err = error;
    final canReduce = err != null && err.code == LineError.soldOut && (err.remaining ?? 0) > 0;

    return Container(
      decoration: err == null
          ? null
          : BoxDecoration(
              color: red.withValues(alpha: 0.06),
              border: Border(left: BorderSide(color: red, width: 3)),
            ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppNetworkImage(line.imageUrl, width: 48, height: 48, borderRadius: AppRadius.smAll),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${line.quantity} × ${line.foodName}', style: theme.textTheme.titleSmall),
                    if (line.options.isNotEmpty) Text(line.optionsText, style: muted),
                    if (line.note != null && line.note!.isNotEmpty)
                      Text('“${line.note}”', style: muted?.copyWith(fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(Money.format(line.lineTotal), style: theme.textTheme.bodyMedium?.tabular),
            ],
          ),
          if (err != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 18, color: red),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(err.message, style: theme.textTheme.bodySmall?.copyWith(color: red)),
                ),
                TextButton(
                  onPressed: () => onFix(err),
                  child: Text(canReduce ? 'Giảm còn ${err.remaining}' : 'Bỏ món'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _VoucherTile extends StatelessWidget {
  const _VoucherTile({required this.check, required this.code, required this.onChoose, required this.onRemove});

  final VoucherCheck? check;
  final String? code;
  final VoidCallback onChoose;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final c = check;
    final valid = c?.isValid ?? false;
    return Card(
      child: ListTile(
        onTap: onChoose,
        leading: Icon(Icons.local_offer_outlined, color: c == null ? null : (valid ? colors.success : colors.warning)),
        title: Text(code == null ? 'Chọn hoặc nhập mã' : code!),
        subtitle: c == null
            ? const Text('Xem các mã bạn đang dùng được')
            : Text(
                valid ? 'Giảm ${Money.format(c.discount)}' : c.message,
                style: TextStyle(color: valid ? colors.success : colors.warning),
              ),
        trailing: code == null
            ? const Icon(Icons.chevron_right_rounded)
            : IconButton(tooltip: 'Bỏ mã', icon: const Icon(Icons.close_rounded), onPressed: onRemove),
      ),
    );
  }
}

/// Chọn giờ nhận: "Sớm nhất" hoặc một mốc 15 phút (chạm chọn — không bắt gõ giờ).
class _PickupPicker extends StatelessWidget {
  const _PickupPicker({required this.info, required this.selected, required this.onChanged});

  final CanteenInfo info;
  final DateTime? selected;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final slots = info.isOpen ? info.pickupSlots() : const <DateTime>[];
    return SizedBox(
      height: kMinTapTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: slots.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, i) {
          if (i == 0) {
            return ChoiceChip(
              avatar: const Icon(Icons.bolt_rounded, size: 18),
              showCheckmark: false, // không đè dấu tích lên biểu tượng
              label: const Text('Sớm nhất'),
              selected: selected == null,
              onSelected: (_) => onChanged(null),
            );
          }
          final slot = slots[i - 1];
          return ChoiceChip(
            showCheckmark: false,
            label: Text(VnTime.time(slot)),
            selected: selected == slot,
            onSelected: (_) => onChanged(slot),
          );
        },
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({
    required this.method,
    required this.selected,
    required this.icon,
    required this.subtitle,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool selected;
  final IconData icon;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Material(
      color: selected ? context.appColors.subtleBrand : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: BorderSide(color: selected ? primary : theme.colorScheme.outlineVariant, width: selected ? 1.5 : 1),
      ),
      child: ListTile(
        enabled: onTap != null,
        onTap: onTap,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        leading: Icon(icon, color: selected ? primary : null),
        title: Text(method.label),
        subtitle: Text(subtitle),
        trailing: Icon(
          selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
          color: selected ? primary : null,
        ),
      ),
    );
  }
}

class _PlaceOrderBar extends StatelessWidget {
  const _PlaceOrderBar({
    required this.total,
    required this.enabled,
    required this.busy,
    required this.hint,
    this.error,
    required this.onPressed,
  });

  final int total;
  final bool enabled;
  final bool busy;
  final String? hint;
  final String? error;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      shadowColor: context.appColors.shadow,
      borderRadius: MediaQuery.sizeOf(context).width >= 840 ? AppRadius.lgAll : null,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 18, color: context.appColors.cancelled),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        error!,
                        style: theme.textTheme.bodySmall?.copyWith(color: context.appColors.cancelled),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              if (hint != null) ...[
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: context.appColors.warning),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              FilledButton(
                onPressed: enabled ? onPressed : null,
                child: busy
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(
                        'Đặt món · ${Money.format(total)}',
                        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
