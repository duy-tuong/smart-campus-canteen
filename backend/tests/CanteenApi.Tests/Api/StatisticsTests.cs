using System.Net;
using CanteenApi.Common;
using CanteenApi.Dtos.Statistics;
using CanteenApi.Models;
using CanteenApi.Services.Statistics;
using CanteenApi.Tests.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Tests.Api;

/// <summary>
/// Thống kê doanh thu. "Bây giờ" = 10:00 ngày 16/11/2026 giờ VN. Dữ liệu dựng sẵn:
///   16/11: Cơm gà ×2 = 70.000 (06:45 VN — tức 23:45 UTC ngày 15/11), Trà sữa ×1 = 25.000 (11:30, sinh viên 2),
///          Nước suối ×3 = 24.000 − 1.000 voucher = 23.000 (12:10), Cơm tấm ×1 bị HỦY
///   15/11: Cơm tấm ×1 = 40.000 (12:00)
///   13/11: Cơm gà ×1 = 35.000 (11:15)
///   20/10: Nước suối ×1 = 8.000
/// </summary>
public class StatisticsTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    private static DateTime Vn(int month, int day, int hour, int minute) =>
        new DateTimeOffset(2026, month, day, hour, minute, 0, TimeSpan.FromHours(7)).UtcDateTime;

    private async Task SeedAsync()
    {
        await TestOrders.AddAsync(Factory, TestData.ComGa, 2, Vn(11, 16, 6, 45), OrderStatus.Completed);
        await TestOrders.AddAsync(Factory, TestData.TraSua, 1, Vn(11, 16, 11, 30), OrderStatus.Completed, TestData.Student2);
        await TestOrders.AddAsync(Factory, TestData.NuocSuoi, 3, Vn(11, 16, 12, 10), OrderStatus.Completed, voucherCode: TestData.Fixed5K);
        await TestOrders.AddAsync(Factory, TestData.ComTam, 1, Vn(11, 16, 9, 0), OrderStatus.Cancelled);
        await TestOrders.AddAsync(Factory, TestData.ComTam, 1, Vn(11, 15, 12, 0), OrderStatus.Completed);
        await TestOrders.AddAsync(Factory, TestData.ComGa, 1, Vn(11, 13, 11, 15), OrderStatus.Completed);
        await TestOrders.AddAsync(Factory, TestData.NuocSuoi, 1, Vn(10, 20, 7, 0), OrderStatus.Completed);
    }

    [Fact]
    public async Task TongQuan_HomNay_VaSoSanhHomQua()
    {
        await SeedAsync();

        var o = await GetAsync<OverviewDto>("/api/stats/overview");

        Assert.Equal((new DateOnly(2026, 11, 16), new DateOnly(2026, 11, 16)), (o.From, o.To));
        Assert.Equal((118_000L, 3, 1), (o.Revenue, o.CompletedOrders, o.CancelledOrders));
        Assert.Equal(25.0, o.CancelRate);              // 1 hủy / 4 đơn đã kết thúc
        Assert.Equal(39_333L, o.AverageOrderValue);    // 118.000 / 3
        Assert.Equal((6, 1_000L, 2), (o.ItemsSold, o.DiscountTotal, o.UniqueCustomers));
        Assert.Equal(118_000L, o.ByPaymentMethod.Single(m => m.Method == PaymentMethod.Cash).Revenue);
        Assert.Equal(0, o.ByPaymentMethod.Single(m => m.Method == PaymentMethod.BankTransfer).Orders);

        // Kỳ trước = 15/11: 40.000 → tăng (118 − 40) / 40 = 195%.
        Assert.Equal((new DateOnly(2026, 11, 15), 40_000L, 195.0), (o.Previous.From, o.Previous.Revenue, o.Previous.RevenueChangePercent));
    }

    [Fact]
    public async Task TongQuan_KhongCoDuLieu_KhongChiaChoKhong()
    {
        var o = await GetAsync<OverviewDto>("/api/stats/overview?from=2026-01-01&to=2026-01-07");

        Assert.Equal((0L, 0, 0.0, 0L), (o.Revenue, o.CompletedOrders, o.CancelRate, o.AverageOrderValue));
        Assert.Null(o.Previous.RevenueChangePercent);
        Assert.Equal(new DateOnly(2025, 12, 25), o.Previous.From); // kỳ trước cũng dài 7 ngày
    }

    [Fact]
    public async Task HoanTien_DuocDemRieng()
    {
        await TestOrders.AddAsync(Factory, TestData.ComTam, 1, Vn(11, 16, 8, 0), OrderStatus.Cancelled);
        await Factory.WithDbAsync(db => db.Orders.ExecuteUpdateAsync(s => s
            .SetProperty(x => x.PaymentStatus, PaymentStatus.Refunded)
            .SetProperty(x => x.PaidAt, CanteenApiFactory.Now.UtcDateTime)));

        var o = await GetAsync<OverviewDto>("/api/stats/overview");

        Assert.Equal((1, 40_000L, 0L), (o.Refunds.Orders, o.Refunds.Amount, o.Revenue));
    }

    [Fact]
    public async Task DoanhThuTheoNgay_DienSo0_ChoNgayTrong()
    {
        await SeedAsync();

        var s = await GetAsync<RevenueSeriesDto>("/api/stats/revenue?from=2026-11-13&to=2026-11-16");

        Assert.Equal(["13/11", "14/11", "15/11", "16/11"], s.Points.Select(p => p.Label));
        Assert.Equal([35_000L, 0, 40_000, 118_000], s.Points.Select(p => p.Revenue));
        Assert.Equal([1, 0, 1, 3], s.Points.Select(p => p.Orders));
        Assert.Equal((193_000L, 5), (s.TotalRevenue, s.TotalOrders));
    }

    [Fact]
    public async Task DoanhThuTheoTuan_BatDauThuHai()
    {
        await SeedAsync();

        var s = await GetAsync<RevenueSeriesDto>("/api/stats/revenue?from=2026-11-01&to=2026-11-16&groupBy=week");

        Assert.All(s.Points.Skip(1), p => Assert.Equal(DayOfWeek.Monday, p.Period.DayOfWeek));
        Assert.Equal(193_000L, s.Points.Sum(p => p.Revenue));
        Assert.Equal(new DateOnly(2026, 11, 16), s.Points[^1].Period); // 16/11/2026 là thứ Hai
        Assert.Equal(118_000L, s.Points[^1].Revenue);
    }

    [Fact]
    public async Task DoanhThuTheoThang()
    {
        await SeedAsync();

        var s = await GetAsync<RevenueSeriesDto>("/api/stats/revenue?from=2026-10-01&to=2026-11-16&groupBy=month");

        Assert.Equal(["10/2026", "11/2026"], s.Points.Select(p => p.Label));
        Assert.Equal([8_000L, 193_000], s.Points.Select(p => p.Revenue));
    }

    [Fact]
    public async Task MonBanChay_TheoSoLuongVaDoanhThu()
    {
        await SeedAsync();
        const string range = "from=2026-11-13&to=2026-11-16";

        var byQty = await GetAsync<List<TopFoodDto>>($"/api/stats/top-foods?{range}");
        Assert.Equal([(TestData.ComGa, 3), (TestData.NuocSuoi, 3), (TestData.ComTam, 1), (TestData.TraSua, 1)],
            byQty.Select(f => (f.Name, f.Quantity)));
        Assert.Equal(TestData.Rice, byQty[0].CategoryName);

        var byRevenue = await GetAsync<List<TopFoodDto>>($"/api/stats/top-foods?{range}&sortBy=revenue&limit=2");
        Assert.Equal([(TestData.ComGa, 105_000L), (TestData.ComTam, 40_000L)], byRevenue.Select(f => (f.Name, f.Revenue)));
    }

    [Fact]
    public async Task GioCaoDiem_TheoGioVietNam()
    {
        await SeedAsync();

        var hours = await GetAsync<List<HourlyStatDto>>("/api/stats/hourly");

        Assert.Equal(Enumerable.Range(0, 24), hours.Select(h => h.Hour));
        // 06:45 VN = 23:45 UTC hôm trước: phải vào cột 6 giờ, không phải 23 giờ.
        Assert.Equal((1, 70_000L), (hours[6].Orders, hours[6].Revenue));
        Assert.Equal(0, hours[23].Orders);
        Assert.Equal(1, hours[11].Orders);
        Assert.Equal(1, hours[12].Orders);
        Assert.Equal(3, hours.Sum(h => h.Orders)); // đơn hủy không tính
    }

    [Fact]
    public async Task TheoDanhMuc_TongPhanTramBang100()
    {
        await SeedAsync();

        var cats = await GetAsync<List<CategoryStatDto>>("/api/stats/categories?from=2026-11-13&to=2026-11-16");

        Assert.Equal([TestData.Rice, TestData.Drinks], cats.Select(c => c.Name));
        Assert.Equal([145_000L, 49_000], cats.Select(c => c.Revenue)); // doanh thu gộp, trước giảm giá
        Assert.Equal(100.0, cats.Sum(c => c.Percent), precision: 6);
    }

    [Theory]
    [InlineData(new long[] { 1, 1, 1 }, new[] { 33.4, 33.3, 33.3 })] // làm tròn riêng lẻ sẽ ra 99,9
    [InlineData(new long[] { 145_000, 49_000 }, new[] { 74.7, 25.3 })]
    [InlineData(new long[] { 0, 0 }, new[] { 0.0, 0.0 })]
    public void PhanTram_TongLuonBang100(long[] values, double[] expected) =>
        Assert.Equal(expected, StatisticsService.LargestRemainderPercents(values));

    [Theory]
    [InlineData("/api/stats/overview?from=2026-11-16&to=2026-11-01")]   // from > to
    [InlineData("/api/stats/revenue?from=2025-01-01&to=2026-11-16")]    // > 366 ngày
    [InlineData("/api/stats/revenue?groupBy=year")]
    [InlineData("/api/stats/top-foods?limit=100")]
    [InlineData("/api/stats/top-foods?sortBy=price")]
    public async Task ThamSoSai_400(string url)
    {
        await (await AsStaff.GetAsync(url)).ShouldBeProblemAsync(HttpStatusCode.BadRequest, ErrorCodes.ValidationError);
    }

    [Fact]
    public async Task SinhVienKhongXemDuoc_AdminXemDuoc()
    {
        await (await AsStudent.GetAsync("/api/stats/overview")).ShouldBeProblemAsync(HttpStatusCode.Forbidden, ErrorCodes.Forbidden);
        await (await AsAdmin.GetAsync("/api/stats/overview")).ShouldHaveStatusAsync(HttpStatusCode.OK);
    }

    private async Task<T> GetAsync<T>(string url) => await (await AsStaff.GetAsync(url)).ReadAsAsync<T>();
}
