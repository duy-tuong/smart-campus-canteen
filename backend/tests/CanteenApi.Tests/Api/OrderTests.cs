using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using CanteenApi.Common;
using CanteenApi.Dtos.Orders;
using CanteenApi.Models;
using CanteenApi.Tests.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Tests.Api;

/// <summary>Đặt món: tính tiền phía server, idempotency, giờ mở cửa, giờ hẹn, giới hạn đơn, chống bán quá suất.</summary>
public class CreateOrderTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    [Fact]
    public async Task DatMonTienMat_201_DayDuThongTin()
    {
        var traSua = await FoodAsync(TestData.TraSua);
        var response = await CreateAsync(AsStudent,
            [Line(await FoodIdAsync(TestData.ComGa), 2), Line(traSua.Id, 1, OptionId(traSua, "L"), OptionId(traSua, "Pudding"))],
            note: "  ít cay  ");

        var order = await response.ReadAsAsync<OrderDetailDto>(HttpStatusCode.Created);
        Assert.EndsWith($"/api/orders/{order.Id}", response.Headers.Location?.ToString());
        Assert.Equal(("001", OrderStatus.Received, PaymentStatus.Pending), (order.PickupCode, order.Status, order.PaymentStatus));
        Assert.Equal((108_000, 0, 108_000, 3), (order.Subtotal, order.DiscountAmount, order.TotalAmount, order.TotalItems));
        Assert.Equal("ít cay", order.Note);
        Assert.Equal(["Size", "Topping"], order.Items[1].Options.Select(o => o.GroupName));
        Assert.Equal(OrderStatus.Received, Assert.Single(order.History).ToStatus);
        Assert.Equal((PaymentMethod.Cash, PaymentStatus.Pending, 108_000), (order.Payment!.Method, order.Payment.Status, order.Payment.Amount));
        Assert.True(order.CanCancel);
        Assert.Equal(new DateOnly(2026, 11, 16), order.PickupDate);

        // Lưu đúng vào database (kể cả bản chụp tùy chọn).
        var saved = await Factory.WithDbAsync(db => db.OrderItemOptions.CountAsync(o => o.OrderItem!.OrderId == order.Id));
        Assert.Equal(2, saved);
    }

    [Fact]
    public async Task CungIdempotencyKey_TraLaiDonCu_KhongTaoTrung()
    {
        var key = Guid.NewGuid().ToString();
        var items = new[] { Line(await FoodIdAsync(TestData.ComTam), 1) };

        var first = await (await CreateAsync(AsStudent, items, key: key)).ReadAsAsync<OrderDetailDto>(HttpStatusCode.Created);
        var retry = await (await CreateAsync(AsStudent, items, key: key)).ReadAsAsync<OrderDetailDto>(HttpStatusCode.OK);
        var another = await (await CreateAsync(AsStudent, items)).ReadAsAsync<OrderDetailDto>(HttpStatusCode.Created);

        Assert.Equal(first.Id, retry.Id);
        Assert.Equal("002", another.PickupCode);
        Assert.Equal(2, await Factory.WithDbAsync(db => db.Orders.CountAsync()));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("khong-phai-guid")]
    public async Task ThieuHoacSaiIdempotencyKey_400(string? key)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/orders")
        {
            Content = JsonContent.Create(Request([Line(await FoodIdAsync(TestData.ComTam), 1)]), options: HttpExtensions.Json),
        };
        if (key is not null) request.Headers.Add("Idempotency-Key", key);

        var response = await AsStudent.SendAsync(request);

        await response.ShouldBeProblemAsync(HttpStatusCode.BadRequest, ErrorCodes.ValidationError);
    }

    [Fact]
    public async Task MonKhongHopLe_422_KemLoiTheoDong()
    {
        var traSua = await FoodAsync(TestData.TraSua);

        var response = await CreateAsync(AsStudent, [Line(await FoodIdAsync(TestData.ComTam), 1), Line(traSua.Id, 1)]);

        var problem = await response.ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.OrderItemsInvalid);
        var item = Assert.Single(problem.GetProperty("items").EnumerateArray());
        Assert.Equal((1, ErrorCodes.OptionInvalid), (item.GetProperty("index").GetInt32(), item.GetProperty("code").GetString()));
        Assert.Equal(0, await Factory.WithDbAsync(db => db.Orders.CountAsync()));
    }

    [Fact]
    public async Task Voucher_DuocGiam_VaTangLuotDung()
    {
        var order = await (await CreateAsync(AsStudent, [Line(await FoodIdAsync(TestData.ComGa), 2)], voucher: "tansv10"))
            .ReadAsAsync<OrderDetailDto>(HttpStatusCode.Created);

        Assert.Equal((70_000, 7_000, 63_000, TestData.Percent10), (order.Subtotal, order.DiscountAmount, order.TotalAmount, order.VoucherCode));
        Assert.Equal(1, await Factory.WithDbAsync(db => db.Vouchers.Where(v => v.Code == TestData.Percent10).Select(v => v.UsedCount).SingleAsync()));
    }

    [Fact]
    public async Task VoucherKhongDung_422_KhongTaoDon()
    {
        var response = await CreateAsync(AsStudent, [Line(await FoodIdAsync(TestData.ComGa), 2)], voucher: TestData.Expired);

        await response.ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.VoucherExpired);
        Assert.Equal(0, await Factory.WithDbAsync(db => db.Orders.CountAsync()));
    }

    [Fact]
    public async Task NgoaiGioMoCua_422_CanteenClosed()
    {
        Factory.Clock.Set(new DateTimeOffset(2026, 11, 16, 13, 0, 0, TimeSpan.Zero)); // 20:00 giờ VN

        var response = await CreateAsync(AsStudent, [Line(await FoodIdAsync(TestData.ComTam), 1)]);

        await response.ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.CanteenClosed);
    }

    [Theory]
    [InlineData("2026-11-16T10:05:00+07:00")] // sớm hơn thời gian chế biến (Cơm gà 10 phút)
    [InlineData("2026-11-16T09:00:00+07:00")] // đã qua
    [InlineData("2026-11-17T11:00:00+07:00")] // ngày mai
    [InlineData("2026-11-16T19:30:00+07:00")] // sau giờ đóng cửa
    public async Task GioHenKhongHopLe_422(string pickup)
    {
        var response = await CreateAsync(AsStudent, [Line(await FoodIdAsync(TestData.ComGa), 1)],
            pickupTime: DateTimeOffset.Parse(pickup));

        await response.ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.PickupTimeInvalid);
    }

    [Fact]
    public async Task GioHenHopLe_DuKienXongDungGioHen()
    {
        var pickup = DateTimeOffset.Parse("2026-11-16T11:30:00+07:00");

        var order = await (await CreateAsync(AsStudent, [Line(await FoodIdAsync(TestData.ComGa), 1)], pickupTime: pickup))
            .ReadAsAsync<OrderDetailDto>(HttpStatusCode.Created);

        Assert.Equal(pickup.UtcDateTime, order.PickupTime);
        Assert.Equal(pickup.UtcDateTime, order.EstimatedReadyAt);
    }

    [Fact]
    public async Task KhongHenGio_DuKienXong_TheoThoiGianCheBienVaHangDoi()
    {
        var comGa = await FoodIdAsync(TestData.ComGa); // 10 phút
        await CreateAsync(AsStudent2, [Line(comGa, 1)]);  // 1 đơn đang chờ trước

        var order = await (await CreateAsync(AsStudent, [Line(comGa, 1)])).ReadAsAsync<OrderDetailDto>(HttpStatusCode.Created);

        Assert.Equal(CanteenApiFactory.Now.UtcDateTime.AddMinutes(10 + 2), order.EstimatedReadyAt);
    }

    [Fact]
    public async Task QuaSoDonDangXuLy_422_DonHuyVaHoanThanhKhongTinh()
    {
        var now = CanteenApiFactory.Now.UtcDateTime;
        await TestOrders.AddAsync(Factory, TestData.ComTam, 1, now.AddHours(-1), OrderStatus.Cancelled);
        await TestOrders.AddAsync(Factory, TestData.ComTam, 1, now.AddHours(-1), OrderStatus.Completed);
        var comTam = await FoodIdAsync(TestData.ComTam);

        for (var i = 0; i < 3; i++)
            await (await CreateAsync(AsStudent, [Line(comTam, 1)])).ShouldHaveStatusAsync(HttpStatusCode.Created);

        await (await CreateAsync(AsStudent, [Line(comTam, 1)]))
            .ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.TooManyActiveOrders);
        await (await CreateAsync(AsStudent2, [Line(comTam, 1)])).ShouldHaveStatusAsync(HttpStatusCode.Created);
    }

    [Fact]
    public async Task ChuyenKhoanKhiChuaBatPayOS_422()
    {
        Factory.Payments.Enabled = false;
        var response = await CreateAsync(AsStudent, [Line(await FoodIdAsync(TestData.ComTam), 1)], method: "bankTransfer");
        await response.ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.PaymentMethodUnavailable);
    }

    [Fact]
    public async Task DatSongSong_10Request_Con5Suat_DungNamDonThanhCong_MaKhongTrung()
    {
        var comGa = await FoodIdAsync(TestData.ComGa);
        await Factory.WithDbAsync(db => db.Foods.Where(f => f.Id == comGa)
            .ExecuteUpdateAsync(s => s.SetProperty(f => f.DailyLimit, 5)));

        // 4 người (mỗi người ≤ 3 đơn để không chạm giới hạn đơn đang xử lý), 10 request cùng lúc, mỗi request 1 suất.
        var clients = new[] { AsStudent, AsStudent, AsStudent, AsStudent2, AsStudent2, AsStudent2, AsStaff, AsStaff, AsAdmin, AsAdmin };
        var responses = await Task.WhenAll(clients.Select(c => CreateAsync(c, [Line(comGa, 1)])));

        var created = responses.Where(r => r.StatusCode == HttpStatusCode.Created).ToList();
        Assert.Equal(5, created.Count);
        foreach (var rejected in responses.Except(created))
        {
            var problem = await rejected.ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.OrderItemsInvalid);
            Assert.Equal(ErrorCodes.ItemSoldOut, problem.GetProperty("items")[0].GetProperty("code").GetString());
        }

        var codes = new List<string>();
        foreach (var r in created) codes.Add((await r.ReadAsAsync<OrderDetailDto>(HttpStatusCode.Created)).PickupCode);
        Assert.Equal(["001", "002", "003", "004", "005"], codes.Order());
        Assert.Equal(5, await Factory.WithDbAsync(db => db.OrderItems.Where(i => i.FoodId == comGa).SumAsync(i => i.Quantity)));
    }

    [Fact]
    public async Task SangNgayMoi_MaNhanMonBatDauLai001()
    {
        var comTam = await FoodIdAsync(TestData.ComTam);
        await (await CreateAsync(AsStudent, [Line(comTam, 1)])).ShouldHaveStatusAsync(HttpStatusCode.Created);

        Factory.Clock.Advance(TimeSpan.FromDays(1));
        var order = await (await CreateAsync(AsStudent2, [Line(comTam, 1)])).ReadAsAsync<OrderDetailDto>(HttpStatusCode.Created);

        Assert.Equal(("001", new DateOnly(2026, 11, 17)), (order.PickupCode, order.PickupDate));
    }

    // ------------------------- Hỗ trợ -------------------------

    internal static CartLineRequest Line(int foodId, int quantity, params int[] optionIds) => new(foodId, quantity, [.. optionIds], null);

    internal static object Request(CartLineRequest[] items, string method = "cash", string? voucher = null,
        DateTimeOffset? pickupTime = null, string? note = null) =>
        new { items, voucherCode = voucher, paymentMethod = method, pickupTime, note };

    internal static Task<HttpResponseMessage> CreateAsync(HttpClient client, CartLineRequest[] items, string method = "cash",
        string? voucher = null, DateTimeOffset? pickupTime = null, string? note = null, string? key = null)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/orders")
        {
            Content = JsonContent.Create(Request(items, method, voucher, pickupTime, note), options: HttpExtensions.Json),
        };
        request.Headers.Add("Idempotency-Key", key ?? Guid.NewGuid().ToString());
        return client.SendAsync(request);
    }

    private Task<int> FoodIdAsync(string name) =>
        Factory.WithDbAsync(db => db.Foods.Where(f => f.Name == name).Select(f => f.Id).SingleAsync());

    private Task<Food> FoodAsync(string name) => Factory.WithDbAsync(db =>
        db.Foods.AsNoTracking().Include(f => f.OptionGroups).ThenInclude(g => g.Options).SingleAsync(f => f.Name == name));

    private static int OptionId(Food food, string name) =>
        food.OptionGroups.SelectMany(g => g.Options).Single(o => o.Name == name).Id;
}

/// <summary>Truy vấn đơn: quyền xem, đơn của tôi, bảng đơn của căn-tin.</summary>
public class OrderQueryTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    [Fact]
    public async Task ChiTiet_ChuDonVaStaffXemDuoc_NguoiKhac404()
    {
        var order = await PlaceAsync(AsStudent);

        await (await AsStudent.GetAsync($"/api/orders/{order.Id}")).ShouldHaveStatusAsync(HttpStatusCode.OK);
        var forStaff = await (await AsStaff.GetAsync($"/api/orders/{order.Id}")).ReadAsAsync<OrderDetailDto>();
        Assert.Equal(("Nguyễn Văn An", TestData.Student1Code), (forStaff.Customer.FullName, forStaff.Customer.StudentCode));

        await (await AsStudent2.GetAsync($"/api/orders/{order.Id}"))
            .ShouldBeProblemAsync(HttpStatusCode.NotFound, ErrorCodes.NotFound);
    }

    [Fact]
    public async Task DonCuaToi_LocTheoTrangThai_MoiNhatTruoc()
    {
        var now = CanteenApiFactory.Now.UtcDateTime;
        await TestOrders.AddAsync(Factory, TestData.ComTam, 1, now.AddDays(-2), OrderStatus.Completed);
        await TestOrders.AddAsync(Factory, TestData.NuocSuoi, 2, now.AddDays(-1), OrderStatus.Cancelled);
        var placed = await PlaceAsync(AsStudent);
        await PlaceAsync(AsStudent2); // đơn của người khác không lẫn vào

        var all = await ListMineAsync("");
        Assert.Equal(3, all.TotalCount);
        Assert.Equal(placed.Id, all.Items[0].Id);
        Assert.Equal("Cơm tấm sườn bì chả ×1", all.Items[0].ItemsPreview);

        Assert.Equal(placed.Id, Assert.Single((await ListMineAsync("status=active")).Items).Id);
        Assert.Equal(OrderStatus.Completed, Assert.Single((await ListMineAsync("status=completed")).Items).Status);
        Assert.Equal("Nước suối ×2", Assert.Single((await ListMineAsync("status=cancelled")).Items).ItemsPreview);
    }

    [Fact]
    public async Task BangDonStaff_TheoNgay_LocTrangThai_TimMaTenMssv()
    {
        var first = await PlaceAsync(AsStudent);
        await PlaceAsync(AsStudent2);
        await TestOrders.AddAsync(Factory, TestData.ComTam, 1, CanteenApiFactory.Now.UtcDateTime.AddDays(-1)); // hôm qua

        Assert.Equal(2, (await StaffListAsync("")).TotalCount);
        Assert.Equal(1, (await StaffListAsync("date=2026-11-15")).TotalCount);
        Assert.Equal(2, (await StaffListAsync("status=received&status=cooking")).TotalCount);
        Assert.Equal(0, (await StaffListAsync("status=ready")).TotalCount);

        foreach (var q in new[] { "%23001", "001", "nguyen van an", TestData.Student1Code })
            Assert.Equal(first.Id, Assert.Single((await StaffListAsync($"q={q}")).Items).Id);
    }

    [Fact]
    public async Task SinhVienKhongXemDuocBangDonStaff_403()
    {
        await (await AsStudent.GetAsync("/api/orders")).ShouldBeProblemAsync(HttpStatusCode.Forbidden, ErrorCodes.Forbidden);
    }

    private async Task<OrderDetailDto> PlaceAsync(HttpClient client)
    {
        var comTam = await Factory.WithDbAsync(db => db.Foods.Where(f => f.Name == TestData.ComTam).Select(f => f.Id).SingleAsync());
        return await (await CreateOrderTests.CreateAsync(client, [CreateOrderTests.Line(comTam, 1)]))
            .ReadAsAsync<OrderDetailDto>(HttpStatusCode.Created);
    }

    private async Task<PagedResult<OrderSummaryDto>> ListMineAsync(string query) =>
        await (await AsStudent.GetAsync($"/api/orders/me?{query}")).ReadAsAsync<PagedResult<OrderSummaryDto>>();

    private async Task<PagedResult<OrderSummaryDto>> StaffListAsync(string query) =>
        await (await AsStaff.GetAsync($"/api/orders?{query}")).ReadAsAsync<PagedResult<OrderSummaryDto>>();
}
