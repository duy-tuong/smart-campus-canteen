import '../core/utils/vn_time.dart';

/// Danh mục món (GET /api/categories).
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.sortOrder,
    required this.isActive,
    required this.foodCount,
    this.description,
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        description: json['description'] as String?,
        icon: json['icon'] as String? ?? '',
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        isActive: json['isActive'] as bool? ?? true,
        foodCount: (json['foodCount'] as num?)?.toInt() ?? 0,
      );

  final int id;
  final String name;
  final String? description;

  /// Tên Material Icon (ví dụ "rice_bowl").
  final String icon;
  final int sortOrder;
  final bool isActive;
  final int foodCount;
}

/// Món trong danh sách (GET /api/foods).
class FoodSummary {
  const FoodSummary({
    required this.id,
    required this.name,
    required this.price,
    required this.categoryId,
    required this.categoryName,
    required this.prepTimeMinutes,
    required this.averageRating,
    required this.ratingCount,
    required this.isAvailable,
    required this.isSoldOut,
    required this.hasOptions,
    required this.isFavorite,
    this.imageUrl,
    this.remainingToday,
  });

  factory FoodSummary.fromJson(Map<String, dynamic> json) => FoodSummary(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        price: (json['price'] as num).toInt(),
        imageUrl: json['imageUrl'] as String?,
        categoryId: (json['categoryId'] as num).toInt(),
        categoryName: json['categoryName'] as String? ?? '',
        prepTimeMinutes: (json['prepTimeMinutes'] as num?)?.toInt() ?? 0,
        averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0,
        ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
        isAvailable: json['isAvailable'] as bool? ?? true,
        remainingToday: (json['remainingToday'] as num?)?.toInt(),
        isSoldOut: json['isSoldOut'] as bool? ?? false,
        hasOptions: json['hasOptions'] as bool? ?? false,
        isFavorite: json['isFavorite'] as bool? ?? false,
      );

  final int id;
  final String name;
  final int price;

  /// URL tuyệt đối, hoặc null → hiển thị ảnh thay thế.
  final String? imageUrl;
  final int categoryId;
  final String categoryName;
  final int prepTimeMinutes;
  final double averageRating;
  final int ratingCount;
  final bool isAvailable;

  /// Số suất còn lại hôm nay; null = không giới hạn.
  final int? remainingToday;
  final bool isSoldOut;
  final bool hasOptions;
  final bool isFavorite;

  FoodSummary copyWith({bool? isFavorite}) => FoodSummary(
        id: id,
        name: name,
        price: price,
        imageUrl: imageUrl,
        categoryId: categoryId,
        categoryName: categoryName,
        prepTimeMinutes: prepTimeMinutes,
        averageRating: averageRating,
        ratingCount: ratingCount,
        isAvailable: isAvailable,
        remainingToday: remainingToday,
        isSoldOut: isSoldOut,
        hasOptions: hasOptions,
        isFavorite: isFavorite ?? this.isFavorite,
      );
}

class FoodOption {
  const FoodOption({
    required this.id,
    required this.name,
    required this.extraPrice,
    required this.isAvailable,
    required this.sortOrder,
  });

  factory FoodOption.fromJson(Map<String, dynamic> json) => FoodOption(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        extraPrice: (json['extraPrice'] as num?)?.toInt() ?? 0,
        isAvailable: json['isAvailable'] as bool? ?? true,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );

  final int id;
  final String name;
  final int extraPrice;
  final bool isAvailable;
  final int sortOrder;
}

/// Nhóm tùy chọn: bắt buộc chọn trong khoảng [minSelect]–[maxSelect].
class FoodOptionGroup {
  const FoodOptionGroup({
    required this.id,
    required this.name,
    required this.isRequired,
    required this.minSelect,
    required this.maxSelect,
    required this.sortOrder,
    required this.options,
  });

  factory FoodOptionGroup.fromJson(Map<String, dynamic> json) => FoodOptionGroup(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        isRequired: json['isRequired'] as bool? ?? false,
        minSelect: (json['minSelect'] as num?)?.toInt() ?? 0,
        maxSelect: (json['maxSelect'] as num?)?.toInt() ?? 1,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        options: (json['options'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(FoodOption.fromJson)
            .toList(),
      );

  final int id;
  final String name;
  final bool isRequired;
  final int minSelect;
  final int maxSelect;
  final int sortOrder;
  final List<FoodOption> options;

  /// Chọn tối đa 1 → hiển thị dạng radio; nhiều hơn → checkbox.
  bool get isSingleChoice => maxSelect == 1;
}

/// Chi tiết món (GET /api/foods/{id}).
class FoodDetail {
  const FoodDetail({
    required this.summary,
    required this.description,
    required this.optionGroups,
    required this.rowVersion,
    required this.createdAt,
    required this.updatedAt,
    this.dailyLimit,
  });

  factory FoodDetail.fromJson(Map<String, dynamic> json) => FoodDetail(
        summary: FoodSummary.fromJson({...json, 'hasOptions': (json['optionGroups'] as List?)?.isNotEmpty ?? false}),
        description: json['description'] as String? ?? '',
        dailyLimit: (json['dailyLimit'] as num?)?.toInt(),
        optionGroups: (json['optionGroups'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(FoodOptionGroup.fromJson)
            .toList(),
        rowVersion: json['rowVersion'] as String? ?? '',
        createdAt: VnTime.parse(json['createdAt'] as String),
        updatedAt: VnTime.parse(json['updatedAt'] as String),
      );

  final FoodSummary summary;
  final String description;
  final int? dailyLimit;
  final List<FoodOptionGroup> optionGroups;

  /// Phiên bản bản ghi — gửi lại khi staff sửa món để phát hiện sửa đồng thời.
  final String rowVersion;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get id => summary.id;
  String get name => summary.name;
}
