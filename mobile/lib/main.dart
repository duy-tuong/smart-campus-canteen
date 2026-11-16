import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/local/cart_dao.dart';
import 'data/local/database_helper.dart';
import 'data/local/order_dao.dart';
import 'data/local/search_history_dao.dart';
import 'data/remote/api_client.dart';
import 'firebase_options.dart';
import 'providers/settings_provider.dart';

/// Điểm khởi chạy:
///  1. Firebase (Auth + Realtime Database)
///  2. Định dạng ngày giờ tiếng Việt
///  3. Cài đặt đã lưu (theme, địa chỉ máy chủ)
///  4. SQLite cục bộ + REST client
///  5. MultiProvider bọc toàn bộ app
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('vi');
  Intl.defaultLocale = 'vi';

  final settings = await SettingsProvider.load();
  final database = DatabaseHelper();
  final api = ApiClient(
    // Đọc địa chỉ mỗi lần gọi → đổi trong Cài đặt máy chủ có hiệu lực ngay.
    baseUrl: () => settings.apiBaseUrl,
    // ID token của Firebase (SDK tự làm mới khi sắp hết hạn).
    tokenProvider: () async => FirebaseAuth.instance.currentUser?.getIdToken(),
  );

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      Provider.value(value: api),
      Provider.value(value: database),
      Provider(create: (_) => CartDao(database)),
      Provider(create: (_) => OrderDao(database)),
      Provider(create: (_) => SearchHistoryDao(database)),
    ],
    child: const CanteenApp(),
  ));
}
