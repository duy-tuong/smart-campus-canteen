using System.ComponentModel.DataAnnotations;
using CanteenApi.Models;

namespace CanteenApi.Dtos.Statistics;

/// <summary>
/// Khoảng thời gian thống kê theo NGÀY GIỜ VIỆT NAM (?from=2026-11-01&amp;to=2026-11-16).
/// Bỏ trống = hôm nay. Tối đa 366 ngày.
/// </summary>
public class StatsQuery : IValidatableObject
{
    public const int MaxDays = 366;

    public DateOnly? From { get; set; }
    public DateOnly? To { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext context)
    {
        if (From is { } from && To is { } to)
        {
            if (from > to)
                yield return new ValidationResult("Ngày bắt đầu phải trước hoặc bằng ngày kết thúc.", [nameof(From)]);
            else if (to.DayNumber - from.DayNumber + 1 > MaxDays)
                yield return new ValidationResult($"Khoảng thống kê tối đa {MaxDays} ngày.", [nameof(To)]);
        }
    }
}

public sealed class RevenueQuery : StatsQuery
{
    /// <summary>day (mặc định) | week (tuần bắt đầu thứ Hai) | month</summary>
    [RegularExpression("^(day|week|month)$", ErrorMessage = "groupBy phải là: day, week, month.")]
    public string GroupBy { get; set; } = "day";
}

public sealed class TopFoodsQuery : StatsQuery
{
    [Range(1, 50, ErrorMessage = "limit từ 1 đến 50.")]
    public int Limit { get; set; } = 10;

    /// <summary>quantity (mặc định) | revenue</summary>
    [RegularExpression("^(quantity|revenue)$", ErrorMessage = "sortBy phải là: quantity, revenue.")]
    public string SortBy { get; set; } = "quantity";
}

public sealed record PaymentMethodStatDto(PaymentMethod Method, int Orders, long Revenue);

/// <summary>Đơn đã thanh toán nhưng bị hủy → căn-tin cần hoàn tiền.</summary>
public sealed record RefundStatDto(int Orders, long Amount);

/// <summary>Kỳ trước có cùng độ dài, liền trước khoảng đang xem.</summary>
public sealed record PeriodComparisonDto(
    DateOnly From,
    DateOnly To,
    long Revenue,
    int CompletedOrders,
    /// <summary>% thay đổi doanh thu so với kỳ trước; null nếu kỳ trước không có doanh thu.</summary>
    double? RevenueChangePercent);

public sealed record OverviewDto(
    DateOnly From,
    DateOnly To,
    /// <summary>Tổng TotalAmount (sau giảm giá) của đơn đã hoàn thành.</summary>
    long Revenue,
    int CompletedOrders,
    int CancelledOrders,
    /// <summary>% đơn bị hủy trên tổng đơn đã kết thúc (hoàn thành + hủy).</summary>
    double CancelRate,
    long AverageOrderValue,
    int ItemsSold,
    long DiscountTotal,
    int UniqueCustomers,
    IReadOnlyList<PaymentMethodStatDto> ByPaymentMethod,
    RefundStatDto Refunds,
    PeriodComparisonDto Previous);

public sealed record RevenuePointDto(
    /// <summary>Ngày bắt đầu của kỳ (ngày / thứ Hai đầu tuần / ngày 1 của tháng).</summary>
    DateOnly Period,
    string Label,
    long Revenue,
    int Orders);

public sealed record RevenueSeriesDto(
    DateOnly From, DateOnly To, string GroupBy, long TotalRevenue, int TotalOrders, IReadOnlyList<RevenuePointDto> Points);

public sealed record TopFoodDto(
    int FoodId,
    string Name,
    string CategoryName,
    int Quantity,
    /// <summary>Doanh thu gộp của món (tổng LineTotal, TRƯỚC giảm giá theo đơn).</summary>
    long Revenue,
    decimal AverageRating,
    int RatingCount);

public sealed record HourlyStatDto(int Hour, int Orders, long Revenue);

public sealed record CategoryStatDto(
    int? CategoryId,
    string Name,
    int Quantity,
    /// <summary>Doanh thu gộp (tổng LineTotal, trước giảm giá theo đơn).</summary>
    long Revenue,
    /// <summary>Tỷ trọng doanh thu (%), tổng các danh mục = 100.</summary>
    double Percent);
