import 'dart:async';

import 'package:campus_canteen/app.dart';
import 'package:campus_canteen/core/responsive/responsive_shell.dart';
import 'package:campus_canteen/core/theme/app_theme.dart';
import 'package:campus_canteen/data/remote/api_client.dart';
import 'package:campus_canteen/data/remote/api_exception.dart';
import 'package:campus_canteen/models/enums.dart';
import 'package:campus_canteen/providers/settings_provider.dart';
import 'package:campus_canteen/widgets/async_value_view.dart';
import 'package:campus_canteen/widgets/common.dart';
import 'package:campus_canteen/widgets/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  void setScreen(WidgetTester tester, double width, [double height = 900]) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

  group('ResponsiveShell', () {
    Widget shell() => ResponsiveShell(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          destinations: const [
            ShellDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'A'),
            ShellDestination(icon: Icons.shopping_bag_outlined, selectedIcon: Icons.shopping_bag, label: 'B', badgeCount: 3),
          ],
          pages: const [Text('trang A'), Text('trang B')],
        );

    testWidgets('< 600px: thanh điều hướng dưới, có badge', (tester) async {
      setScreen(tester, 400);
      await tester.pumpWidget(wrap(shell()));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('600–1023px: NavigationRail thu gọn', (tester) async {
      setScreen(tester, 800);
      await tester.pumpWidget(wrap(shell()));
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended, isFalse);
    });

    testWidgets('điện thoại xoay ngang (thấp 360px, 5 mục): rail không bị tràn', (tester) async {
      setScreen(tester, 800, 360);
      await tester.pumpWidget(wrap(ResponsiveShell(
        selectedIndex: 0,
        onDestinationSelected: (_) {},
        railLeading: const Icon(Icons.lunch_dining, size: 32),
        destinations: [
          for (var i = 0; i < 5; i++) ShellDestination(icon: Icons.circle_outlined, selectedIcon: Icons.circle, label: 'Mục $i'),
        ],
        pages: [for (var i = 0; i < 5; i++) Text('trang $i')],
      )));
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('≥ 1024px: NavigationRail mở rộng', (tester) async {
      setScreen(tester, 1200);
      await tester.pumpWidget(wrap(shell()));
      expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended, isTrue);
    });
  });

  group('AsyncValueView', () {
    testWidgets('waiting → skeleton, done → dữ liệu', (tester) async {
      final completer = Completer<String>();
      await tester.pumpWidget(wrap(Scaffold(body: AsyncValueView<String>(future: completer.future, builder: (_, s) => Text(s)))));
      expect(find.byType(SkeletonList), findsOneWidget);

      completer.complete('Xong');
      await tester.pump();
      expect(find.text('Xong'), findsOneWidget);
    });

    testWidgets('lỗi mạng → ErrorView + nút Thử lại', (tester) async {
      var retried = false;
      final completer = Completer<String>();
      await tester.pumpWidget(wrap(Scaffold(
        body: AsyncValueView<String>(
          future: completer.future,
          builder: (_, s) => Text(s),
          onRetry: () => retried = true,
        ),
      )));
      completer.completeError(ApiException.network());
      await tester.pump();
      expect(find.text('Không có kết nối'), findsOneWidget);
      await tester.tap(find.text('Thử lại'));
      expect(retried, isTrue);
    });

    testWidgets('rỗng → trạng thái trống', (tester) async {
      await tester.pumpWidget(wrap(Scaffold(
        body: AsyncValueView<List<int>>(
          future: Future.value(const []),
          builder: (_, _) => const Text('có dữ liệu'),
          isEmpty: (list) => list.isEmpty,
          empty: const EmptyState(icon: Icons.receipt_long, title: 'Chưa có đơn nào'),
        ),
      )));
      await tester.pump();
      expect(find.text('Chưa có đơn nào'), findsOneWidget);
    });
  });

  testWidgets('StatusChip và PriceText hiển thị đúng', (tester) async {
    await tester.pumpWidget(wrap(const Scaffold(
      body: Column(children: [StatusChip(OrderStatus.ready), PriceText(35000, originalAmount: 40000)]),
    )));
    expect(find.text('Mời nhận món'), findsOneWidget);
    expect(find.text('35.000đ'), findsOneWidget);
    expect(find.text('40.000đ'), findsOneWidget);
  });

  group('App', () {
    late SettingsProvider settings;
    late ApiClient api;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = await SettingsProvider.load();
      api = ApiClient(
        baseUrl: () => settings.apiBaseUrl,
        httpClient: MockClient((request) async =>
            request.url.host == '192.168.1.10' ? http.Response('{"status":"ok"}', 200) : http.Response('', 503)),
      );
    });

    Widget app() => MultiProvider(
          providers: [ChangeNotifierProvider.value(value: settings), Provider.value(value: api)],
          child: const CanteenApp(),
        );

    testWidgets('đổi giao diện Tối ở tab Tài khoản và lưu lại', (tester) async {
      setScreen(tester, 400);
      await tester.pumpWidget(app());
      await tester.tap(find.text('Tài khoản'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tối'));
      await tester.pumpAndSettle();

      expect(settings.themeMode, ThemeMode.dark);
      expect(Theme.of(tester.element(find.text('Giao diện'))).brightness, Brightness.dark);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings.themeMode'), 'dark');
    });

    testWidgets('Cài đặt máy chủ: kiểm tra địa chỉ, kiểm tra kết nối, lưu', (tester) async {
      setScreen(tester, 400);
      await tester.pumpWidget(app());
      await tester.tap(find.text('Tài khoản'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Địa chỉ máy chủ'));
      await tester.pumpAndSettle();
      expect(find.text('Cài đặt máy chủ'), findsOneWidget);

      final field = find.byType(TextFormField);
      await tester.enterText(field, '192.168.1.10');
      await tester.tap(find.text('Kiểm tra kết nối'));
      await tester.pumpAndSettle();
      expect(find.text('Địa chỉ dạng http://192.168.1.10:5265'), findsOneWidget);

      await tester.enterText(field, 'http://192.168.1.10:5265/');
      await tester.tap(find.text('Kiểm tra kết nối'));
      await tester.pumpAndSettle();
      expect(find.text('Kết nối thành công'), findsOneWidget);

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(settings.apiBaseUrl, 'http://192.168.1.10:5265');
      expect(find.text('Cài đặt máy chủ'), findsNothing, reason: 'lưu xong quay lại');
      expect(find.text('http://192.168.1.10:5265'), findsOneWidget);
    });
  });
}
