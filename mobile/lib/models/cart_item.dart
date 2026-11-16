/// Tùy chọn đã chọn của một món trong giỏ (bản chụp tên + giá lúc thêm vào giỏ).
class CartItemOption {
  const CartItemOption({
    required this.optionId,
    required this.groupName,
    required this.optionName,
    required this.extraPrice,
    this.id,
  });

  factory CartItemOption.fromMap(Map<String, Object?> map) => CartItemOption(
    id: map['id'] as int?,
    optionId: map['option_id'] as int,
    groupName: map['group_name'] as String,
    optionName: map['option_name'] as String,
    extraPrice: map['extra_price'] as int,
  );

  final int? id;
  final int optionId;
  final String groupName;
  final String optionName;
  final int extraPrice;

  Map<String, Object?> toMap(int cartItemId) => {
    'cart_item_id': cartItemId,
    'option_id': optionId,
    'group_name': groupName,
    'option_name': optionName,
    'extra_price': extraPrice,
  };
}

/// Một dòng trong giỏ hàng — lưu SQLite (bảng cart_items + cart_item_options) để giữ giỏ khi tắt app.
///
/// Giá ở đây chỉ để HIỂN THỊ tạm tính; khi đặt món server tự tính lại giá từ database.
class CartItem {
  const CartItem({
    required this.userId,
    required this.foodId,
    required this.foodName,
    required this.unitPrice,
    required this.quantity,
    required this.createdAt,
    this.options = const [],
    this.id,
    this.imageUrl,
    this.note,
  });

  factory CartItem.fromMap(Map<String, Object?> map, List<CartItemOption> options) => CartItem(
    id: map['id'] as int?,
    userId: map['user_id'] as String,
    foodId: map['food_id'] as int,
    foodName: map['food_name'] as String,
    imageUrl: map['image_url'] as String?,
    unitPrice: map['unit_price'] as int,
    quantity: map['quantity'] as int,
    // Lưu "" thay cho null để UNIQUE gộp được dòng không ghi chú (SQLite coi các NULL là khác nhau).
    note: (map['note'] as String?)?.isEmpty ?? true ? null : map['note'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int, isUtc: true),
    options: options,
  );

  final int? id;
  final String userId;
  final int foodId;
  final String foodName;
  final String? imageUrl;
  final int unitPrice;
  final int quantity;
  final String? note;
  final DateTime createdAt;
  final List<CartItemOption> options;

  /// Khóa nhận diện cấu hình tùy chọn ("12,15" — id đã sắp xếp). Hai dòng cùng món + cùng tùy chọn
  /// + cùng ghi chú được GỘP thành một (tăng số lượng) thay vì tạo dòng mới.
  String get optionsKey => (options.map((o) => o.optionId).toList()..sort()).join(',');

  int get optionsPrice => options.fold(0, (sum, o) => sum + o.extraPrice);

  int get lineTotal => (unitPrice + optionsPrice) * quantity;

  /// "Size L, Pudding trứng"
  String get optionsText => options.map((o) => o.optionName).join(', ');

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'user_id': userId,
    'food_id': foodId,
    'food_name': foodName,
    'image_url': imageUrl,
    'unit_price': unitPrice,
    'quantity': quantity,
    'note': note ?? '',
    'options_key': optionsKey,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  CartItem copyWith({int? id, int? quantity, String? note}) => CartItem(
    id: id ?? this.id,
    userId: userId,
    foodId: foodId,
    foodName: foodName,
    imageUrl: imageUrl,
    unitPrice: unitPrice,
    quantity: quantity ?? this.quantity,
    note: note ?? this.note,
    createdAt: createdAt,
    options: options,
  );
}
