import '../../models/menu.dart';
import '../../models/paged_result.dart';
import '../../models/review.dart';
import 'api_client.dart';

/// Cách sắp xếp thực đơn (khớp tham số `sort` của GET /api/foods).
enum FoodSort {
  popular('popular', 'Bán chạy'),
  rating('rating', 'Đánh giá cao'),
  priceAsc('price_asc', 'Giá thấp → cao'),
  priceDesc('price_desc', 'Giá cao → thấp'),
  newest('newest', 'Món mới'),
  name('name', 'Tên A → Z');

  const FoodSort(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

/// Điều kiện lọc thực đơn. Bất biến — đổi bằng [copyWith].
class FoodQuery {
  const FoodQuery({
    this.q,
    this.categoryId,
    this.minPrice,
    this.maxPrice,
    this.availableOnly = false,
    this.sort = FoodSort.popular,
  });

  final String? q;
  final int? categoryId;
  final int? minPrice;
  final int? maxPrice;
  final bool availableOnly;
  final FoodSort sort;

  /// Số bộ lọc phụ đang bật (khoảng giá, chỉ món còn bán) — hiện trên nút Lọc.
  int get extraFilterCount => (minPrice != null || maxPrice != null ? 1 : 0) + (availableOnly ? 1 : 0);

  static const _keep = Object();

  /// Truyền `null` để XÓA một điều kiện (vd: `copyWith(categoryId: null)` = Tất cả danh mục).
  FoodQuery copyWith({
    Object? q = _keep,
    Object? categoryId = _keep,
    Object? minPrice = _keep,
    Object? maxPrice = _keep,
    bool? availableOnly,
    FoodSort? sort,
  }) => FoodQuery(
    q: identical(q, _keep) ? this.q : q as String?,
    categoryId: identical(categoryId, _keep) ? this.categoryId : categoryId as int?,
    minPrice: identical(minPrice, _keep) ? this.minPrice : minPrice as int?,
    maxPrice: identical(maxPrice, _keep) ? this.maxPrice : maxPrice as int?,
    availableOnly: availableOnly ?? this.availableOnly,
    sort: sort ?? this.sort,
  );

  Map<String, Object?> toQuery({required int page, required int pageSize}) => {
    'q': (q == null || q!.trim().isEmpty) ? null : q!.trim(),
    'categoryId': categoryId,
    'minPrice': minPrice,
    'maxPrice': maxPrice,
    'availableOnly': availableOnly ? true : null,
    'sort': sort.apiValue,
    'page': page,
    'pageSize': pageSize,
  };

  @override
  bool operator ==(Object other) =>
      other is FoodQuery &&
      other.q == q &&
      other.categoryId == categoryId &&
      other.minPrice == minPrice &&
      other.maxPrice == maxPrice &&
      other.availableOnly == availableOnly &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(q, categoryId, minPrice, maxPrice, availableOnly, sort);
}

/// Cách sắp xếp đánh giá (tham số `sort` của GET /api/foods/{id}/reviews).
enum ReviewSort {
  newest('newest', 'Mới nhất'),
  ratingDesc('rating_desc', 'Sao cao nhất'),
  ratingAsc('rating_asc', 'Sao thấp nhất');

  const ReviewSort(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

/// REST: thực đơn, chi tiết món, yêu thích, đánh giá.
class MenuApi {
  MenuApi(this._api);

  final ApiClient _api;

  static const pageSize = 20;

  Future<List<Category>> categories() async =>
      (await _api.get('/api/categories') as List).whereType<Map<String, dynamic>>().map(Category.fromJson).toList();

  Future<PagedResult<FoodSummary>> foods(FoodQuery query, {int page = 1, int pageSize = pageSize}) async =>
      PagedResult.fromJson(
        await _api.get(
              '/api/foods',
              query: query.toQuery(page: page, pageSize: pageSize),
            )
            as Map<String, dynamic>,
        FoodSummary.fromJson,
      );

  Future<FoodDetail> food(int id) async =>
      FoodDetail.fromJson(await _api.get('/api/foods/$id') as Map<String, dynamic>);

  Future<PagedResult<FoodSummary>> favorites({int page = 1, int pageSize = pageSize}) async => PagedResult.fromJson(
    await _api.get('/api/users/me/favorites', query: {'page': page, 'pageSize': pageSize}) as Map<String, dynamic>,
    FoodSummary.fromJson,
  );

  Future<void> setFavorite(int foodId, bool favorite) =>
      favorite ? _api.put('/api/foods/$foodId/favorite') : _api.delete('/api/foods/$foodId/favorite');

  Future<FoodReviewPage> reviews(
    int foodId, {
    int page = 1,
    int pageSize = 10,
    int? rating,
    ReviewSort sort = ReviewSort.newest,
  }) async => FoodReviewPage.fromJson(
    await _api.get(
          '/api/foods/$foodId/reviews',
          query: {'page': page, 'pageSize': pageSize, 'rating': rating, 'sort': sort.apiValue},
        )
        as Map<String, dynamic>,
  );
}
