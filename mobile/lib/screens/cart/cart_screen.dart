import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/money.dart';
import '../../models/cart_item.dart';
import '../../providers/cart_provider.dart';
import '../../providers/home_tabs.dart';
import '../../widgets/common.dart';
import '../../widgets/food_widgets.dart';
import '../../widgets/state_views.dart';

/// Tab Giỏ hàng — đọc từ SQLite (CartProvider). Vuốt để xóa (có Hoàn tác), sửa số lượng, ghi chú.
/// Màn rộng (≥ 840): danh sách bên trái, khung tổng tiền bên phải (LayoutBuilder).
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  Future<void> _confirmClear(BuildContext context) async {
    final cart = context.read<CartProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa hết giỏ hàng?'),
        content: Text('${cart.totalQuantity} phần món sẽ bị xóa khỏi giỏ.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Giữ lại')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa hết')),
        ],
      ),
    );
    if (ok == true) await cart.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(cart.isEmpty ? 'Giỏ hàng' : 'Giỏ hàng (${cart.totalQuantity})'),
        actions: [
          if (!cart.isEmpty)
            IconButton(
              tooltip: 'Xóa hết',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _confirmClear(context),
            ),
        ],
      ),
      body: !cart.isLoaded
          ? const SkeletonList()
          : cart.isEmpty
          ? EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Giỏ hàng đang trống',
              message: 'Chọn vài món ngon rồi đặt trước — đến quầy là có, không cần xếp hàng.',
              actionLabel: 'Xem thực đơn',
              onAction: () => context.read<HomeTabs>().select(HomeTabs.menu),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final list = _CartList(items: cart.items);
                if (constraints.maxWidth < 840) {
                  return Column(
                    children: [
                      Expanded(child: list),
                      _SummaryBar(cart: cart),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: list),
                    SizedBox(
                      width: 360,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Card(child: _SummaryBar(cart: cart, inCard: true)),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _CartList extends StatelessWidget {
  const _CartList({required this.items});

  final List<CartItem> items;

  Future<void> _remove(BuildContext context, CartItem item) async {
    final cart = context.read<CartProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final removed = await cart.remove(item.id!);
    if (removed == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Đã xóa ${removed.foodName}'),
          persist: false, // tự ẩn — không che nút Thanh toán
          action: SnackBarAction(label: 'Hoàn tác', onPressed: () => cart.restore(removed)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
      itemCount: items.length + 1,
      itemBuilder: (context, i) {
        if (i == items.length) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Vuốt sang trái để xóa món. Giá cuối cùng được căn-tin xác nhận ở bước Thanh toán.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          );
        }
        final item = items[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Dismissible(
            key: ValueKey('cart-${item.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              decoration: BoxDecoration(color: context.appColors.cancelled, borderRadius: AppRadius.lgAll),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline_rounded, color: Colors.white),
                  SizedBox(width: AppSpacing.xs),
                  Text(
                    'Xóa',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            onDismissed: (_) => _remove(context, item),
            child: CartItemCard(item: item, onRemove: () => _remove(context, item)),
          ),
        );
      },
    );
  }
}

/// Thẻ một dòng giỏ hàng: ảnh, tên, tùy chọn, ghi chú (chạm để sửa), giá dòng, số lượng.
class CartItemCard extends StatelessWidget {
  const CartItemCard({super.key, required this.item, required this.onRemove});

  final CartItem item;
  final VoidCallback onRemove;

  Future<void> _editNote(BuildContext context) async {
    final cart = context.read<CartProvider>();
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NoteSheet(initial: item.note ?? ''),
    );
    if (note != null && note.trim() != (item.note ?? '')) await cart.updateNote(item.id!, note);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppNetworkImage(item.imageUrl, width: 72, height: 72, borderRadius: AppRadius.mdAll),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.foodName, style: theme.textTheme.titleSmall),
                  if (item.options.isNotEmpty) ...[const SizedBox(height: 2), Text(item.optionsText, style: muted)],
                  InkWell(
                    onTap: () => _editNote(context),
                    borderRadius: AppRadius.smAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                      child: Row(
                        children: [
                          Icon(Icons.edit_note_rounded, size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: AppSpacing.xxs),
                          Flexible(
                            child: Text(
                              item.note ?? 'Thêm ghi chú',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: item.note == null
                                  ? theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)
                                  : theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      Expanded(child: PriceText(item.lineTotal)),
                      QuantityStepper(
                        compact: true,
                        value: item.quantity,
                        // Giảm từ 1 → hỏi xóa (nút − không bị khóa ở 1).
                        min: 0,
                        onChanged: (q) =>
                            q == 0 ? onRemove() : context.read<CartProvider>().updateQuantity(item.id!, q),
                      ),
                    ],
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

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.initial});

  final String initial;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.md,
      0,
      AppSpacing.md,
      AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Ghi chú cho món', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 200,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(hintText: 'VD: ít cay, không hành...'),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Lưu ghi chú'),
        ),
      ],
    ),
  );
}

/// Tạm tính + nút Thanh toán (dưới cùng — trong vùng ngón cái).
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.cart, this.inCard = false});

  final CartProvider cart;
  final bool inCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Tạm tính · ${cart.totalQuantity} phần', style: theme.textTheme.bodyMedium)),
              Text(
                Money.format(cart.subtotal),
                style: theme.textTheme.titleMedium?.tabular.copyWith(color: context.appColors.price),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.checkout),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Thanh toán'),
          ),
        ],
      ),
    );
    if (inCard) return content;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      shadowColor: context.appColors.shadow,
      child: SafeArea(top: false, child: content),
    );
  }
}
