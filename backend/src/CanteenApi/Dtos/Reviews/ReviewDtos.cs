using System.ComponentModel.DataAnnotations;
using CanteenApi.Common;

namespace CanteenApi.Dtos.Reviews;

// Quy ước: với record, attribute validate đặt trên THAM SỐ constructor.

/// <summary>Một đánh giá. Tên tác giả được rút gọn khi hiển thị công khai ("An N.").</summary>
public sealed record ReviewDto(
    int Id,
    int FoodId,
    string FoodName,
    string OrderId,
    byte Rating,
    string? Comment,
    string AuthorName,
    bool IsMine,
    /// <summary>Tác giả được sửa (còn trong hạn và chưa bị ẩn).</summary>
    bool CanEdit,
    bool IsHidden,
    /// <summary>Chỉ trả về cho tác giả và staff/admin.</summary>
    string? HiddenReason,
    string? StaffReply,
    DateTime? RepliedAt,
    DateTime CreatedAt,
    DateTime UpdatedAt);

/// <summary>Tổng quan đánh giá của một món.</summary>
public sealed record FoodReviewSummaryDto(
    int FoodId,
    decimal Average,
    int Count,
    /// <summary>Số đánh giá theo số sao: khóa "5", "4", ..., "1".</summary>
    IReadOnlyDictionary<string, int> Distribution);

public sealed record FoodReviewPageDto(FoodReviewSummaryDto Summary, PagedResult<ReviewDto> Reviews);

public sealed class FoodReviewQuery : PageQuery
{
    [Range(1, 5, ErrorMessage = "Số sao từ 1 đến 5.")]
    public int? Rating { get; set; }

    /// <summary>newest (mặc định) | rating_desc | rating_asc</summary>
    [RegularExpression("^(newest|rating_desc|rating_asc)$", ErrorMessage = "sort phải là: newest, rating_desc, rating_asc.")]
    public string Sort { get; set; } = "newest";
}

/// <summary>Một món trong đơn ở màn "Đánh giá đơn hàng".</summary>
public sealed record OrderReviewItemDto(
    int FoodId,
    string FoodName,
    string? ImageUrl,
    int Quantity,
    ReviewDto? MyReview);

public sealed record OrderReviewsDto(
    string OrderId,
    /// <summary>Đơn đã hoàn thành và còn trong hạn đánh giá.</summary>
    bool CanReview,
    DateTime? ReviewDeadline,
    IReadOnlyList<OrderReviewItemDto> Items);

public sealed record CreateReviewRequest(
    [Range(1, int.MaxValue, ErrorMessage = "Món không hợp lệ.")]
    int FoodId,

    [Range(1, 5, ErrorMessage = "Vui lòng chọn từ 1 đến 5 sao.")]
    int Rating,

    [StringLength(500, ErrorMessage = "Nhận xét tối đa 500 ký tự.")]
    string? Comment);

public sealed record UpdateReviewRequest(
    [Range(1, 5, ErrorMessage = "Vui lòng chọn từ 1 đến 5 sao.")]
    int Rating,

    [StringLength(500, ErrorMessage = "Nhận xét tối đa 500 ký tự.")]
    string? Comment);

/// <summary>Ẩn / hiện đánh giá (ẩn bắt buộc nêu lý do).</summary>
public sealed record ReviewVisibilityRequest(
    [Required(ErrorMessage = "Vui lòng cho biết isHidden (true/false).")]
    bool? IsHidden,

    [StringLength(300, ErrorMessage = "Lý do tối đa 300 ký tự.")]
    string? Reason);

public sealed record ReviewReplyRequest(
    [Required(ErrorMessage = "Vui lòng nhập nội dung trả lời.")]
    [StringLength(500, MinimumLength = 1, ErrorMessage = "Nội dung trả lời từ 1 đến 500 ký tự.")]
    string Reply);

/// <summary>Bộ lọc màn quản lý đánh giá.</summary>
public sealed class AdminReviewQuery : PageQuery
{
    [Range(1, int.MaxValue)]
    public int? FoodId { get; set; }

    [Range(1, 5, ErrorMessage = "Số sao từ 1 đến 5.")]
    public int? Rating { get; set; }

    public bool? IsHidden { get; set; }

    /// <summary>true = đã trả lời; false = chưa trả lời (cần xử lý).</summary>
    public bool? HasReply { get; set; }

    /// <summary>Tìm trong nội dung nhận xét (không phân biệt dấu).</summary>
    [StringLength(100)]
    public string? Q { get; set; }
}
