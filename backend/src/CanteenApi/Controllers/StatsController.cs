using CanteenApi.Auth;
using CanteenApi.Dtos.Statistics;
using CanteenApi.Services.Statistics;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CanteenApi.Controllers;

/// <summary>
/// Thống kê cho căn-tin (staff/admin). Khoảng ngày theo giờ Việt Nam (?from=yyyy-MM-dd&amp;to=yyyy-MM-dd),
/// bỏ trống = hôm nay, tối đa 366 ngày. Doanh thu = đơn đã HOÀN THÀNH, sau giảm giá.
/// </summary>
[ApiController]
[Route("api/stats")]
[Authorize(Policy = Policies.StaffOrAdmin)]
[Tags("Thống kê")]
public class StatsController(StatisticsService stats) : ControllerBase
{
    /// <summary>Tổng quan: doanh thu, số đơn, tỷ lệ hủy, giá trị đơn trung bình, theo phương thức thanh toán, so sánh kỳ trước.</summary>
    [HttpGet("overview")]
    public async Task<OverviewDto> Overview([FromQuery] StatsQuery query, CancellationToken ct) =>
        await stats.OverviewAsync(query, ct);

    /// <summary>Doanh thu theo ngày / tuần (bắt đầu thứ Hai) / tháng — kỳ không có đơn = 0.</summary>
    [HttpGet("revenue")]
    public async Task<RevenueSeriesDto> Revenue([FromQuery] RevenueQuery query, CancellationToken ct) =>
        await stats.RevenueAsync(query, ct);

    /// <summary>Món bán chạy theo số lượng hoặc doanh thu (gộp, trước giảm giá).</summary>
    [HttpGet("top-foods")]
    public async Task<IReadOnlyList<TopFoodDto>> TopFoods([FromQuery] TopFoodsQuery query, CancellationToken ct) =>
        await stats.TopFoodsAsync(query, ct);

    /// <summary>Giờ cao điểm: 24 cột theo giờ Việt Nam.</summary>
    [HttpGet("hourly")]
    public async Task<IReadOnlyList<HourlyStatDto>> Hourly([FromQuery] StatsQuery query, CancellationToken ct) =>
        await stats.HourlyAsync(query, ct);

    /// <summary>Tỷ trọng doanh thu theo danh mục (tổng = 100%).</summary>
    [HttpGet("categories")]
    public async Task<IReadOnlyList<CategoryStatDto>> Categories([FromQuery] StatsQuery query, CancellationToken ct) =>
        await stats.CategoriesAsync(query, ct);
}
