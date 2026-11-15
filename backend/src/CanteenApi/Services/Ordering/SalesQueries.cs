using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Models;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Services.Ordering;

/// <summary>Truy vấn số lượng đã bán dùng chung cho tính giá và đặt món.</summary>
public static class SalesQueries
{
    /// <summary>
    /// Số suất đã đặt HÔM NAY (giờ Việt Nam) của từng món, bỏ qua đơn bị hủy.
    /// Cùng quy tắc với cột remainingToday ở danh sách món (FoodService).
    /// </summary>
    public static async Task<Dictionary<int, int>> SoldTodayAsync(
        CanteenDbContext db, IReadOnlyCollection<int> foodIds, TimeProvider clock, CancellationToken ct)
    {
        if (foodIds.Count == 0) return [];

        var (start, end) = VietnamTime.TodayRangeUtc(clock);
        return await db.OrderItems
            .Where(i => i.FoodId != null && foodIds.Contains(i.FoodId.Value) &&
                        i.Order!.Status != OrderStatus.Cancelled &&
                        i.Order.CreatedAt >= start && i.Order.CreatedAt < end)
            .GroupBy(i => i.FoodId!.Value)
            .Select(g => new { FoodId = g.Key, Quantity = g.Sum(i => i.Quantity) })
            .ToDictionaryAsync(x => x.FoodId, x => x.Quantity, ct);
    }
}
