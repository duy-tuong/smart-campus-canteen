import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'app_providers.dart';
import 'data/local/cart_dao.dart';
import 'data/local/database_helper.dart';
import 'data/local/order_dao.dart';
import 'data/local/search_history_dao.dart';
import 'data/firebase/auth_service.dart';
import 'data/firebase/realtime_service.dart';
import 'data/remote/api_client.dart';
import 'firebase_options.dart';
import 'providers/settings_provider.dart';

/// Điểm khởi chạy:
///  1. Firebase (Auth + Realtime Database)
///  2. Định dạng ngày giờ tiếng Việt
///  3. Cài đặt đã lưu (theme, địa chỉ máy chủ)
///  4. Firebase Auth, SQLite cục bộ, REST client
///  5. MultiProvider bọc toàn bộ app
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('vi');
  Intl.defaultLocale = 'vi';

  final settings = await SettingsProvider.load();
  final database = DatabaseHelper();
  final AuthService authService = FirebaseAuthService(FirebaseAuth.instance);
  // Realtime Database: bật bộ nhớ đệm trên máy TRƯỚC lần đọc đầu tiên (mất mạng ngắn vẫn thấy trạng thái gần nhất).
  final rtdb = FirebaseDatabase.instance;
  FirebaseRealtimeService.enableOfflineCache(rtdb);
  final api = ApiClient(
    // Đọc địa chỉ mỗi lần gọi → đổi trong Cài đặt máy chủ có hiệu lực ngay.
    baseUrl: () => settings.apiBaseUrl,
    // ID token của Firebase (SDK tự làm mới khi sắp hết hạn).
    tokenProvider: authService.idToken,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: database),
        ...buildAppProviders(
          settings: settings,
          api: api,
          auth: authService,
          realtime: FirebaseRealtimeService(rtdb),
          cartDao: CartDao(database),
          orderDao: OrderDao(database),
          searchHistoryDao: SearchHistoryDao(database),
        ),
      ],
      child: const CanteenApp(),
    ),
  );
}
