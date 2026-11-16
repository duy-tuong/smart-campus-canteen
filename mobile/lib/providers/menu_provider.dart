import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../data/remote/menu_api.dart';
import '../models/menu.dart';

/// Thực đơn: danh mục + danh sách món có lọc/sắp xếp/phân trang (cuộn vô hạn) + yêu thích.
class MenuProvider extends ChangeNotifier {
  MenuProvider(this._api);

  final MenuApi _api;

  String? _userId;
  List<Category> _categories = const [];
  FoodQuery _query = const FoodQuery();
  List<FoodSummary> _items = const [];
  int _page = 0;
  bool _hasNext = true;
  bool _loading = false;
  bool _loadingMore = false;
  bool _loaded = false;
  Object? _error;
  Object? _loadMoreError;

  /// Tăng mỗi lần đổi điều kiện lọc — kết quả của lượt tải cũ (gõ tìm kiếm nhanh) bị bỏ qua.
  int _generation = 0;

  /// Yêu thích đã đổi trên máy (cập nhật lạc quan) — áp lên mọi danh sách đang hiển thị.
  final Map<int, bool> _favorites = {};

  List<Category> get categories => _categories;
  FoodQuery get query => _query;
  List<FoodSummary> get items => _items;
  bool get hasNext => _hasNext;
  bool get isLoading => _loading;
  bool get isLoadingMore => _loadingMore;
  bool get isLoaded => _loaded;
  Object? get error => _error;
  Object? get loadMoreError => _loadMoreError;

  bool isFavorite(FoodSummary food) => _favorites[food.id] ?? food.isFavorite;

  /// Đổi người dùng (đăng xuất / tài khoản khác) → xóa dữ liệu cũ (yêu thích là của từng người).
  void attachUser(String? userId) {
    if (userId == _userId) return;
    _userId = userId;
    _generation++;
    _categories = const [];
    _query = const FoodQuery();
    _items = const [];
    _page = 0;
    _hasNext = true;
    _loading = _loadingMore = _loaded = false;
    _error = _loadMoreError = null;
    _favorites.clear();
  }

  /// Lần đầu mở màn Thực đơn.
  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    await refresh();
  }

  /// Tải lại từ trang 1 (kéo để làm mới / đổi bộ lọc). Danh mục được tải kèm nếu chưa có.
  Future<void> refresh() async {
    final generation = ++_generation;
    _loading = true;
    _error = null;
    _loadMoreError = null;
    notifyListeners();
    try {
      // Gọi song song. Future.wait ném lỗi GỐC đầu tiên và vẫn "bắt" lỗi của future còn lại
      // (await lần lượt từng future sẽ để lọt lỗi của future thứ hai thành lỗi không được xử lý).
      final categoriesFuture = _categories.isEmpty ? _api.categories() : Future.value(_categories);
      final pageFuture = _api.foods(_query, page: 1);
      await Future.wait([categoriesFuture, pageFuture]);
      final categories = await categoriesFuture;
      final page = await pageFuture;
      if (generation != _generation) return;
      _categories = categories.where((c) => c.isActive).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      _items = page.items;
      _page = 1;
      _hasNext = page.hasNext;
      _loaded = true;
    } catch (e) {
      if (generation != _generation) return;
      _error = e;
    } finally {
      if (generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Tải trang kế tiếp (ScrollController gọi khi cuộn gần cuối lưới).
  Future<void> loadMore() async {
    if (!_hasNext || _loading || _loadingMore || !_loaded) return;
    final generation = _generation;
    _loadingMore = true;
    _loadMoreError = null;
    notifyListeners();
    try {
      final page = await _api.foods(_query, page: _page + 1);
      if (generation != _generation) return;
      // Bỏ món trùng (thứ tự có thể xê dịch giữa hai lần gọi, VD sắp theo "bán chạy").
      final seen = _items.map((f) => f.id).toSet();
      _items = [..._items, ...page.items.where((f) => seen.add(f.id))];
      _page = page.page;
      _hasNext = page.hasNext;
    } catch (e) {
      if (generation == _generation) _loadMoreError = e;
    } finally {
      if (generation == _generation) {
        _loadingMore = false;
        notifyListeners();
      }
    }
  }

  /// Đổi điều kiện lọc → tải lại từ đầu.
  Future<void> updateQuery(FoodQuery query) async {
    if (query == _query) return;
    _query = query;
    await refresh();
  }

  /// Bật/tắt yêu thích: đổi giao diện NGAY, gọi API sau; lỗi thì hoàn tác và ném lỗi để màn hình báo.
  Future<void> toggleFavorite(FoodSummary food) async {
    final previous = isFavorite(food);
    _favorites[food.id] = !previous;
    notifyListeners();
    try {
      await _api.setFavorite(food.id, !previous);
    } catch (_) {
      _favorites[food.id] = previous;
      notifyListeners();
      rethrow;
    }
  }
}
