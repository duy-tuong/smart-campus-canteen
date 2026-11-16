import 'package:campus_canteen/app.dart';
import 'package:campus_canteen/app_providers.dart';
import 'package:campus_canteen/data/firebase/auth_service.dart';
import 'package:campus_canteen/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_realtime.dart';
import 'fake_reviews.dart';
import 'fakes.dart';
import 'memory_daos.dart';

/// Dựng toàn bộ app (đúng danh sách provider như main.dart) với Firebase/backend/SQLite giả.
class AppHarness {
  AppHarness._(this.settings, this.backend);

  final SettingsProvider settings;
  final FakeBackend backend;
  late FakeAuthService auth;
  final cartDao = MemoryCartDao();
  final searchHistory = MemorySearchHistoryDao();
  final orderDao = MemoryOrderDao();
  final realtime = FakeRealtimeService();
  final images = FakeImageSource();

  static const student = AuthUser(uid: 'uid-sv01', email: 'sv01@smartcanteen.vn');

  /// Gọi trong setUp (ngoài vùng thời gian giả của testWidgets).
  static Future<AppHarness> create() async {
    SharedPreferences.setMockInitialValues({});
    final backend = FakeBackend()
      ..addProfile(profileJson())
      ..addProfile(
        profileJson(
          id: 'uid-staff',
          email: 'staff@smartcanteen.vn',
          fullName: 'Nhân viên',
          role: 'staff',
          studentCode: null,
        ),
      )
      ..addProfile(
        profileJson(
          id: 'uid-admin',
          email: 'admin@smartcanteen.vn',
          fullName: 'Quản trị',
          role: 'admin',
          studentCode: null,
        ),
      );
    return AppHarness._(await SettingsProvider.load(), backend);
  }

  Future<void> pump(WidgetTester tester, {AuthUser? signedIn, Size size = const Size(420, 1600)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    auth = FakeAuthService(signedIn: signedIn);
    await tester.pumpWidget(
      MultiProvider(
        providers: buildAppProviders(
          settings: settings,
          api: backend.client(auth: auth),
          auth: auth,
          realtime: realtime,
          images: images,
          cartDao: cartDao,
          orderDao: orderDao,
          searchHistoryDao: searchHistory,
        ),
        child: const CanteenApp(),
      ),
    );
    await tester.pumpAndSettle();
  }
}
