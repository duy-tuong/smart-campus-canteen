import 'package:flutter/material.dart';

import 'app.dart';

/// Điểm khởi chạy ứng dụng.
///
/// Các bước tiếp theo sẽ bổ sung tại đây:
///   1. `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`
///   2. Bọc [CanteenApp] trong `MultiProvider` (Auth, Theme, Menu, Cart, OrderHistory).
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CanteenApp());
}
