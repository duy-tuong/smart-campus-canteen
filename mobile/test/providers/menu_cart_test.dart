import 'package:campus_canteen/data/firebase/auth_service.dart';
import 'package:campus_canteen/data/local/cart_dao.dart';
import 'package:campus_canteen/data/local/database_helper.dart';
import 'package:campus_canteen/data/remote/api_exception.dart';
import 'package:campus_canteen/data/remote/menu_api.dart';
import 'package:campus_canteen/models/cart_item.dart';
import 'package:campus_canteen/models/menu.dart';
import 'package:campus_canteen/providers/cart_provider.dart';
import 'package:campus_canteen/providers/menu_provider.dart';
import 'package:campus_canteen/screens/menu/option_selection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fakes.dart';

void main() {
  group('MenuProvider', () {
    late FakeBackend backend;
    late MenuProvider menu;

    setUp(() {
      backend = FakeBackend();
      final auth = FakeAuthService(signedIn: const AuthUser(uid: 'uid-sv01'));
      menu = MenuProvider(MenuApi(backend.client(auth: auth)))..attachUser('uid-sv01');
    });

    test('tải danh mục + trang đầu; loadMore nối trang 2, hết trang thì dừng', () async {
      await menu.ensureLoaded();
      expect(menu.categories.map((c) => c.name), ['Cơm', 'Nước uống']);
      expect(menu.items, hasLength(20));
      expect(menu.hasNext, isTrue);

      await menu.loadMore();
      expect(menu.items, hasLength(25));
      expect(menu.hasNext, isFalse);
      expect(menu.items.map((f) => f.id).toSet(), hasLength(25), reason: 'không trùng món');

      final calls = backend.calls.length;
      await menu.loadMore();
      expect(backend.calls.length, calls, reason: 'hết trang thì không gọi API nữa');
    });

    test('đổi bộ lọc → tải lại từ trang 1; giữ nguyên bộ lọc thì không gọi lại', () async {
      await menu.ensureLoaded();
      await menu.updateQuery(menu.query.copyWith(categoryId: 3));
      expect(menu.items.every((f) => f.categoryId == 3), isTrue);
      expect(menu.query.categoryId, 3);

      final calls = backend.calls.length;
      await menu.updateQuery(menu.query.copyWith(categoryId: 3));
      expect(backend.calls.length, calls);

      await menu.updateQuery(menu.query.copyWith(categoryId: null));
      expect(menu.query.categoryId, isNull);
      expect(menu.items, hasLength(20));
    });

    test('kết quả của bộ lọc cũ về muộn bị bỏ qua', () async {
      await menu.ensureLoaded();
      backend.delay = const Duration(milliseconds: 40);
      final slow = menu.updateQuery(const FoodQuery(q: 'món số'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      backend.delay = Duration.zero;
      await menu.updateQuery(const FoodQuery(q: 'trà sữa'));
      await slow;
      expect(menu.items.map((f) => f.name), ['Trà sữa trân châu']);
    });

    test('yêu thích: đổi ngay trên giao diện; lỗi máy chủ → hoàn tác + ném lỗi', () async {
      await menu.ensureLoaded();
      final food = menu.items.first;
      expect(menu.isFavorite(food), isFalse);

      await menu.toggleFavorite(food);
      expect(menu.isFavorite(food), isTrue);
      expect(backend.favoriteIds, {food.id});

      backend.failFavorite = true;
      final pending = menu.toggleFavorite(food);
      expect(menu.isFavorite(food), isFalse, reason: 'lạc quan: đổi trước khi API trả lời');
      await expectLater(pending, throwsA(isA<ApiException>()));
      expect(menu.isFavorite(food), isTrue, reason: 'lỗi → hoàn tác');
    });

    test('đổi người dùng → xóa dữ liệu cũ', () async {
      await menu.ensureLoaded();
      await menu.toggleFavorite(menu.items.first);
      menu.attachUser('uid-khac');
      expect(menu.items, isEmpty);
      expect(menu.isLoaded, isFalse);
      expect(menu.isFavorite(FoodSummary.fromJson(FakeBackend.foodJson(1, 'x', 1))), isFalse);
    });

    test('mất mạng → error, giữ trạng thái chưa tải', () async {
      backend.offline = true;
      await menu.ensureLoaded();
      expect((menu.error as ApiException).isNetwork, isTrue);
      expect(menu.isLoaded, isFalse);
    });
  });

  group('CartProvider (SQLite thật qua sqflite_common_ffi)', () {
    sqfliteFfiInit();
    late DatabaseHelper helper;
    late CartProvider cart;

    final tea = FoodSummary.fromJson(FakeBackend.foodJson(2, 'Trà sữa trân châu', 25000, hasOptions: true));
    final rice = FoodSummary.fromJson(FakeBackend.foodJson(1, 'Cơm gà xối mỡ', 35000));
    const sizeL = CartItemOption(optionId: 21, groupName: 'Size', optionName: 'L', extraPrice: 6000);

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

    setUp(() async {
      helper = DatabaseHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      cart = CartProvider(CartDao(helper))..attachUser('u1');
      await settle();
    });
    tearDown(() => helper.close());

    test('thêm món, gộp dòng trùng, tính tổng', () async {
      await cart.addFood(tea, quantity: 2, options: const [sizeL]);
      await cart.addFood(tea, options: const [sizeL]);
      await cart.addFood(rice, note: '  Ít cơm ');

      expect(cart.items, hasLength(2));
      expect(cart.totalQuantity, 4);
      expect(cart.quantityOf(tea.id), 3);
      expect(cart.subtotal, (25000 + 6000) * 3 + 35000);
      expect(cart.items.last.note, 'Ít cơm');
    });

    test('giỏ còn nguyên khi "mở lại app" (provider mới, cùng CSDL) và tách theo người dùng', () async {
      await cart.addFood(rice, quantity: 2);

      final reopened = CartProvider(CartDao(helper))..attachUser('u1');
      await settle();
      expect(reopened.totalQuantity, 2);

      reopened.attachUser('u2');
      expect(reopened.items, isEmpty);
      await settle();
      expect(reopened.isLoaded, isTrue);
      expect(reopened.items, isEmpty);
    });

    test('xóa rồi hoàn tác; đổi số lượng; xóa sạch', () async {
      await cart.addFood(rice);
      await cart.addFood(tea, options: const [sizeL]);
      final removed = await cart.remove(cart.items.first.id!);
      expect(cart.items.map((i) => i.foodName), ['Trà sữa trân châu']);

      await cart.restore(removed!);
      expect(cart.items.map((i) => i.foodName), ['Cơm gà xối mỡ', 'Trà sữa trân châu'], reason: 'về đúng vị trí cũ');

      await cart.updateQuantity(cart.items.first.id!, 5);
      expect(cart.totalQuantity, 6);

      await cart.clear();
      expect(cart.isEmpty, isTrue);
    });
  });

  group('OptionSelection (quy tắc chọn tùy chọn)', () {
    FoodDetail detail(List<Map<String, Object?>> groups) => FoodDetail.fromJson({
      ...FakeBackend.foodJson(2, 'Trà sữa', 25000),
      'description': '',
      'optionGroups': groups,
      'rowVersion': 'A',
      'createdAt': '2026-11-01T00:00:00Z',
      'updatedAt': '2026-11-01T00:00:00Z',
    });

    Map<String, Object?> option(int id, String name, int extra, {bool available = true}) => {
      'id': id,
      'name': name,
      'extraPrice': extra,
      'isAvailable': available,
    };

    Map<String, Object?> group(
      int id,
      String name, {
      bool required = false,
      int min = 0,
      int max = 1,
      required List<Map<String, Object?>> options,
    }) => {'id': id, 'name': name, 'isRequired': required, 'minSelect': min, 'maxSelect': max, 'options': options};

    test('nhóm bắt buộc chọn 1: tự chọn sẵn mục miễn phí đầu tiên', () {
      final food = detail([
        group(1, 'Size', required: true, min: 1, options: [option(1, 'M', 0), option(2, 'L', 6000)]),
      ]);
      final s = OptionSelection(food);
      expect(s.isValid, isTrue);
      expect(s.selectedOptions.single.optionName, 'M');
      expect(s.unitPrice, 25000);

      s.toggle(food.optionGroups.single, food.optionGroups.single.options[1]);
      expect(s.selectedOptions.single.optionName, 'L');
      expect(s.unitPrice, 31000);

      s.toggle(food.optionGroups.single, food.optionGroups.single.options[1]);
      expect(s.selectedOptions.single.optionName, 'L', reason: 'nhóm bắt buộc: chạm lại không bỏ chọn');
    });

    test('nhóm bắt buộc mà mọi mục đều có phụ thu → KHÔNG chọn sẵn, nút Thêm báo thiếu', () {
      final food = detail([
        group(1, 'Size', required: true, min: 1, options: [option(1, 'L', 6000), option(2, 'XL', 9000)]),
      ]);
      final s = OptionSelection(food);
      expect(s.isValid, isFalse);
      expect(s.firstInvalid!.name, 'Size');
      expect(s.errorOf(food.optionGroups.single), 'Vui lòng chọn 1 mục');
    });

    test('nhóm chọn nhiều: tối đa maxSelect, mục hết hàng không chọn được', () {
      final food = detail([
        group(
          1,
          'Topping',
          max: 2,
          options: [
            option(1, 'A', 1000),
            option(2, 'B', 2000),
            option(3, 'C', 3000),
            option(4, 'D', 0, available: false),
          ],
        ),
      ]);
      final s = OptionSelection(food);
      final g = food.optionGroups.single;
      expect(s.isValid, isTrue, reason: 'không bắt buộc');

      s.toggle(g, g.options[0]);
      s.toggle(g, g.options[1]);
      expect(s.canSelect(g, g.options[2]), isFalse, reason: 'đã đủ 2');
      s.toggle(g, g.options[2]);
      expect(s.countIn(g), 2);
      expect(s.canSelect(g, g.options[3]), isFalse, reason: 'hết hàng');

      s.toggle(g, g.options[0]);
      expect(s.canSelect(g, g.options[2]), isTrue);
      expect(s.extraPrice, 2000);
      expect(OptionSelection.ruleOf(g), 'Không bắt buộc · tối đa 2');
    });

    test('nhóm không bắt buộc chọn 1: chạm lại để bỏ chọn', () {
      final food = detail([
        group(1, 'Đá', options: [option(1, 'Ít đá', 0)]),
      ]);
      final s = OptionSelection(food);
      final g = food.optionGroups.single;
      expect(s.countIn(g), 0, reason: 'không bắt buộc → không chọn sẵn');
      s.toggle(g, g.options.single);
      expect(s.countIn(g), 1);
      s.toggle(g, g.options.single);
      expect(s.countIn(g), 0);
    });

    test('nhóm bắt buộc chọn ít nhất 2', () {
      final food = detail([
        group(
          1,
          'Combo',
          required: true,
          min: 2,
          max: 3,
          options: [option(1, 'A', 0), option(2, 'B', 0), option(3, 'C', 0)],
        ),
      ]);
      final s = OptionSelection(food);
      final g = food.optionGroups.single;
      expect(s.errorOf(g), 'Chọn ít nhất 2 mục');
      s.toggle(g, g.options[0]);
      s.toggle(g, g.options[1]);
      expect(s.isValid, isTrue);
      expect(OptionSelection.ruleOf(g), 'Bắt buộc · chọn 2–3');
    });
  });
}
