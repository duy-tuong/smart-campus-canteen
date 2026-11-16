import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/money.dart';
import '../../core/utils/vn_time.dart';
import '../../data/remote/api_exception.dart';
import '../../data/remote/staff_api.dart';
import '../../models/checkout.dart';
import '../../models/voucher.dart';
import '../../widgets/state_views.dart';
import 'manage_hub_screen.dart';

/// Voucher: danh sách (tìm theo mã), bật/tắt, thêm / sửa, xóa (chỉ khi chưa đơn nào dùng).
class VouchersScreen extends StatefulWidget {
  const VouchersScreen({super.key});

  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen> {
  late final StaffApi _api = context.read<StaffApi>();
  List<AdminVoucher> _items = const [];
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
      final page = await _api.vouchers();
      if (mounted) setState(() => _items = page.items);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(int i, bool active) async {
    final v = _items[i];
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await _api.setVoucherActive(v.id, active);
      setState(() => _items = [..._items]..[i] = updated);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ErrorView.messageOf(e))));
    }
  }

  Future<void> _open([AdminVoucher? voucher]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => VoucherFormScreen(voucher: voucher)),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    return Scaffold(
      appBar: AppBar(title: const Text('Voucher')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tạo voucher'),
      ),
      body: _items.isEmpty
          ? (_loading
                ? const SkeletonList()
                : _error != null
                ? ErrorView(error: _error!, onRetry: _load)
                : EmptyState(
                    icon: Icons.local_offer_outlined,
                    title: 'Chưa có voucher',
                    actionLabel: 'Tạo voucher',
                    onAction: () => _open(),
                  ))
          : RefreshIndicator(
              onRefresh: _load,
              child: formWidth(
                ListView.builder(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 96),
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final v = _items[i];
                    final theme = Theme.of(context);
                    final colors = context.appColors;
                    final (state, color) = v.isExpired(now)
                        ? ('Hết hạn', colors.completed)
                        : v.isUpcoming(now)
                        ? ('Sắp diễn ra', colors.received)
                        : v.isActive
                        ? ('Đang chạy', colors.success)
                        : ('Đang tắt', colors.completed);
                    return Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: ListTile(
                        onTap: () => _open(v),
                        title: Row(
                          children: [
                            Text(v.code, style: theme.textTheme.titleSmall),
                            const SizedBox(width: AppSpacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: AppRadius.smAll,
                              ),
                              child: Text(state, style: theme.textTheme.labelSmall?.copyWith(color: color)),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          '${v.title}${v.minOrderAmount > 0 ? ' · đơn từ ${Money.format(v.minOrderAmount)}' : ''}\n'
                          '${VnTime.date(v.startAt)} → ${VnTime.date(v.endAt)} · đã dùng ${v.usedCount}${v.usageLimit != null ? '/${v.usageLimit}' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: Switch(value: v.isActive, onChanged: (a) => _toggle(i, a)),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}

/// Tạo / sửa voucher. Kiểm tra trên máy khớp backend: mã 3–30 chữ/số, % ≤ 100, "tối đa" chỉ cho %,
/// kết thúc sau bắt đầu. Chọn ngày giờ bằng DatePicker + TimePicker.
class VoucherFormScreen extends StatefulWidget {
  const VoucherFormScreen({super.key, this.voucher});

  final AdminVoucher? voucher;

  @override
  State<VoucherFormScreen> createState() => _VoucherFormScreenState();
}

class _VoucherFormScreenState extends State<VoucherFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final AdminVoucher? v = widget.voucher;
  late final _code = TextEditingController(text: v?.code);
  late final _description = TextEditingController(text: v?.description);
  late final _value = TextEditingController(text: v?.discountValue.toString());
  late final _maxDiscount = TextEditingController(text: v?.maxDiscount?.toString());
  late final _minOrder = TextEditingController(text: (v?.minOrderAmount ?? 0).toString());
  late final _usageLimit = TextEditingController(text: v?.usageLimit?.toString());
  late final _perUser = TextEditingController(text: (v?.perUserLimit ?? 1).toString());
  late DiscountType _type = v?.discountType ?? DiscountType.percent;
  late DateTime _start = v?.startAt ?? DateTime.now().toUtc();
  late DateTime _end = v?.endAt ?? DateTime.now().toUtc().add(const Duration(days: 7));
  late bool _active = v?.isActive ?? true;
  bool _saving = false;
  ApiException? _error;

  bool get _codeLocked => (v?.orderCount ?? 0) > 0;

  @override
  void dispose() {
    for (final c in [_code, _description, _value, _maxDiscount, _minOrder, _usageLimit, _perUser]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Chọn ngày + giờ (theo giờ Việt Nam), trả về UTC.
  Future<DateTime?> _pickDateTime(DateTime current) async {
    final local = VnTime.toVietnam(current);
    final date = await showDatePicker(
      context: context,
      initialDate: local,
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: local.hour, minute: local.minute),
    );
    if (time == null) return null;
    return DateTime.utc(date.year, date.month, date.day, time.hour, time.minute).subtract(VnTime.offset);
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await context.read<StaffApi>().saveVoucher({
        'code': _code.text.trim().toUpperCase(),
        'description': _description.text.trim(),
        'discountType': _type.name,
        'discountValue': int.parse(_value.text),
        'maxDiscount': _type == DiscountType.percent ? int.tryParse(_maxDiscount.text) : null,
        'minOrderAmount': int.tryParse(_minOrder.text) ?? 0,
        'startAt': _start.toIso8601String(),
        'endAt': _end.toIso8601String(),
        'usageLimit': int.tryParse(_usageLimit.text),
        'perUserLimit': int.tryParse(_perUser.text),
        'isActive': _active,
        'rowVersion': v?.rowVersion,
      }, id: v?.id);
      messenger.showSnackBar(SnackBar(content: Text('Đã lưu voucher ${_code.text.trim().toUpperCase()}.')));
      navigator.pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<StaffApi>().deleteVoucher(v!.id);
      messenger.showSnackBar(SnackBar(content: Text('Đã xóa ${v!.code}.')));
      navigator.pop(true);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String? _err(String field) => _error?.fieldError(field);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String? positive(String? s, {int min = 1, int max = 1000000}) {
      final n = int.tryParse(s ?? '');
      return n == null || n < min || n > max ? 'Từ $min đến $max.' : null;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(v == null ? 'Tạo voucher' : 'Sửa ${v!.code}'),
        actions: [
          if (v != null && v!.orderCount == 0)
            IconButton(tooltip: 'Xóa voucher', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
          child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Đang lưu...' : 'Lưu voucher')),
        ),
      ),
      body: SingleChildScrollView(
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
                if (_error != null && _error!.fieldErrors.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(_error!.message, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                TextFormField(
                  controller: _code,
                  enabled: !_codeLocked,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]'))],
                  decoration: InputDecoration(
                    labelText: 'Mã (VD: GIAM10)',
                    errorText: _err('code'),
                    helperText: _codeLocked ? 'Đã có ${v!.orderCount} đơn dùng mã — không đổi được.' : null,
                  ),
                  validator: (s) =>
                      RegExp(r'^[A-Za-z0-9]{3,30}$').hasMatch(s?.trim() ?? '') ? null : '3–30 chữ cái hoặc số.',
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _description,
                  maxLength: 300,
                  decoration: InputDecoration(labelText: 'Mô tả cho sinh viên', errorText: _err('description')),
                  validator: (s) => (s?.trim().length ?? 0) < 5 ? 'Mô tả dài từ 5 ký tự.' : null,
                ),
                SegmentedButton<DiscountType>(
                  segments: const [
                    ButtonSegment(
                      value: DiscountType.percent,
                      icon: Icon(Icons.percent_rounded),
                      label: Text('Theo %'),
                    ),
                    ButtonSegment(
                      value: DiscountType.fixed,
                      icon: Icon(Icons.payments_outlined),
                      label: Text('Số tiền'),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _value,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: _type == DiscountType.percent ? 'Giảm (%)' : 'Giảm (đ)',
                          errorText: _err('discountValue'),
                        ),
                        validator: (s) => _type == DiscountType.percent ? positive(s, max: 100) : positive(s),
                      ),
                    ),
                    if (_type == DiscountType.percent) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextFormField(
                          controller: _maxDiscount,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: 'Giảm tối đa (đ)'),
                          validator: (s) => (s == null || s.isEmpty) ? null : positive(s, min: 1000),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _minOrder,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Đơn tối thiểu (đ)'),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _DateTile(
                        label: 'Bắt đầu',
                        value: _start,
                        onTap: () async {
                          final d = await _pickDateTime(_start);
                          if (d != null) setState(() => _start = d);
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _DateTile(
                        label: 'Kết thúc',
                        value: _end,
                        error: _end.isAfter(_start) ? null : 'Phải sau thời gian bắt đầu',
                        onTap: () async {
                          final d = await _pickDateTime(_end);
                          if (d != null) setState(() => _end = d);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _usageLimit,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Tổng lượt (trống = ∞)'),
                        validator: (s) => (s == null || s.isEmpty) ? null : positive(s),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextFormField(
                        controller: _perUser,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Lượt / người (trống = ∞)'),
                        validator: (s) => (s == null || s.isEmpty) ? null : positive(s, max: 1000),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Đang bật'),
                  value: _active,
                  onChanged: (a) => setState(() => _active = a),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.label, required this.value, required this.onTap, this.error});

  final String label;
  final DateTime value;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: AppRadius.mdAll,
    child: InputDecorator(
      decoration: InputDecoration(labelText: label, errorText: error, suffixIcon: const Icon(Icons.event_rounded)),
      child: Text(VnTime.dateTime(value)),
    ),
  );
}
