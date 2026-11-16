import 'package:flutter/foundation.dart';

/// Tab đang chọn của khung chính — để một màn đang mở chồng lên (VD: Chi tiết món)
/// chuyển được sang tab khác (nút "Xem giỏ" trên SnackBar).
class HomeTabs extends ChangeNotifier {
  static const menu = 0;
  static const cart = 1;
  static const orders = 2;
  static const notifications = 3;
  static const account = 4;

  int _index = menu;
  int get index => _index;

  void select(int index) {
    if (index == _index) return;
    _index = index;
    notifyListeners();
  }

  /// Về tab đầu (khi vào app với tài khoản mới) — không notify vì gọi trong lúc dựng khung.
  void reset() => _index = menu;
}
