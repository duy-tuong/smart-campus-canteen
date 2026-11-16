using CanteenApi.Common;
using CanteenApi.Dtos.Statistics;
using CanteenApi.Models;
using CanteenApi.Services.Dev;
using CanteenApi.Tests.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace CanteenApi.Tests.Api;

/// <summary>Sinh dữ liệu lịch sử cho demo: hợp lệ với mọi ràng buộc, lặp lại được, khớp với thống kê.</summary>
public class HistorySeederTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    private async Task<HistorySeedResult> SeedAsync(int days = 30, bool reset = false)
    {
        await using var scope = Factory.Services.CreateAsyncScope();
        return await scope.ServiceProvider.GetRequiredService<HistorySeeder>().SeedAsync(days, reset, default);
    }

    [Fact]
    public async Task Sinh30Ngay_HopLe_KhongDungToiHomNay()
    {
        var r = await SeedAsync();

        Assert.Equal((new DateOnly(2026, 10, 17), new DateOnly(2026, 11, 15)), (r.From, r.To));
        Assert.True(r.Orders > 400, $"Chỉ có {r.Orders} đơn");
        Assert.InRange(r.Cancelled * 100.0 / r.Orders, 3, 15);
        Assert.True(r.Reviews > 50 && r.Replies > 0 && r.HiddenReviews >= 0);

        await Factory.WithDbAsync(async db =>
        {
            // Không đơn nào thuộc hôm nay; mã nhận món không trùng trong ngày; tổng tiền khớp chi tiết.
            Assert.False(await db.Orders.AnyAsync(o => o.PickupDate >= new DateOnly(2026, 11, 16)));
            Assert.False(await db.Orders.GroupBy(o => new { o.PickupDate, o.PickupCode }).AnyAsync(g => g.Count() > 1));
            Assert.False(await db.Orders.AnyAsync(o => o.Subtotal != o.Items.Sum(i => i.LineTotal)));
            // Đơn hoàn thành nào cũng có đủ 4 mốc lịch sử và đã thanh toán.
            Assert.False(await db.Orders.AnyAsync(o => o.Status == OrderStatus.Completed &&
                (o.StatusHistory.Count != 4 || o.PaymentStatus != PaymentStatus.Paid)));
            // Đánh giá luôn viết sau khi nhận món.
            Assert.False(await db.Reviews.AnyAsync(rv => rv.CreatedAt < rv.Order!.UpdatedAt));
        });
    }

    [Fact]
    public async Task DiemSaoMon_KhopVoiDanhGiaKhongBiAn()
    {
        await SeedAsync();

        await Factory.WithDbAsync(async db =>
        {
            var foods = await db.Foods.AsNoTracking().ToListAsync();
            foreach (var f in foods)
            {
                var visible = await db.Reviews.Where(r => r.FoodId == f.Id && !r.IsHidden).Select(r => (int)r.Rating).ToListAsync();
                Assert.Equal(visible.Count, f.RatingCount);
                Assert.Equal(visible.Count == 0 ? 0m : Math.Round((decimal)visible.Average(), 2), f.AverageRating);
            }
        });
    }

    [Fact]
    public async Task ThongKe_KhopTongDoanhThuDaSinh()
    {
        var r = await SeedAsync();

        var series = await (await AsStaff.GetAsync($"/api/stats/revenue?from={r.From:yyyy-MM-dd}&to={r.To:yyyy-MM-dd}"))
            .ReadAsAsync<RevenueSeriesDto>();
        var hourly = await (await AsStaff.GetAsync($"/api/stats/hourly?from={r.From:yyyy-MM-dd}&to={r.To:yyyy-MM-dd}"))
            .ReadAsAsync<List<HourlyStatDto>>();

        Assert.Equal((r.Revenue, r.Completed), (series.TotalRevenue, series.TotalOrders));
        Assert.Equal(30, series.Points.Count);
        // Giờ cao điểm: buổi trưa đông nhất, không có đơn lúc nửa đêm.
        Assert.Equal(hourly.Max(h => h.Orders), hourly.Where(h => h.Hour is 11 or 12).Max(h => h.Orders));
        Assert.Equal(0, hourly.Where(h => h.Hour < 6 || h.Hour > 18).Sum(h => h.Orders));
    }

    [Fact]
    public async Task ChayLai_CanReset_VaChoCungSoLieu()
    {
        var first = await SeedAsync();

        await using (var scope = Factory.Services.CreateAsyncScope())
        {
            var seeder = scope.ServiceProvider.GetRequiredService<HistorySeeder>();
            var ex = await Assert.ThrowsAsync<ConflictException>(() => seeder.SeedAsync(30, reset: false, default));
            Assert.Equal(ErrorCodes.Duplicate, ex.Code);
        }

        var second = await SeedAsync(reset: true);

        Assert.Equal(first with { }, second); // cùng seed → cùng số đơn, doanh thu, đánh giá
        Assert.Equal(first.Orders, await Factory.WithDbAsync(db => db.Orders.CountAsync()));
    }

    [Fact]
    public async Task KhongDeLenDonThatCungNgay()
    {
        // Một đơn thật hôm qua với mã 001 → dữ liệu lịch sử phải đánh số tiếp, không vi phạm UNIQUE.
        await TestOrders.AddAsync(Factory, TestData.ComTam, 1, CanteenApiFactory.Now.UtcDateTime.AddDays(-1), OrderStatus.Completed);
        await Factory.WithDbAsync(db => db.Orders.ExecuteUpdateAsync(s => s.SetProperty(o => o.PickupCode, "001")));

        var r = await SeedAsync(days: 2);

        Assert.True(r.Orders > 0);
        var yesterday = new DateOnly(2026, 11, 15);
        Assert.Equal(1, await Factory.WithDbAsync(db => db.Orders.CountAsync(o => o.PickupDate == yesterday && o.PickupCode == "001")));
    }
}
