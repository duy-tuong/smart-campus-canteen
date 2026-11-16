import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../data/remote/api_exception.dart';
import '../../data/remote/staff_api.dart';
import '../../models/menu.dart';
import '../../widgets/food_widgets.dart';
import '../../widgets/state_views.dart';
import 'manage_hub_screen.dart';
import 'menu_manage_screen.dart';

/// Danh mục: kéo-thả để sắp xếp (ReorderableListView → PUT /api/categories/order),
/// thêm / sửa (tên, mô tả, biểu tượng, hiển thị), xóa (chặn nếu còn món — 409 CATEGORY_NOT_EMPTY).
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late final StaffApi _api = context.read<StaffApi>();
  List<Category> _items = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.categories();
      if (mounted) setState(() => _items = list..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final previous = _items;
    final list = [..._items];
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved); // onReorderItem đã trừ sẵn vị trí của mục vừa nhấc ra
    setState(() => _items = list); // đổi ngay trên màn hình
    try {
      final saved = await _api.reorderCategories([for (final c in list) c.id]);
      if (mounted) setState(() => _items = saved..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _items = previous);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ErrorView.messageOf(e))));
    }
  }

  Future<void> _edit([Category? category]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CategorySheet(api: _api, category: category, nextSortOrder: _items.length + 1),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(Category c) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xóa danh mục "${c.name}"?'),
        content: const Text('Chỉ xóa được danh mục không còn món nào.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Giữ lại')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteCategory(c.id);
      messenger.showSnackBar(SnackBar(content: Text('Đã xóa "${c.name}".')));
      await _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Danh mục')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Thêm danh mục'),
      ),
      body: _items.isEmpty
          ? (_loading
                ? const SkeletonList()
                : _error != null
                ? ErrorView(error: _error!, onRetry: _load)
                : const EmptyState(icon: Icons.category_outlined, title: 'Chưa có danh mục'))
          : formWidth(
              ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(0, AppSpacing.xs, 0, 96),
                header: Padding(
                  padding: AppSpacing.pagePadding,
                  child: Text(
                    'Giữ và kéo biểu tượng ≡ để đổi thứ tự hiển thị trên thực đơn.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                itemCount: _items.length,
                onReorderItem: _reorder,
                itemBuilder: (context, i) {
                  final c = _items[i];
                  return ListTile(
                    key: ValueKey(c.id),
                    onTap: () => _edit(c),
                    leading: Icon(categoryIcon(c.icon)),
                    title: Text(c.isActive ? c.name : '${c.name} (đang ẩn)'),
                    subtitle: Text('${c.foodCount} món'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Xóa ${c.name}',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _delete(c),
                        ),
                        ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle_rounded)),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.api, required this.nextSortOrder, this.category});

  final StaffApi api;
  final Category? category;
  final int nextSortOrder;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.category?.name);
  late final _description = TextEditingController(text: widget.category?.description);
  late String _icon = widget.category?.icon.isNotEmpty == true ? widget.category!.icon : kCategoryIcons.first;
  late bool _active = widget.category?.isActive ?? true;
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.saveCategory(
        id: widget.category?.id,
        name: _name.text,
        description: _description.text,
        icon: _icon,
        sortOrder: widget.category?.sortOrder ?? widget.nextSortOrder,
        isActive: _active,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.md,
      0,
      AppSpacing.md,
      AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.category == null ? 'Thêm danh mục' : 'Sửa danh mục',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Tên danh mục',
              errorText: _error?.fieldError('name') ?? (_error?.code == 'CATEGORY_NAME_TAKEN' ? _error!.message : null),
            ),
            validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Tên dài từ 2 đến 100 ký tự.' : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _description,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Mô tả (không bắt buộc)'),
          ),
          Text('Biểu tượng', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          CategoryIconPicker(value: _icon, onChanged: (v) => setState(() => _icon = v)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hiển thị trên thực đơn'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          if (_error != null && _error!.code != 'CATEGORY_NAME_TAKEN' && _error!.fieldErrors.isEmpty)
            Text(_error!.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Đang lưu...' : 'Lưu')),
        ],
      ),
    ),
  );
}
