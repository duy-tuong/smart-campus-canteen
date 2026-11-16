import '../core/utils/money.dart';
import '../core/utils/vn_time.dart';
import 'checkout.dart';

/// Voucher trong màn quản lý (staff/admin).
class AdminVoucher {
  const AdminVoucher({
    required this.id,
    required this.code,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.minOrderAmount,
    required this.startAt,
    required this.endAt,
    required this.usedCount,
    required this.isActive,
    required this.orderCount,
    required this.rowVersion,
    this.maxDiscount,
    this.usageLimit,
    this.perUserLimit,
  });

  factory AdminVoucher.fromJson(Map<String, dynamic> json) => AdminVoucher(
    id: (json['id'] as num).toInt(),
    code: json['code'] as String,
    description: json['description'] as String? ?? '',
    discountType: DiscountType.fromJson(json['discountType']),
    discountValue: (json['discountValue'] as num?)?.toInt() ?? 0,
    maxDiscount: (json['maxDiscount'] as num?)?.toInt(),
    minOrderAmount: (json['minOrderAmount'] as num?)?.toInt() ?? 0,
    startAt: VnTime.parse(json['startAt'] as String),
    endAt: VnTime.parse(json['endAt'] as String),
    usageLimit: (json['usageLimit'] as num?)?.toInt(),
    usedCount: (json['usedCount'] as num?)?.toInt() ?? 0,
    perUserLimit: (json['perUserLimit'] as num?)?.toInt(),
    isActive: json['isActive'] as bool? ?? true,
    orderCount: (json['orderCount'] as num?)?.toInt() ?? 0,
    rowVersion: json['rowVersion'] as String? ?? '',
  );

  final int id;
  final String code;
  final String description;
  final DiscountType discountType;
  final int discountValue;
  final int? maxDiscount;
  final int minOrderAmount;
  final DateTime startAt;
  final DateTime endAt;
  final int? usageLimit;
  final int usedCount;
  final int? perUserLimit;
  final bool isActive;

  /// Số đơn (kể cả đã hủy) từng dùng mã — > 0 thì không xóa / đổi mã được.
  final int orderCount;
  final String rowVersion;

  String get title => discountType == DiscountType.percent
      ? 'Giảm $discountValue%${maxDiscount != null ? ' (tối đa ${Money.format(maxDiscount!)})' : ''}'
      : 'Giảm ${Money.format(discountValue)}';

  bool isExpired(DateTime now) => !endAt.isAfter(now);
  bool isUpcoming(DateTime now) => startAt.isAfter(now);
}

/// Dữ liệu gửi khi tạo / sửa món (khớp CreateFoodRequest / UpdateFoodRequest).
class FoodDraft {
  const FoodDraft({
    required this.categoryId,
    required this.name,
    required this.description,
    required this.price,
    required this.prepTimeMinutes,
    required this.isAvailable,
    this.dailyLimit,
  });

  final int categoryId;
  final String name;
  final String description;
  final int price;
  final int prepTimeMinutes;
  final int? dailyLimit;
  final bool isAvailable;

  Map<String, Object?> toJson() => {
    'categoryId': categoryId,
    'name': name.trim(),
    'description': description.trim(),
    'price': price,
    'prepTimeMinutes': prepTimeMinutes,
    'dailyLimit': dailyLimit,
    'isAvailable': isAvailable,
  };
}

/// Một tùy chọn đang soạn trong trình sửa nhóm tùy chọn.
class OptionDraft {
  OptionDraft({this.name = '', this.extraPrice = 0, this.isAvailable = true});

  String name;
  int extraPrice;
  bool isAvailable;

  Map<String, Object?> toJson(int sortOrder) => {
    'name': name.trim(),
    'extraPrice': extraPrice,
    'isAvailable': isAvailable,
    'sortOrder': sortOrder,
  };
}

/// Một nhóm tùy chọn đang soạn (Size, Topping...).
class OptionGroupDraft {
  OptionGroupDraft({
    this.name = '',
    this.isRequired = false,
    this.minSelect = 0,
    this.maxSelect = 1,
    List<OptionDraft>? options,
  }) : options = options ?? [OptionDraft()];

  String name;
  bool isRequired;
  int minSelect;
  int maxSelect;
  final List<OptionDraft> options;

  /// Lỗi của nhóm (null = hợp lệ) — kiểm tra trước khi gửi, khớp quy tắc backend.
  String? get error {
    if (name.trim().isEmpty) return 'Nhập tên nhóm';
    if (options.isEmpty) return 'Cần ít nhất 1 tùy chọn';
    if (options.any((o) => o.name.trim().isEmpty)) return 'Tùy chọn chưa có tên';
    if (maxSelect < 1) return 'Số chọn tối đa ≥ 1';
    if (minSelect > maxSelect) return 'Tối thiểu không được lớn hơn tối đa';
    if (maxSelect > options.length) return 'Tối đa không được vượt số tùy chọn (${options.length})';
    if (isRequired && minSelect < 1) return 'Nhóm bắt buộc cần chọn ít nhất 1';
    return null;
  }

  Map<String, Object?> toJson(int sortOrder) => {
    'name': name.trim(),
    'isRequired': isRequired,
    'minSelect': minSelect,
    'maxSelect': maxSelect,
    'sortOrder': sortOrder,
    'options': [for (final (i, o) in options.indexed) o.toJson(i + 1)],
  };
}
