import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/debouncer.dart';
import '../../data/remote/staff_api.dart';
import '../../models/menu.dart';
import '../../widgets/common.dart';
import '../../widgets/food_widgets.dart';
import '../../widgets/state_views.dart';
import 'food_form_screen.dart';

/// Quản lý thực đơn: mọi món (kể cả đang ẩn), lọc danh mục, tìm theo tên,
/// công tắc "Còn bán" đổi ngay (lạc quan, lỗi thì hoàn tác), chạm để sửa, nút + để thêm món.
class MenuManageScreen extends StatefulWidget {
  const MenuManageScreen({super.key});

  @override
  State<MenuManageScreen> createState() => _MenuManageScreenState();
}

class _MenuManageScreenState extends State<MenuManageScreen> {
  late final StaffApi _api = context.read<StaffApi>();
  final _search = TextEditingController();
  final _debouncer = Debouncer();
  List<Category> _categories = const [];
  List<FoodSummary> _foods = const [];
  int? _categoryId;
  bool _loading = true;
  Object? _error;
  final Set<int> _toggling = {};

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => _debouncer.run(_load));
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([_api.categories(), _api.foods(categoryId: _categoryId, q: _search.text)]);
      if (!mounted) return;
      setState(() {
        _categories = (results[0] as List<Category>)..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        _foods = (results[1] as dynamic).items as List<FoodSummary>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(int index, bool available) async {
    final food = _foods[index];
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _toggling.add(food.id);
      _foods = [..._foods]..[index] = _withAvailability(food, available);
    });
    try {
      await _api.setAvailability(food.id, available);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${food.name}: ${available ? 'mở bán lại' : 'tạm ngưng bán'}')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _foods = [..._foods]..[index] = food); // hoàn tác
      messenger.showSnackBar(SnackBar(content: Text(ErrorView.messageOf(e))));
    } finally {
      if (mounted) setState(() => _toggling.remove(food.id));
    }
  }

  static FoodSummary _withAvailability(FoodSummary f, bool available) => FoodSummary(
    id: f.id,
    name: f.name,
    price: f.price,
    imageUrl: f.imageUrl,
    categoryId: f.categoryId,
    categoryName: f.categoryName,
    prepTimeMinutes: f.prepTimeMinutes,
    averageRating: f.averageRating,
    ratingCount: f.ratingCount,
    isAvailable: available,
    isSoldOut: f.isSoldOut,
    hasOptions: f.hasOptions,
    isFavorite: f.isFavorite,
    remainingToday: f.remainingToday,
  );

  Future<void> _open({int? foodId}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FoodFormScreen(foodId: foodId, categories: _categories),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thực đơn')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _categories.isEmpty ? null : () => _open(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Thêm món'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xs),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(hintText: 'Tìm món theo tên', prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
          SizedBox(
            height: kMinTapTarget,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: AppSpacing.pagePadding,
              children: [
                for (final (id, label) in [
                  (null, 'Tất cả'),
                  for (final c in _categories) (c.id, c.isActive ? c.name : '${c.name} (ẩn)'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: ChoiceChip(
                      showCheckmark: false,
                      label: Text(label),
                      selected: _categoryId == id,
                      onSelected: (_) {
                        setState(() => _categoryId = id);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_loading && _foods.isNotEmpty) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_foods.isEmpty) {
      if (_loading) return const SkeletonList();
      if (_error != null) return ErrorView(error: _error!, onRetry: _load);
      return const EmptyState(icon: Icons.no_food_outlined, title: 'Không có món nào');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: MaxWidthBox(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(0, AppSpacing.xs, 0, 96),
          itemCount: _foods.length,
          separatorBuilder: (_, _) => const Divider(indent: 88),
          itemBuilder: (context, i) {
            final food = _foods[i];
            final theme = Theme.of(context);
            return ListTile(
              onTap: () => _open(foodId: food.id),
              leading: AppNetworkImage(food.imageUrl, width: 56, height: 56, borderRadius: AppRadius.mdAll),
              title: Text(
                food.name,
                style: food.isAvailable ? null : TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              subtitle: Row(
                children: [
                  PriceText(food.price, style: theme.textTheme.bodySmall),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      [
                        food.categoryName,
                        if (food.isSoldOut) 'hết suất hôm nay',
                        if (food.remainingToday != null && !food.isSoldOut) 'còn ${food.remainingToday}',
                      ].join(' · '),
                      overflow: TextOverflow.ellipsis,
                      style: food.isSoldOut ? TextStyle(color: context.appColors.cancelled) : null,
                    ),
                  ),
                ],
              ),
              trailing: Switch(
                value: food.isAvailable,
                onChanged: _toggling.contains(food.id) ? null : (v) => _toggle(i, v),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Biểu tượng danh mục có thể chọn trong form (tên Material Icon lưu ở backend).
const kCategoryIcons = [
  'rice_bowl',
  'ramen_dining',
  'local_drink',
  'local_cafe',
  'bakery_dining',
  'icecream',
  'cake',
  'fastfood',
  'lunch_dining',
  'set_meal',
  'soup_kitchen',
  'local_pizza',
];

/// Ô chọn biểu tượng danh mục.
class CategoryIconPicker extends StatelessWidget {
  const CategoryIconPicker({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.xs,
    runSpacing: AppSpacing.xs,
    children: [
      for (final name in kCategoryIcons)
        ChoiceChip(
          showCheckmark: false,
          tooltip: name,
          label: Icon(categoryIcon(name), size: 22),
          selected: value == name,
          onSelected: (_) => onChanged(name),
        ),
    ],
  );
}
