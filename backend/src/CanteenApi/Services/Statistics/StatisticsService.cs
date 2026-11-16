using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Dtos.Statistics;
using CanteenApi.Models;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Services.Statistics;

/// <summary>
/// Thống kê cho căn-tin (staff/admin). Định nghĩa số liệu:
///  - Doanh thu = tổng TotalAmount (SAU giảm giá) của đơn đã HOÀN THÀNH; đơn hủy/hoàn tiền không tính.
///  - Ngày = ngày theo giờ Việt Nam (cột Orders.PickupDate).
///  - Giờ trong ngày = giờ Việt Nam của lúc đặt (UTC + 7; Việt Nam không có giờ mùa hè).
///  - Doanh thu theo món/danh mục = tổng LineTotal (doanh thu gộp, TRƯỚC giảm giá theo đơn).
/// Mọi phép gom nhóm chạy trên SQL Server; chỉ gom tuần/tháng làm trong bộ nhớ từ chuỗi ngày (≤ 366 điểm).
/// </summary>
public sealed class StatisticsService(CanteenDbContext db, TimeProvider clock)
{
    private const int VietnamUtcOffsetHours = 7;

    // ============================ Tổng quan ============================

    public async Task<OverviewDto> OverviewAsync(StatsQuery query, CancellationToken ct)
    {
        var (from, to) = Range(query);
        var orders = OrdersIn(from, to);
        var completed = orders.Where(o => o.Status == OrderStatus.Completed);

        var totals = await completed
            .GroupBy(_ => 1)
            .Select(g => new
            {
                Revenue = g.Sum(o => (long)o.TotalAmount),
                Count = g.Count(),
                Discount = g.Sum(o => (long)o.DiscountAmount),
                Customers = g.Select(o => o.UserId).Distinct().Count(),
            })
            .FirstOrDefaultAsync(ct);

        var cancelled = await orders.CountAsync(o => o.Status == OrderStatus.Cancelled, ct);
        var itemsSold = await db.OrderItems
            .Where(i => i.Order!.Status == OrderStatus.Completed && i.Order.PickupDate >= from && i.Order.PickupDate <= to)
            .SumAsync(i => (int?)i.Quantity, ct) ?? 0;

        var byMethod = await completed
            .GroupBy(o => o.PaymentMethod)
            .Select(g => new PaymentMethodStatDto(g.Key, g.Count(), g.Sum(o => (long)o.TotalAmount)))
            .ToListAsync(ct);
        var allMethods = Enum.GetValues<PaymentMethod>()
            .Select(m => byMethod.FirstOrDefault(x => x.Method == m) ?? new PaymentMethodStatDto(m, 0, 0))
            .ToList();

        var refunds = await orders.Where(o => o.PaymentStatus == PaymentStatus.Refunded)
            .GroupBy(_ => 1)
            .Select(g => new RefundStatDto(g.Count(), g.Sum(o => (long)o.TotalAmount)))
            .FirstOrDefaultAsync(ct) ?? new RefundStatDto(0, 0);

        var revenue = totals?.Revenue ?? 0;
        var completedCount = totals?.Count ?? 0;
        var finished = completedCount + cancelled;

        // Kỳ trước: cùng số ngày, ngay trước "from".
        var days = to.DayNumber - from.DayNumber + 1;
        var prevTo = from.AddDays(-1);
        var prevFrom = prevTo.AddDays(-(days - 1));
        var previous = await OrdersIn(prevFrom, prevTo).Where(o => o.Status == OrderStatus.Completed)
            .GroupBy(_ => 1)
            .Select(g => new { Revenue = g.Sum(o => (long)o.TotalAmount), Count = g.Count() })
            .FirstOrDefaultAsync(ct);
        var prevRevenue = previous?.Revenue ?? 0;

        return new OverviewDto(
            from, to, revenue, completedCount, cancelled,
            finished == 0 ? 0 : Math.Round(cancelled * 100.0 / finished, 1),
            completedCount == 0 ? 0 : revenue / completedCount,
            itemsSold, totals?.Discount ?? 0, totals?.Customers ?? 0,
            allMethods, refunds,
            new PeriodComparisonDto(prevFrom, prevTo, prevRevenue, previous?.Count ?? 0,
                prevRevenue == 0 ? null : Math.Round((revenue - prevRevenue) * 100.0 / prevRevenue, 1)));
    }

    // ============================ Doanh thu theo thời gian ============================

    /// <summary>Chuỗi doanh thu theo ngày/tuần/tháng — điền đủ các kỳ không có đơn bằng 0 để biểu đồ không đứt.</summary>
    public async Task<RevenueSeriesDto> RevenueAsync(RevenueQuery query, CancellationToken ct)
    {
        var (from, to) = Range(query);
        var byDay = await OrdersIn(from, to)
            .Where(o => o.Status == OrderStatus.Completed)
            .GroupBy(o => o.PickupDate)
            .Select(g => new { Day = g.Key, Revenue = g.Sum(o => (long)o.TotalAmount), Orders = g.Count() })
            .ToDictionaryAsync(x => x.Day, ct);

        Func<DateOnly, DateOnly> periodOf = query.GroupBy switch
        {
            "week" => d => d.AddDays(-(((int)d.DayOfWeek + 6) % 7)), // thứ Hai đầu tuần
            "month" => d => new DateOnly(d.Year, d.Month, 1),
            _ => d => d,
        };

        var points = Enumerable.Range(0, to.DayNumber - from.DayNumber + 1)
            .Select(from.AddDays)
            .GroupBy(periodOf)
            .Select(g => new RevenuePointDto(
                g.Key,
                Label(g.Key, query.GroupBy, g.First(), g.Last()),
                g.Sum(d => byDay.TryGetValue(d, out var v) ? v.Revenue : 0),
                g.Sum(d => byDay.TryGetValue(d, out var v) ? v.Orders : 0)))
            .ToList();

        return new RevenueSeriesDto(from, to, query.GroupBy, points.Sum(p => p.Revenue), points.Sum(p => p.Orders), points);
    }

    // ============================ Món bán chạy ============================

    public async Task<IReadOnlyList<TopFoodDto>> TopFoodsAsync(TopFoodsQuery query, CancellationToken ct)
    {
        var (from, to) = Range(query);
        var grouped = CompletedItemsIn(from, to)
            .Where(i => i.FoodId != null)
            .GroupBy(i => i.FoodId!.Value)
            .Select(g => new { FoodId = g.Key, Quantity = g.Sum(i => i.Quantity), Revenue = g.Sum(i => (long)i.LineTotal) });

        var top = await (query.SortBy == "revenue"
                ? grouped.OrderByDescending(x => x.Revenue).ThenByDescending(x => x.Quantity)
                : grouped.OrderByDescending(x => x.Quantity).ThenByDescending(x => x.Revenue))
            .ThenBy(x => x.FoodId)
            .Take(query.Limit)
            .ToListAsync(ct);

        var ids = top.Select(x => x.FoodId).ToList();
        var foods = await db.Foods.AsNoTracking()
            .Where(f => ids.Contains(f.Id))
            .Select(f => new { f.Id, f.Name, Category = f.Category!.Name, f.AverageRating, f.RatingCount })
            .ToDictionaryAsync(f => f.Id, ct);

        return top.Select(x =>
            {
                var f = foods[x.FoodId]; // món xóa mềm vẫn còn trong bảng Foods
                return new TopFoodDto(x.FoodId, f.Name, f.Category, x.Quantity, x.Revenue, f.AverageRating, f.RatingCount);
            })
            .ToList();
    }

    // ============================ Giờ cao điểm ============================

    /// <summary>24 cột theo giờ Việt Nam của lúc đặt (giờ không có đơn = 0).</summary>
    public async Task<IReadOnlyList<HourlyStatDto>> HourlyAsync(StatsQuery query, CancellationToken ct)
    {
        var (from, to) = Range(query);
        var byHour = await OrdersIn(from, to)
            .Where(o => o.Status == OrderStatus.Completed)
            .GroupBy(o => o.CreatedAt.AddHours(VietnamUtcOffsetHours).Hour)
            .Select(g => new { Hour = g.Key, Orders = g.Count(), Revenue = g.Sum(o => (long)o.TotalAmount) })
            .ToDictionaryAsync(x => x.Hour, ct);

        return Enumerable.Range(0, 24)
            .Select(h => byHour.TryGetValue(h, out var v)
                ? new HourlyStatDto(h, v.Orders, v.Revenue)
                : new HourlyStatDto(h, 0, 0))
            .ToList();
    }

    // ============================ Theo danh mục ============================

    /// <summary>Tỷ trọng doanh thu theo danh mục; % được làm tròn sao cho tổng đúng bằng 100.</summary>
    public async Task<IReadOnlyList<CategoryStatDto>> CategoriesAsync(StatsQuery query, CancellationToken ct)
    {
        var (from, to) = Range(query);
        var rows = await CompletedItemsIn(from, to)
            .GroupBy(i => new { CategoryId = (int?)i.Food!.CategoryId, Name = i.Food.Category!.Name })
            .Select(g => new { g.Key.CategoryId, g.Key.Name, Quantity = g.Sum(i => i.Quantity), Revenue = g.Sum(i => (long)i.LineTotal) })
            .OrderByDescending(x => x.Revenue)
            .ToListAsync(ct);

        var percents = LargestRemainderPercents(rows.Select(r => r.Revenue).ToList());
        return rows.Select((r, i) => new CategoryStatDto(r.CategoryId, r.Name ?? "Món đã xóa", r.Quantity, r.Revenue, percents[i]))
            .ToList();
    }

    // ============================ Hỗ trợ ============================

    /// <summary>Khoảng ngày (giờ VN); bỏ trống = hôm nay.</summary>
    private (DateOnly From, DateOnly To) Range(StatsQuery query)
    {
        var today = DateOnly.FromDateTime(VietnamTime.Now(clock));
        var to = query.To ?? query.From ?? today;
        var from = query.From ?? to;
        return (from, to);
    }

    private IQueryable<Order> OrdersIn(DateOnly from, DateOnly to) =>
        db.Orders.AsNoTracking().Where(o => o.PickupDate >= from && o.PickupDate <= to);

    private IQueryable<OrderItem> CompletedItemsIn(DateOnly from, DateOnly to) =>
        db.OrderItems.AsNoTracking().Where(i =>
            i.Order!.Status == OrderStatus.Completed && i.Order.PickupDate >= from && i.Order.PickupDate <= to);

    private static string Label(DateOnly period, string groupBy, DateOnly first, DateOnly last) => groupBy switch
    {
        "week" => $"{first:dd/MM}–{last:dd/MM}",
        "month" => $"{period:MM/yyyy}",
        _ => $"{period:dd/MM}",
    };

    /// <summary>
    /// Phương pháp phần dư lớn nhất: làm tròn % tới 0,1 mà tổng vẫn đúng 100
    /// (làm tròn từng mục riêng lẻ có thể ra 99,9 hoặc 100,1).
    /// </summary>
    public static double[] LargestRemainderPercents(IReadOnlyList<long> values)
    {
        var total = values.Sum();
        if (total == 0) return values.Select(_ => 0d).ToArray();

        var tenths = values.Select(v => v * 1000.0 / total).ToArray(); // đơn vị 0,1%
        var floors = tenths.Select(Math.Floor).ToArray();
        var missing = 1000 - (int)floors.Sum();
        foreach (var i in tenths.Select((t, i) => (Rem: t - Math.Floor(t), i)).OrderByDescending(x => x.Rem).Take(missing).Select(x => x.i))
            floors[i] += 1;
        return floors.Select(f => f / 10).ToArray();
    }
}
