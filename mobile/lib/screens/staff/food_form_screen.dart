import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/device/image_source_service.dart';
import '../../data/remote/api_exception.dart';
import '../../data/remote/staff_api.dart';
import '../../models/menu.dart';
import '../../models/voucher.dart';
import '../../widgets/common.dart';
import '../../widgets/food_widgets.dart';
import '../../widgets/state_views.dart';
import 'manage_hub_screen.dart';

/// Thêm / sửa món. Trả về true (Navigator.pop) nếu đã lưu / xóa để danh sách tải lại.
class FoodFormScreen extends StatefulWidget {
  const FoodFormScreen({super.key, this.foodId, required this.categories});

  /// null = thêm món mới.
  final int? foodId;
  final List<Category> categories;

  @override
  State<FoodFormScreen> createState() => _FoodFormScreenState();
}

class _FoodFormScreenState extends State<FoodFormScreen> {
  late final StaffApi _api = context.read<StaffApi>();
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _prep = TextEditingController(text: '10');
  final _dailyLimit = TextEditingController();

  FoodDetail? _food;
  int? _categoryId;
  bool _available = true;
  bool _limitPerDay = false;
  List<OptionGroupDraft> _groups = [];
  bool _groupsDirty = false;
  PickedImage? _pendingImage;
  bool _loading = false;
  bool _saving = false;
  bool _uploading = false;
  Object? _loadError;
  ApiException? _error;
  bool _showGroupErrors = false;

  bool get _isNew => widget.foodId == null;

  @override
  void initState() {
    super.initState();
    if (_isNew) {
      _categoryId = widget.categories.where((c) => c.isActive).firstOrNull?.id ?? widget.categories.firstOrNull?.id;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _price, _prep, _dailyLimit]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      _fill(await _api.food(widget.foodId!));
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fill(FoodDetail f) {
    setState(() {
      _food = f;
      _name.text = f.name;
      _description.text = f.description;
      _price.text = '${f.summary.price}';
      _prep.text = '${f.summary.prepTimeMinutes}';
      _limitPerDay = f.dailyLimit != null;
      _dailyLimit.text = f.dailyLimit?.toString() ?? '';
      _categoryId = f.summary.categoryId;
      _available = f.summary.isAvailable;
      _groups = [
        for (final g in f.optionGroups)
          OptionGroupDraft(
            name: g.name,
            isRequired: g.isRequired,
            minSelect: g.minSelect,
            maxSelect: g.maxSelect,
            options: [
              for (final o in g.options)
                OptionDraft(name: o.name, extraPrice: o.extraPrice, isAvailable: o.isAvailable),
            ],
          ),
      ];
      _groupsDirty = false;
    });
  }

  FoodDraft get _draft => FoodDraft(
    categoryId: _categoryId!,
    name: _name.text,
    description: _description.text,
    price: int.parse(_price.text),
    prepTimeMinutes: int.parse(_prep.text),
    dailyLimit: _limitPerDay ? int.tryParse(_dailyLimit.text) : null,
    isAvailable: _available,
  );

  Future<void> _save() async {
    setState(() {
      _error = null;
      _showGroupErrors = true;
    });
    final formOk = _formKey.currentState!.validate();
    final groupsOk = _groups.every((g) => g.error == null);
    if (!formOk || !groupsOk) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      if (_isNew) {
        final created = await _api.createFood(_draft, _groups);
        if (_pendingImage != null) {
          await _api.uploadFoodImage(created.id, _pendingImage!.bytes, _pendingImage!.fileName);
        }
        messenger.showSnackBar(SnackBar(content: Text('Đã thêm "${created.name}" vào thực đơn.')));
      } else {
        var food = await _api.updateFood(_food!.id, _draft, _food!.rowVersion);
        if (_groupsDirty) food = await _api.replaceOptionGroups(food.id, _groups);
        messenger.showSnackBar(SnackBar(content: Text('Đã lưu "${food.name}".')));
      }
      navigator.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == ApiErrorCodes.concurrencyConflict) {
        setState(() => _saving = false); // tắt vòng xoay trước khi hỏi (không để quay mãi sau hộp thoại)
        await _askReload();
      } else {
        setState(() => _error = e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 409: người khác vừa sửa món → hỏi tải lại dữ liệu mới nhất (thay vì ghi đè âm thầm).
  Future<void> _askReload() async {
    final reload = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.sync_problem_rounded, color: context.appColors.warning),
        title: const Text('Món vừa được sửa ở máy khác'),
        content: const Text('Tải lại dữ liệu mới nhất? Thay đổi bạn vừa nhập sẽ mất.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ở lại')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tải lại')),
        ],
      ),
    );
    if (reload == true) await _load();
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<PickSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Chụp ảnh'),
              onTap: () => Navigator.pop(context, PickSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Chọn từ thư viện'),
              onTap: () => Navigator.pop(context, PickSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final image = await context.read<ImageSourceService>().pick(source);
      if (image == null) return;
      if (_isNew) {
        setState(() => _pendingImage = image); // tải lên sau khi tạo món
        return;
      }
      setState(() => _uploading = true);
      final updated = await _api.uploadFoodImage(_food!.id, image.bytes, image.fileName);
      setState(() => _food = updated);
      messenger.showSnackBar(const SnackBar(content: Text('Đã cập nhật ảnh món.')));
    } on PlatformException {
      messenger.showSnackBar(const SnackBar(content: Text('Không mở được camera / thư viện ảnh.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ErrorView.messageOf(e))));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xóa "${_food!.name}"?'),
        content: const Text('Món biến mất khỏi thực đơn. Hóa đơn cũ vẫn giữ tên và giá món.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Giữ lại')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa món')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteFood(_food!.id);
      messenger.showSnackBar(SnackBar(content: Text('Đã xóa "${_food!.name}".')));
      navigator.pop(true);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _changed(VoidCallback update) => setState(() {
    update();
    _groupsDirty = true;
  });

  String? _fieldError(String field) => _error?.fieldError(field);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Thêm món' : 'Sửa món'),
        actions: [
          if (!_isNew && _food != null)
            IconButton(tooltip: 'Xóa món', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
          child: FilledButton(
            onPressed: _saving || _loading || (!_isNew && _food == null) ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(_isNew ? 'Thêm vào thực đơn' : 'Lưu thay đổi'),
          ),
        ),
      ),
      body: _loading
          ? const SkeletonList(itemCount: 5)
          : _loadError != null
          ? ErrorView(error: _loadError!, onRetry: _load)
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: formWidth(
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ImageBox(
                        url: _food?.summary.imageUrl,
                        pending: _pendingImage,
                        uploading: _uploading,
                        onPick: _pickImage,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_error != null && _error!.fieldErrors.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Text(_error!.message, style: TextStyle(color: theme.colorScheme.error)),
                        ),
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(labelText: 'Tên món', errorText: _fieldError('name')),
                        validator: (v) {
                          final len = v?.trim().length ?? 0;
                          return len < 2 || len > 150 ? 'Tên món dài từ 2 đến 150 ký tự.' : null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<int>(
                        initialValue: _categoryId,
                        // Cùng cỡ chữ với các ô nhập khác (mặc định dropdown dùng cỡ tiêu đề).
                        style: theme.textTheme.bodyLarge,
                        decoration: const InputDecoration(labelText: 'Danh mục'),
                        items: [
                          for (final c in widget.categories)
                            DropdownMenuItem(
                              value: c.id,
                              child: Row(
                                children: [
                                  Icon(categoryIcon(c.icon), size: 20),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(c.isActive ? c.name : '${c.name} (ẩn)'),
                                ],
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                        validator: (v) => v == null ? 'Vui lòng chọn danh mục.' : null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _description,
                        maxLength: 500,
                        maxLines: 3,
                        minLines: 2,
                        decoration: InputDecoration(labelText: 'Mô tả', errorText: _fieldError('description')),
                        validator: (v) => (v?.trim().isEmpty ?? true) ? 'Vui lòng nhập mô tả.' : null,
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _price,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: InputDecoration(labelText: 'Giá (đ)', errorText: _fieldError('price')),
                              validator: (v) {
                                final p = int.tryParse(v ?? '');
                                return p == null || p < 1000 || p > 1000000 ? 'Từ 1.000đ đến 1.000.000đ.' : null;
                              },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: TextFormField(
                              controller: _prep,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(labelText: 'Chế biến (phút)'),
                              validator: (v) {
                                final m = int.tryParse(v ?? '');
                                return m == null || m > 180 ? 'Từ 0 đến 180 phút.' : null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Giới hạn số suất mỗi ngày'),
                        value: _limitPerDay,
                        onChanged: (v) => setState(() => _limitPerDay = v),
                      ),
                      if (_limitPerDay)
                        TextFormField(
                          controller: _dailyLimit,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: 'Số suất mỗi ngày'),
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            return n == null || n < 1 || n > 1000 ? 'Từ 1 đến 1000 suất.' : null;
                          },
                        ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Đang bán'),
                        subtitle: const Text('Tắt để tạm ngưng (món vẫn hiện, không đặt được)'),
                        value: _available,
                        onChanged: (v) => setState(() => _available = v),
                      ),
                      const Divider(height: AppSpacing.xl),
                      Row(
                        children: [
                          Expanded(child: Text('Nhóm tùy chọn', style: theme.textTheme.titleMedium)),
                          TextButton.icon(
                            onPressed: _groups.length >= 10
                                ? null
                                : () => _changed(() => _groups.add(OptionGroupDraft())),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Thêm nhóm'),
                          ),
                        ],
                      ),
                      Text(
                        'VD: Size (bắt buộc, chọn 1), Topping (tùy chọn, tối đa 3).',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final (i, g) in _groups.indexed) ...[
                        _OptionGroupEditor(
                          key: ObjectKey(g),
                          group: g,
                          showError: _showGroupErrors,
                          onChanged: _changed,
                          onRemove: () => _changed(() => _groups.removeAt(i)),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _ImageBox extends StatelessWidget {
  const _ImageBox({required this.url, required this.pending, required this.uploading, required this.onPick});

  final String? url;
  final PickedImage? pending;
  final bool uploading;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final image = pending != null
        ? Image.memory(pending!.bytes, fit: BoxFit.cover, errorBuilder: (_, _, _) => const AppNetworkImage(null))
        : AppNetworkImage(url);
    return ClipRRect(
      borderRadius: AppRadius.lgAll,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (uploading)
              const ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
            Positioned(
              right: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: FilledButton.tonalIcon(
                onPressed: uploading ? null : onPick,
                icon: const Icon(Icons.photo_camera_rounded),
                label: Text(url == null && pending == null ? 'Thêm ảnh' : 'Đổi ảnh'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sửa một nhóm tùy chọn: tên, bắt buộc, số chọn tối thiểu/tối đa, danh sách tùy chọn (tên, giá cộng thêm, còn/hết).
class _OptionGroupEditor extends StatelessWidget {
  const _OptionGroupEditor({
    super.key,
    required this.group,
    required this.showError,
    required this.onChanged,
    required this.onRemove,
  });

  final OptionGroupDraft group;
  final bool showError;
  final void Function(VoidCallback update) onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = showError ? group.error : null;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: BorderSide(color: error != null ? theme.colorScheme.error : theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: group.name,
                    decoration: const InputDecoration(labelText: 'Tên nhóm (VD: Size)'),
                    onChanged: (v) => onChanged(() => group.name = v),
                  ),
                ),
                IconButton(tooltip: 'Xóa nhóm', icon: const Icon(Icons.delete_outline_rounded), onPressed: onRemove),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Bắt buộc chọn'),
              value: group.isRequired,
              onChanged: (v) => onChanged(() {
                group.isRequired = v;
                if (v && group.minSelect < 1) group.minSelect = 1;
                if (!v) group.minSelect = 0;
              }),
            ),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Tối thiểu'),
                    const SizedBox(width: AppSpacing.xs),
                    QuantityStepper(
                      compact: true,
                      value: group.minSelect,
                      min: 0,
                      max: 20,
                      onChanged: (v) => onChanged(() => group.minSelect = v),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Tối đa'),
                    const SizedBox(width: AppSpacing.xs),
                    QuantityStepper(
                      compact: true,
                      value: group.maxSelect,
                      min: 1,
                      max: 20,
                      onChanged: (v) => onChanged(() => group.maxSelect = v),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final (i, option) in group.options.indexed)
              Padding(
                key: ObjectKey(option),
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        initialValue: option.name,
                        decoration: InputDecoration(labelText: 'Tùy chọn ${i + 1}'),
                        onChanged: (v) => onChanged(() => option.name = v),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: option.extraPrice == 0 ? '' : '${option.extraPrice}',
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: '+ giá (đ)'),
                        onChanged: (v) => onChanged(() => option.extraPrice = int.tryParse(v) ?? 0),
                      ),
                    ),
                    Checkbox(
                      semanticLabel: 'Còn',
                      value: option.isAvailable,
                      onChanged: (v) => onChanged(() => option.isAvailable = v ?? true),
                    ),
                    IconButton(
                      tooltip: 'Xóa tùy chọn',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: group.options.length <= 1 ? null : () => onChanged(() => group.options.removeAt(i)),
                    ),
                  ],
                ),
              ),
            // Wrap: màn hẹp / chữ lớn thì chú thích tự xuống dòng thay vì tràn.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: group.options.length >= 20
                      ? null
                      : () => onChanged(() => group.options.add(OptionDraft())),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Thêm tùy chọn'),
                ),
                Text('Ô tích = còn hàng', style: theme.textTheme.bodySmall),
              ],
            ),
            if (error != null) Text(error, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      ),
    );
  }
}
