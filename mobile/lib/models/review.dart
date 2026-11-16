import '../core/utils/vn_time.dart';
import 'paged_result.dart';

/// Một đánh giá món (tên tác giả đã rút gọn: "An N.").
class Review {
  const Review({
    required this.id,
    required this.foodId,
    required this.foodName,
    required this.orderId,
    required this.rating,
    required this.authorName,
    required this.isMine,
    required this.canEdit,
    required this.isHidden,
    required this.createdAt,
    required this.updatedAt,
    this.comment,
    this.hiddenReason,
    this.staffReply,
    this.repliedAt,
  });

  factory Review.fromJson(Map<String, dynamic> json) => Review(
    id: (json['id'] as num).toInt(),
    foodId: (json['foodId'] as num).toInt(),
    foodName: json['foodName'] as String? ?? '',
    orderId: json['orderId'] as String? ?? '',
    rating: (json['rating'] as num).toInt(),
    comment: json['comment'] as String?,
    authorName: json['authorName'] as String? ?? '',
    isMine: json['isMine'] as bool? ?? false,
    canEdit: json['canEdit'] as bool? ?? false,
    isHidden: json['isHidden'] as bool? ?? false,
    hiddenReason: json['hiddenReason'] as String?,
    staffReply: json['staffReply'] as String?,
    repliedAt: VnTime.tryParse(json['repliedAt'] as String?),
    createdAt: VnTime.parse(json['createdAt'] as String),
    updatedAt: VnTime.parse(json['updatedAt'] as String),
  );

  final int id;
  final int foodId;
  final String foodName;
  final String orderId;
  final int rating;
  final String? comment;
  final String authorName;
  final bool isMine;
  final bool canEdit;
  final bool isHidden;
  final String? hiddenReason;
  final String? staffReply;
  final DateTime? repliedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// Tổng quan đánh giá: điểm trung bình, số lượt, phân bố theo số sao.
class ReviewSummary {
  const ReviewSummary({required this.average, required this.count, required this.distribution});

  factory ReviewSummary.fromJson(Map<String, dynamic> json) {
    final raw = json['distribution'] as Map<String, dynamic>? ?? const {};
    return ReviewSummary(
      average: (json['average'] as num?)?.toDouble() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
      distribution: {for (var star = 1; star <= 5; star++) star: (raw['$star'] as num?)?.toInt() ?? 0},
    );
  }

  final double average;
  final int count;

  /// {5: 11, 4: 10, 3: 3, 2: 1, 1: 2}
  final Map<int, int> distribution;

  /// Tỉ lệ 0..1 của một mức sao (vẽ thanh phân bố).
  double ratio(int star) => count == 0 ? 0 : (distribution[star] ?? 0) / count;
}

/// GET /api/foods/{id}/reviews → { summary, reviews: PagedResult }.
class FoodReviewPage {
  const FoodReviewPage({required this.summary, required this.reviews});

  factory FoodReviewPage.fromJson(Map<String, dynamic> json) => FoodReviewPage(
    summary: ReviewSummary.fromJson(json['summary'] as Map<String, dynamic>? ?? const {}),
    reviews: PagedResult.fromJson(json['reviews'] as Map<String, dynamic>? ?? const {}, Review.fromJson),
  );

  final ReviewSummary summary;
  final PagedResult<Review> reviews;
}
