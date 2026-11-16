import '../../models/cart_item.dart';
import '../../models/menu.dart';

/// Lựa chọn tùy chọn của một món — kiểm tra đúng quy tắc từng nhóm (minSelect–maxSelect)
/// GIỐNG backend, để nút "Thêm vào giỏ" chỉ bật khi hợp lệ.
class OptionSelection {
  OptionSelection(this.food) {
    // Chọn sẵn để giảm thao tác: nhóm chọn đúng 1, bắt buộc → mục đầu tiên còn bán và KHÔNG tính thêm tiền
    // (VD: Size M, Đường 100%). Không chọn sẵn mục có phụ thu.
    for (final group in food.optionGroups) {
      if (group.isSingleChoice && _minOf(group) >= 1) {
        final free = group.options.where((o) => o.isAvailable && o.extraPrice == 0).firstOrNull;
        if (free != null) _selected[group.id] = {free.id};
      }
    }
  }

  final FoodDetail food;
  final Map<int, Set<int>> _selected = {};

  /// Số mục tối thiểu phải chọn (nhóm "bắt buộc" mà minSelect = 0 vẫn phải chọn ít nhất 1).
  static int _minOf(FoodOptionGroup g) => g.isRequired && g.minSelect < 1 ? 1 : g.minSelect;

  bool isSelected(FoodOptionGroup group, FoodOption option) => _selected[group.id]?.contains(option.id) ?? false;

  int countIn(FoodOptionGroup group) => _selected[group.id]?.length ?? 0;

  /// Có chọn thêm được mục [option] không (nhóm nhiều lựa chọn đã đủ maxSelect → khóa các mục còn lại).
  bool canSelect(FoodOptionGroup group, FoodOption option) {
    if (!option.isAvailable) return false;
    if (group.isSingleChoice || isSelected(group, option)) return true;
    return countIn(group) < group.maxSelect;
  }

  /// Chạm vào một mục: nhóm chọn 1 → thay mục cũ (nhóm không bắt buộc thì chạm lại để bỏ chọn);
  /// nhóm chọn nhiều → bật/tắt.
  void toggle(FoodOptionGroup group, FoodOption option) {
    if (!canSelect(group, option)) return;
    final set = _selected.putIfAbsent(group.id, () => {});
    if (group.isSingleChoice) {
      final wasSelected = set.contains(option.id);
      set.clear();
      if (!wasSelected || _minOf(group) >= 1) set.add(option.id);
    } else if (!set.remove(option.id)) {
      set.add(option.id);
    }
  }

  /// Lỗi của một nhóm (null = hợp lệ) — hiện dưới tiêu đề nhóm.
  String? errorOf(FoodOptionGroup group) {
    final count = countIn(group);
    final min = _minOf(group);
    if (count < min) return min == 1 ? 'Vui lòng chọn 1 mục' : 'Chọn ít nhất $min mục';
    if (count > group.maxSelect) return 'Chọn tối đa ${group.maxSelect} mục';
    return null;
  }

  /// Mô tả quy tắc nhóm: "Bắt buộc · chọn 1", "Tùy chọn · tối đa 3".
  static String ruleOf(FoodOptionGroup g) {
    final min = _minOf(g);
    final required = min >= 1 ? 'Bắt buộc' : 'Không bắt buộc';
    if (g.isSingleChoice) return '$required · chọn 1';
    if (min > 1) return '$required · chọn $min–${g.maxSelect}';
    return '$required · tối đa ${g.maxSelect}';
  }

  /// Nhóm đầu tiên còn thiếu (để nút Thêm báo "Chọn Size").
  FoodOptionGroup? get firstInvalid => food.optionGroups.where((g) => errorOf(g) != null).firstOrNull;

  bool get isValid => firstInvalid == null;

  int get extraPrice => selectedOptions.fold(0, (sum, o) => sum + o.extraPrice);

  int get unitPrice => food.summary.price + extraPrice;

  /// Các tùy chọn đã chọn theo thứ tự nhóm (bản chụp tên + giá để lưu vào giỏ).
  List<CartItemOption> get selectedOptions => [
    for (final group in food.optionGroups)
      for (final option in group.options)
        if (isSelected(group, option))
          CartItemOption(
            optionId: option.id,
            groupName: group.name,
            optionName: option.name,
            extraPrice: option.extraPrice,
          ),
  ];
}
