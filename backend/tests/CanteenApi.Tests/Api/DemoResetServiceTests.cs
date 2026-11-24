using CanteenApi.Models;
using CanteenApi.Services.Dev;
using CanteenApi.Tests.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace CanteenApi.Tests.Api;

/// <summary>Làm mới dữ liệu trước buổi demo: dọn đơn chạy thử, giữ lịch sử, khôi phục thực đơn và voucher.</summary>
public class DemoResetServiceTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    private static readonly DateTime NowUtc = CanteenApiFactory.Now.UtcDateTime;

    /// <summary>menu.json thu nhỏ theo đúng tên món của TestData.</summary>
    private static List<Category> SeedMenu() =>
    [
        new()
        {
            Name = TestData.Rice, Description = "Cơm phần", Icon = "rice_bowl", SortOrder = 1,
            Foods =
            {
                new Food { Name = TestData.ComGa, Description = "Mô tả gốc", Price = 35000, PrepTimeMinutes = 10, DailyLimit = 60, ImageUrl = "/images/com-ga.jpg" },
                new Food { Name = TestData.ComTam, Description = "Sườn bì chả", Price = 40000, PrepTimeMinutes = 10 },
            },
        },
        new()
        {
            Name = TestData.Drinks, Icon = "local_drink", SortOrder = 2,
            Foods =
            {
                new Food { Name = TestData.TraSua, Description = "Trà sữa", Price = 25000, PrepTimeMinutes = 4 },
                new Food { Name = TestData.NuocSuoi, Description = "Nước suối", Price = 8000, PrepTimeMinutes = 1 },
            },
        },
    ];

    private static readonly SeedVoucher[] SeedVouchers =
        [new(TestData.Percent10, "Giảm 10%", DiscountType.Percent, 10, 15000, 30000, ValidDays: 14, UsageLimit: 100, PerUserLimit: 2)];

    private async Task<DemoResetResult> ResetAsync()
    {
        await using var scope = Factory.Services.CreateAsyncScope();
        return await scope.ServiceProvider.GetRequiredService<DemoResetService>().ResetAsync(SeedMenu(), SeedVouchers, default);
    }

    [Fact]
    public async Task DonChayThu_BiXoa_DonLichSu_DuocGiu()
    {
        var live = await TestOrders.AddAsync(Factory, TestData.ComGa, 1, NowUtc, OrderStatus.Cooking, voucherCode: TestData.Percent10);
        var history = await TestOrders.AddAsync(Factory, TestData.ComTam, 1, NowUtc.AddDays(-3), OrderStatus.Completed);
        await Factory.WithDbAsync(async db =>
        {
            await db.Orders.Where(o => o.Id == history).ExecuteUpdateAsync(s => s.SetProperty(o => o.ClientRequestId, "hist-test-1"));
            var comGa = await db.Foods.SingleAsync(f => f.Name == TestData.ComGa);
            var comTam = await db.Foods.SingleAsync(f => f.Name == TestData.ComTam);
            db.Reviews.AddRange(
                new Review { OrderId = live, FoodId = comGa.Id, UserId = TestData.Student1, Rating = 1 },
                new Review { OrderId = history, FoodId = comTam.Id, UserId = TestData.Student1, Rating = 5 });
            db.Notifications.Add(new Notification { UserId = TestData.Student1, Title = "Đơn đang nấu", Body = "…", RefId = live });
            await db.SaveChangesAsync();
        });

        var r = await ResetAsync();

        Assert.Equal((1, 1, 1), (r.OrdersDeleted, r.ReviewsDeleted, r.NotificationsDeleted));
        await Factory.WithDbAsync(async db =>
        {
            Assert.Equal([history], await db.Orders.Select(o => o.Id).ToListAsync());
            Assert.Equal(5, await db.Reviews.Select(rv => rv.Rating).SingleAsync());
            Assert.False(await db.Notifications.AnyAsync());
            // Điểm sao tính lại chỉ từ đánh giá còn lại.
            var foods = await db.Foods.Where(f => f.Name == TestData.ComGa || f.Name == TestData.ComTam)
                .ToDictionaryAsync(f => f.Name, f => (f.AverageRating, f.RatingCount));
            Assert.Equal((0m, 0), foods[TestData.ComGa]);
            Assert.Equal((5m, 1), foods[TestData.ComTam]);
            // Voucher mẫu: gia hạn từ 00:00 hôm nay (giờ VN = 17:00 UTC hôm trước), lượt dùng của đơn đã xóa được trả lại.
            var v = await db.Vouchers.SingleAsync(x => x.Code == TestData.Percent10);
            Assert.Equal((new DateTime(2026, 11, 15, 17, 0, 0), 14.0, 0, true),
                (v.StartAt, (v.EndAt - v.StartAt).TotalDays, v.UsedCount, v.IsActive));
        });
    }

    [Fact]
    public async Task ThucDon_VeDungMenuJson_MonVaDanhMucThem_BiAn()
    {
        await Factory.WithDbAsync(async db =>
        {
            var comGa = await db.Foods.SingleAsync(f => f.Name == TestData.ComGa);
            comGa.Price = 99000;
            comGa.IsAvailable = false;
            comGa.Description = "Sửa khi tập dượt";
            (await db.Foods.SingleAsync(f => f.Name == TestData.ComTam)).IsDeleted = true;
            var rice = await db.Categories.SingleAsync(c => c.Name == TestData.Rice);
            rice.IsActive = false;
            rice.Foods.Add(new Food { Name = "Bánh bao", Description = "Thêm khi tập", Price = 15000, PrepTimeMinutes = 2 });
            await db.SaveChangesAsync();
        });

        var r = await ResetAsync();

        await Factory.WithDbAsync(async db =>
        {
            var foods = await db.Foods.ToDictionaryAsync(f => f.Name);
            var comGa = foods[TestData.ComGa];
            Assert.Equal((35000, true, "Mô tả gốc", "/images/com-ga.jpg"), (comGa.Price, comGa.IsAvailable, comGa.Description, comGa.ImageUrl));
            Assert.False(foods[TestData.ComTam].IsDeleted);
            Assert.True(foods["Bánh bao"].IsDeleted, "món thêm khi tập dượt bị ẩn");
            Assert.True(foods[TestData.HiddenFood].IsDeleted, "món không có trong menu.json bị ẩn");

            var categories = await db.Categories.ToDictionaryAsync(c => c.Name);
            Assert.True(categories[TestData.Rice].IsActive);
            Assert.True(categories[TestData.HiddenCategory].IsDeleted);
        });
        Assert.Equal((4, 2, 2, 1), (r.FoodsRestored, r.FoodsHidden, r.CategoriesRestored, r.CategoriesHidden));
        // Voucher không có trong menu.json (và không có đơn dùng) bị xóa.
        Assert.True(r.VouchersRemoved > 0);
        Assert.Equal([TestData.Percent10], await Factory.WithDbAsync(db => db.Vouchers.Select(v => v.Code).ToListAsync()));
    }

    [Fact]
    public async Task ChayLaiNhieuLan_KhongDoiGiThem()
    {
        await ResetAsync();
        var again = await ResetAsync();
        Assert.Equal((0, 0, 0, 0, 0), (again.OrdersDeleted, again.FoodsHidden, again.CategoriesHidden, again.VouchersRemoved, again.NotificationsDeleted));
        Assert.Equal((4, 2, 1), (again.FoodsRestored, again.CategoriesRestored, again.VouchersRefreshed));
    }
}
