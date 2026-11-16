import 'package:campus_canteen/providers/home_tabs.dart';
import 'package:campus_canteen/providers/menu_provider.dart';
import 'package:campus_canteen/screens/menu/favorites_screen.dart';
import 'package:campus_canteen/screens/menu/food_detail_screen.dart';
import 'package:campus_canteen/screens/menu/menu_screen.dart';
import 'package:campus_canteen/screens/menu/search_screen.dart';
import 'package:campus_canteen/widgets/food_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/app_harness.dart';

/// Luồng Thực đơn qua giao diện: lưới món, danh mục, thêm nhanh, chi tiết + tùy chọn, yêu thích, tìm kiếm.
void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.create());

  Future<void> pumpMenu(WidgetTester tester, {Size size = const Size(420, 1600)}) =>
      app.pump(tester, signedIn: AppHarness.student, size: size);

  Finder cardOf(String name) => find.ancestor(of: find.text(name), matching: find.byType(FoodCard));

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder.first);
    await tester.pump(); // ensureVisible chỉ đổi vị trí cuộn — cần một khung hình để bố cục lại
    await tester.tap(finder.first);
    await tester.pumpAndSettle();
  }

  /// Cho SnackBar hết hạn trước khi kết thúc test (không để Timer treo).
  Future<void> dismissSnackBars(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  int gridColumns(WidgetTester tester) {
    final grid = tester.widget<GridView>(find.descendant(of: find.byType(MenuScreen), matching: find.byType(GridView)));
    return (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisCount;
  }

  testWidgets('vào app → lưới món 2 cột (điện thoại), chip danh mục, nhãn hết món / còn ít suất', (tester) async {
    await pumpMenu(tester);
    expect(find.byType(MenuScreen), findsOneWidget);
    expect(find.text('Chào An, hôm nay ăn gì?'), findsOneWidget);
    expect(gridColumns(tester), 2);
    expect(find.text('Cơm gà xối mỡ'), findsOneWidget);
    expect(find.text('Còn 8 suất'), findsOneWidget);

    await tester.ensureVisible(find.text('Bánh flan'));
    expect(find.text('Hết món hôm nay'), findsOneWidget);
    final addFlan = find.descendant(of: cardOf('Bánh flan'), matching: find.byType(IconButton)).last;
    expect(tester.widget<IconButton>(addFlan).onPressed, isNull);
  });

  testWidgets('máy tính bảng: 800px → rail + 3 cột; 1300px → rail mở rộng + 4 cột', (tester) async {
    await pumpMenu(tester, size: const Size(800, 1000));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(gridColumns(tester), 3);

    await pumpMenu(tester, size: const Size(1300, 900));
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended, isTrue);
    expect(gridColumns(tester), 4, reason: '1300 − rail 220 ≈ 1080px → 4 cột');
  });

  testWidgets('chọn danh mục → chỉ hiện món của danh mục đó', (tester) async {
    await pumpMenu(tester);
    await tap(tester, find.widgetWithText(ChoiceChip, 'Nước uống'));
    expect(find.text('Trà sữa trân châu'), findsOneWidget);
    expect(find.text('Cơm gà xối mỡ'), findsNothing);

    await tap(tester, find.widgetWithText(ChoiceChip, 'Tất cả'));
    expect(find.text('Cơm gà xối mỡ'), findsOneWidget);
  });

  testWidgets('cuộn xuống cuối → tự tải trang 2 (cuộn vô hạn)', (tester) async {
    await pumpMenu(tester, size: const Size(420, 800));
    final menu = Provider.of<MenuProvider>(tester.element(find.byType(MenuScreen)), listen: false);
    expect(menu.items, hasLength(20));

    await tester.fling(find.byType(GridView), const Offset(0, -6000), 3000);
    await tester.pumpAndSettle();
    expect(menu.items, hasLength(25));
    expect(menu.hasNext, isFalse);
  });

  testWidgets('thêm nhanh món không tùy chọn → badge giỏ hàng + SnackBar "Xem giỏ" chuyển tab', (tester) async {
    await pumpMenu(tester);
    await tap(tester, find.descendant(of: cardOf('Món số 4'), matching: find.byTooltip('Thêm vào giỏ')));

    expect(find.text('Đã thêm Món số 4 vào giỏ'), findsOneWidget);
    expect(app.cartDao.rows.single.foodName, 'Món số 4');
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: cardOf('Món số 4'), matching: find.text('Trong giỏ: 1')), findsOneWidget);

    // SnackBar có nút hành động vẫn phải TỰ ẨN (không che nút Thanh toán của giỏ hàng).
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Đã thêm Món số 4 vào giỏ'), findsNothing);

    await tap(tester, find.descendant(of: cardOf('Món số 4'), matching: find.byTooltip('Thêm vào giỏ')));
    await tap(tester, find.text('Xem giỏ'));
    // MenuScreen giờ nằm ở tab ẩn (IndexedStack) → tìm cả widget offstage.
    final tabs = Provider.of<HomeTabs>(tester.element(find.byType(MenuScreen, skipOffstage: false)), listen: false);
    expect(tabs.index, HomeTabs.cart);
    await dismissSnackBars(tester);
  });

  testWidgets('chi tiết món: phải chọn Size mới thêm được; giá cập nhật theo tùy chọn và số lượng', (tester) async {
    await pumpMenu(tester);
    await tap(tester, find.text('Trà sữa trân châu'));
    expect(find.byType(FoodDetailScreen), findsOneWidget);
    expect(find.text('Mô tả món Trà sữa trân châu'), findsOneWidget);

    final addButton = find.byType(FilledButton).last;
    expect(find.text('Chọn Size'), findsOneWidget);
    expect(tester.widget<FilledButton>(addButton).onPressed, isNull);

    await tap(tester, find.text('L'));
    expect(find.text('Thêm vào giỏ · 31.000đ'), findsOneWidget);
    await tap(tester, find.text('Trân châu'));
    expect(find.text('Thêm vào giỏ · 36.000đ'), findsOneWidget);
    expect(find.text('Hết'), findsOneWidget, reason: 'Pudding hết hàng');

    await tap(tester, find.byTooltip('Tăng'));
    expect(find.text('Thêm vào giỏ · 72.000đ'), findsOneWidget);

    // Đánh giá hiển thị trong chi tiết
    expect(find.text('Rất ngon!'), findsOneWidget);
    expect(find.text('Cảm ơn bạn!'), findsOneWidget);

    await tap(tester, find.text('Thêm vào giỏ · 72.000đ'));
    expect(find.byType(FoodDetailScreen), findsNothing, reason: 'thêm xong quay về thực đơn');
    final row = app.cartDao.rows.single;
    expect(row.quantity, 2);
    expect(row.options.map((o) => o.optionName), ['L', 'Trân châu']);
    expect(row.lineTotal, 72000);
    expect(find.text('Đã thêm 2 × Trà sữa trân châu vào giỏ'), findsOneWidget);
    await dismissSnackBars(tester);
  });

  testWidgets('điện thoại xoay ngang: phần đầu thu gọn; chi tiết món ảnh trái / nội dung phải', (tester) async {
    await pumpMenu(tester, size: const Size(900, 420));
    expect(find.text('Tìm món: cơm gà, trà sữa...'), findsNothing, reason: 'ô tìm kiếm thành nút trên AppBar');
    expect(find.byTooltip('Tìm món'), findsOneWidget);
    final grid = find.descendant(of: find.byType(MenuScreen), matching: find.byType(GridView));
    expect(tester.getSize(grid).height, greaterThan(280), reason: 'lưới món có đủ chỗ');

    await tap(tester, find.text('Cơm gà xối mỡ'));
    expect(find.byType(FoodDetailScreen), findsOneWidget);
    expect(find.byType(SliverAppBar), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('yêu thích: đổi ngay, gọi API; xem trong màn Món yêu thích', (tester) async {
    await pumpMenu(tester);
    await tap(tester, find.descendant(of: cardOf('Cơm gà xối mỡ'), matching: find.byTooltip('Yêu thích')));
    expect(app.backend.favoriteIds, {1});
    expect(find.descendant(of: cardOf('Cơm gà xối mỡ'), matching: find.byTooltip('Bỏ yêu thích')), findsOneWidget);

    await tap(tester, find.byTooltip('Món yêu thích'));
    expect(find.byType(FavoritesScreen), findsOneWidget);
    expect(find.text('Cơm gà xối mỡ'), findsOneWidget);
  });

  testWidgets('yêu thích lỗi máy chủ → hoàn tác + báo lỗi', (tester) async {
    app.backend.failFavorite = true;
    await pumpMenu(tester);
    await tap(tester, find.descendant(of: cardOf('Cơm gà xối mỡ'), matching: find.byTooltip('Yêu thích')));

    expect(find.text('Máy chủ lỗi.'), findsOneWidget);
    expect(find.descendant(of: cardOf('Cơm gà xối mỡ'), matching: find.byTooltip('Yêu thích')), findsOneWidget);
    await dismissSnackBars(tester);
  });

  testWidgets('chưa có món yêu thích → trạng thái trống có nút quay lại thực đơn', (tester) async {
    await pumpMenu(tester);
    await tap(tester, find.byTooltip('Món yêu thích'));
    expect(find.text('Chưa có món yêu thích'), findsOneWidget);
    await tap(tester, find.text('Khám phá thực đơn'));
    expect(find.byType(FavoritesScreen), findsNothing);
  });

  testWidgets('tìm kiếm: gợi ý bán chạy → gõ (debounce) → kết quả → lưu lịch sử tìm kiếm', (tester) async {
    await pumpMenu(tester);
    await tap(tester, find.text('Tìm món: cơm gà, trà sữa...'));
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.text('Món bán chạy'), findsOneWidget);
    expect(find.text('Tìm gần đây'), findsNothing);

    await tester.enterText(find.byType(TextField), 'trà');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ListTile), findsNothing, reason: 'chưa đủ 400ms → chưa gọi API');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Trà sữa trân châu'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(await app.searchHistory.recent('uid-sv01'), ['trà']);

    await tap(tester, find.byTooltip('Xóa'));
    expect(find.text('Tìm gần đây'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'trà'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'xyz');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy “xyz”'), findsOneWidget);
  });

  testWidgets('lọc "chỉ món còn bán" qua bottom sheet → ẩn món hết', (tester) async {
    await pumpMenu(tester);
    await tap(tester, find.widgetWithText(ActionChip, 'Lọc'));
    await tap(tester, find.text('Chỉ món còn bán'));
    await tap(tester, find.text('Áp dụng'));
    expect(find.text('Bánh flan'), findsNothing);
    expect(find.text('1'), findsOneWidget, reason: 'badge số bộ lọc đang bật');
  });
}
