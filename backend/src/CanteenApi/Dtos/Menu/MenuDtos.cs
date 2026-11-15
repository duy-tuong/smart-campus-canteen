using System.ComponentModel.DataAnnotations;
using CanteenApi.Common;

namespace CanteenApi.Dtos.Menu;

// Quy ước: với record, attribute validate đặt trên THAM SỐ constructor.

// ============================ Danh mục ============================

public sealed record CategoryDto(
    int Id,
    string Name,
    string? Description,
    string Icon,
    int SortOrder,
    bool IsActive,
    /// <summary>Số món (chưa xóa) trong danh mục.</summary>
    int FoodCount);

/// <summary>Tạo / sửa danh mục.</summary>
public sealed record SaveCategoryRequest(
    [Required(ErrorMessage = "Vui lòng nhập tên danh mục.")]
    [StringLength(100, MinimumLength = 2, ErrorMessage = "Tên danh mục dài từ 2 đến 100 ký tự.")]
    string Name,

    [StringLength(300, ErrorMessage = "Mô tả tối đa 300 ký tự.")]
    string? Description,

    /// <summary>Tên Material Icon, ví dụ "rice_bowl".</summary>
    [Required(ErrorMessage = "Vui lòng chọn biểu tượng.")]
    [RegularExpression("^[a-z0-9_]{1,50}$", ErrorMessage = "Biểu tượng là tên Material Icon (chữ thường, số, gạch dưới).")]
    string Icon,

    [Range(0, 1000, ErrorMessage = "Thứ tự hiển thị từ 0 đến 1000.")]
    int SortOrder,

    /// <summary>Mặc định true. false = tạm ẩn khỏi menu của sinh viên.</summary>
    bool? IsActive);

public sealed record CategoryOrderItem(
    [Range(1, int.MaxValue, ErrorMessage = "Id danh mục không hợp lệ.")] int Id,
    [Range(0, 1000, ErrorMessage = "Thứ tự hiển thị từ 0 đến 1000.")] int SortOrder);

/// <summary>Sắp xếp lại thứ tự nhiều danh mục một lần (kéo-thả trên app).</summary>
public sealed record ReorderCategoriesRequest(
    [Required, MinLength(1, ErrorMessage = "Danh sách sắp xếp không được rỗng.")]
    List<CategoryOrderItem> Items);

// ============================ Món ăn ============================

public sealed record FoodSummaryDto(
    int Id,
    string Name,
    int Price,
    string? ImageUrl,
    int CategoryId,
    string CategoryName,
    int PrepTimeMinutes,
    decimal AverageRating,
    int RatingCount,
    bool IsAvailable,
    /// <summary>Số suất còn lại hôm nay; null nếu món không giới hạn suất.</summary>
    int? RemainingToday,
    /// <summary>true nếu tạm hết món hoặc đã bán hết suất hôm nay.</summary>
    bool IsSoldOut,
    bool HasOptions,
    bool IsFavorite);

public sealed record FoodOptionDto(int Id, string Name, int ExtraPrice, bool IsAvailable, int SortOrder);

public sealed record FoodOptionGroupDto(
    int Id,
    string Name,
    bool IsRequired,
    int MinSelect,
    int MaxSelect,
    int SortOrder,
    IReadOnlyList<FoodOptionDto> Options);

public sealed record FoodDetailDto(
    int Id,
    string Name,
    string Description,
    int Price,
    string? ImageUrl,
    int CategoryId,
    string CategoryName,
    int PrepTimeMinutes,
    int? DailyLimit,
    decimal AverageRating,
    int RatingCount,
    bool IsAvailable,
    int? RemainingToday,
    bool IsSoldOut,
    bool IsFavorite,
    IReadOnlyList<FoodOptionGroupDto> OptionGroups,
    /// <summary>Phiên bản bản ghi (base64). Gửi lại khi sửa món để phát hiện sửa đồng thời.</summary>
    string RowVersion,
    DateTime CreatedAt,
    DateTime UpdatedAt);

/// <summary>Bộ lọc danh sách món.</summary>
public sealed class FoodQuery : PageQuery, IValidatableObject
{
    public const string SortPattern = "^(popular|price_asc|price_desc|rating|newest|name)$";

    [Range(1, int.MaxValue, ErrorMessage = "Id danh mục không hợp lệ.")]
    public int? CategoryId { get; set; }

    /// <summary>Từ khóa tìm theo tên/mô tả, không phân biệt dấu ("com ga" → "Cơm gà").</summary>
    [StringLength(100, ErrorMessage = "Từ khóa tối đa 100 ký tự.")]
    public string? Q { get; set; }

    [Range(0, 10_000_000, ErrorMessage = "Giá không hợp lệ.")]
    public int? MinPrice { get; set; }

    [Range(0, 10_000_000, ErrorMessage = "Giá không hợp lệ.")]
    public int? MaxPrice { get; set; }

    /// <summary>true = chỉ món còn bán được (chưa hết món, còn suất hôm nay).</summary>
    public bool AvailableOnly { get; set; }

    /// <summary>popular (bán chạy 30 ngày) | price_asc | price_desc | rating | newest | name.</summary>
    [RegularExpression(SortPattern, ErrorMessage = "sort phải là: popular, price_asc, price_desc, rating, newest, name.")]
    public string Sort { get; set; } = "name";

    /// <summary>Chỉ staff/admin: hiện cả món thuộc danh mục đang ẩn.</summary>
    public bool IncludeInactive { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        if (MinPrice is { } min && MaxPrice is { } max && min > max)
            yield return new ValidationResult("Giá thấp nhất phải nhỏ hơn hoặc bằng giá cao nhất.", [nameof(MinPrice)]);
    }
}

public sealed record SaveOptionRequest(
    [Required(ErrorMessage = "Vui lòng nhập tên tùy chọn.")]
    [StringLength(100, MinimumLength = 1, ErrorMessage = "Tên tùy chọn tối đa 100 ký tự.")]
    string Name,

    [Range(0, 200_000, ErrorMessage = "Giá cộng thêm từ 0 đến 200.000đ.")]
    int ExtraPrice,

    bool? IsAvailable,
    int? SortOrder);

public sealed record SaveOptionGroupRequest(
    [Required(ErrorMessage = "Vui lòng nhập tên nhóm tùy chọn.")]
    [StringLength(50, MinimumLength = 1, ErrorMessage = "Tên nhóm tối đa 50 ký tự.")]
    string Name,

    bool IsRequired,

    [Range(0, 20, ErrorMessage = "Số lựa chọn tối thiểu từ 0 đến 20.")]
    int MinSelect,

    [Range(1, 20, ErrorMessage = "Số lựa chọn tối đa từ 1 đến 20.")]
    int MaxSelect,

    int? SortOrder,

    [Required, MinLength(1, ErrorMessage = "Mỗi nhóm cần ít nhất 1 tùy chọn.")]
    [MaxLength(20, ErrorMessage = "Mỗi nhóm tối đa 20 tùy chọn.")]
    List<SaveOptionRequest> Options);

public sealed record CreateFoodRequest(
    [Range(1, int.MaxValue, ErrorMessage = "Vui lòng chọn danh mục.")]
    int CategoryId,

    [Required(ErrorMessage = "Vui lòng nhập tên món.")]
    [StringLength(150, MinimumLength = 2, ErrorMessage = "Tên món dài từ 2 đến 150 ký tự.")]
    string Name,

    [Required(ErrorMessage = "Vui lòng nhập mô tả.")]
    [StringLength(500, ErrorMessage = "Mô tả tối đa 500 ký tự.")]
    string Description,

    [Range(1_000, 1_000_000, ErrorMessage = "Giá từ 1.000đ đến 1.000.000đ.")]
    int Price,

    [Range(0, 180, ErrorMessage = "Thời gian chế biến từ 0 đến 180 phút.")]
    int PrepTimeMinutes,

    [Range(1, 1000, ErrorMessage = "Số suất mỗi ngày từ 1 đến 1000 (để trống nếu không giới hạn).")]
    int? DailyLimit,

    bool? IsAvailable,

    [MaxLength(10, ErrorMessage = "Mỗi món tối đa 10 nhóm tùy chọn.")]
    List<SaveOptionGroupRequest>? OptionGroups);

public sealed record UpdateFoodRequest(
    [Range(1, int.MaxValue, ErrorMessage = "Vui lòng chọn danh mục.")]
    int CategoryId,

    [Required(ErrorMessage = "Vui lòng nhập tên món.")]
    [StringLength(150, MinimumLength = 2, ErrorMessage = "Tên món dài từ 2 đến 150 ký tự.")]
    string Name,

    [Required(ErrorMessage = "Vui lòng nhập mô tả.")]
    [StringLength(500, ErrorMessage = "Mô tả tối đa 500 ký tự.")]
    string Description,

    [Range(1_000, 1_000_000, ErrorMessage = "Giá từ 1.000đ đến 1.000.000đ.")]
    int Price,

    [Range(0, 180, ErrorMessage = "Thời gian chế biến từ 0 đến 180 phút.")]
    int PrepTimeMinutes,

    [Range(1, 1000, ErrorMessage = "Số suất mỗi ngày từ 1 đến 1000 (để trống nếu không giới hạn).")]
    int? DailyLimit,

    [Required(ErrorMessage = "Vui lòng cho biết trạng thái isAvailable.")]
    bool? IsAvailable,

    /// <summary>rowVersion nhận được khi đọc chi tiết món.</summary>
    [Required(ErrorMessage = "Thiếu rowVersion (lấy từ chi tiết món).")]
    string RowVersion);

/// <summary>Thay toàn bộ nhóm tùy chọn của món (danh sách rỗng = bỏ hết tùy chọn).</summary>
public sealed record ReplaceOptionGroupsRequest(
    [Required]
    [MaxLength(10, ErrorMessage = "Mỗi món tối đa 10 nhóm tùy chọn.")]
    List<SaveOptionGroupRequest> Groups);

public sealed record UpdateAvailabilityRequest(
    [Required(ErrorMessage = "Vui lòng cho biết trạng thái isAvailable.")]
    bool? IsAvailable);
