using System.Net;
using System.Net.Http.Json;
using CanteenApi.Common;
using CanteenApi.Dtos.Orders;
using CanteenApi.Models;
using CanteenApi.Services.Notifications;
using CanteenApi.Services.Ordering;
using CanteenApi.Services.Realtime;
using CanteenApi.Tests.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace CanteenApi.Tests.Api;

/// <summary>Luồng trạng thái đơn, hủy đơn, tự hủy đơn quá hạn, thông báo và đồng bộ realtime.</summary>
public class LifecycleTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    private const long FirstOrderCode = 261116100000001; // yyMMddHHmmss × 1000 + #001

    // ------------------------- Chuyển trạng thái -------------------------

    [Fact]
    public async Task LuongDayDu_TienMat_ThongBaoVaRealtimeMoiBuoc()
    {
        var order = await PlaceAsync();
        var staff = AsStaff;

        foreach (var (to, expected) in new[] { ("cooking", OrderStatus.Cooking), ("ready", OrderStatus.Ready), ("completed", OrderStatus.Completed) })
        {
            var detail = await (await staff.PatchJsonAsync($"/api/orders/{order.Id}/status", new { status = to }))
                .ReadAsAsync<OrderDetailDto>();
            Assert.Equal(expected, detail.Status);
        }

        var final = await GetAsync(order.Id, staff);
        Assert.Equal(
            [OrderStatus.Received, OrderStatus.Cooking, OrderStatus.Ready, OrderStatus.Completed],
            final.History.Select(h => h.ToStatus));
        Assert.Equal("Nhân viên căn-tin", final.History.Last().ChangedByName);
        Assert.Empty(final.AllowedNextStatuses);

        // Tiền mặt: hoàn thành = đã thu tiền tại quầy.
        Assert.Equal(PaymentStatus.Paid, final.PaymentStatus);
        Assert.Equal("CASH-261116-001", await Factory.WithDbAsync(db => db.Payments.Select(p => p.TransactionRef).SingleAsync()));

        // Sinh viên nhận 4 thông báo: đặt món, đang nấu, mời nhận món, hoàn thành.
        var notifications = await (await AsStudent.GetAsync("/api/notifications")).ReadAsAsync<NotificationListDto>();
        Assert.Equal(4, notifications.UnreadCount);
        Assert.Equal("Mời bạn nhận món", notifications.Items[1].Title);
        Assert.All(notifications.Items, n => Assert.Equal(order.Id, n.RefId));

        // Mỗi thay đổi đều được đưa lên hàng đợi realtime.
        Assert.Equal(4, Factory.Realtime.Orders.Count(id => id == order.Id));
        Assert.Equal(4, Factory.Realtime.Notifications.Count);
    }

    [Fact]
    public async Task StaffThayNutTiepTheo_SinhVienKhong()
    {
        var order = await PlaceAsync();
        Assert.Equal([OrderStatus.Cooking], (await GetAsync(order.Id, AsStaff)).AllowedNextStatuses);
        Assert.Empty((await GetAsync(order.Id, AsStudent)).AllowedNextStatuses);
    }

    [Theory]
    [InlineData("ready")]
    [InlineData("completed")]
    [InlineData("cancelled")]
    [InlineData("received")]
    public async Task ChuyenSaiThuTu_422_KemTrangThaiDuocPhep(string to)
    {
        var order = await PlaceAsync();

        var response = await AsStaff.PatchJsonAsync($"/api/orders/{order.Id}/status", new { status = to });

        var problem = await response.ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.InvalidStatusTransition);
        if (to != "cancelled")
            Assert.Equal("cooking", Assert.Single(problem.GetProperty("allowedStatuses").EnumerateArray()).GetString());
    }

    [Fact]
    public async Task SinhVienKhongDuocDoiTrangThai_403()
    {
        var order = await PlaceAsync();
        await (await AsStudent.PatchJsonAsync($"/api/orders/{order.Id}/status", new { status = "cooking" }))
            .ShouldBeProblemAsync(HttpStatusCode.Forbidden, ErrorCodes.Forbidden);
    }

    [Fact]
    public async Task ChuyenKhoanChuaTra_KhongDuocNau_TraXongThiNauDuoc()
    {
        var order = await PlaceAsync("bankTransfer");

        await (await AsStaff.PatchJsonAsync($"/api/orders/{order.Id}/status", new { status = "cooking" }))
            .ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.PaymentRequired);

        await Anonymous.PostAsJsonAsync("/api/payments/payos/webhook", new
        {
            signature = FakePaymentGateway.ValidSignature,
            data = new { orderCode = FirstOrderCode, amount = 40_000, reference = "FT-E4", code = "00" },
        });

        await (await AsStaff.PatchJsonAsync($"/api/orders/{order.Id}/status", new { status = "cooking" }))
            .ShouldHaveStatusAsync(HttpStatusCode.OK);
        var titles = (await (await AsStudent.GetAsync("/api/notifications")).ReadAsAsync<NotificationListDto>())
            .Items.Select(n => n.Title).ToList();
        Assert.Contains("Đã nhận thanh toán #001", titles);
    }

    [Fact]
    public async Task HaiStaffBamCungLuc_ChiMotNguoiThanhCong()
    {
        var order = await PlaceAsync();

        var responses = await Task.WhenAll(Enumerable.Range(0, 5).Select(_ =>
            AsStaff.PatchJsonAsync($"/api/orders/{order.Id}/status", new { status = "cooking" })));

        Assert.Equal(1, responses.Count(r => r.StatusCode == HttpStatusCode.OK));
        Assert.All(responses.Where(r => r.StatusCode != HttpStatusCode.OK),
            r => Assert.Contains(r.StatusCode, new[] { HttpStatusCode.Conflict, HttpStatusCode.UnprocessableEntity }));
        Assert.Equal(1, await Factory.WithDbAsync(db => db.OrderStatusHistory.CountAsync(h => h.ToStatus == OrderStatus.Cooking)));
    }

    // ------------------------- Hủy đơn -------------------------

    [Fact]
    public async Task SinhVienHuyDonCuaMinh_KhiDaNhan_HoanVoucher_KhongTuThongBao()
    {
        var order = await PlaceAsync(voucher: TestData.Fixed5K, quantity: 2);

        var detail = await (await AsStudent.PostAsJsonAsync($"/api/orders/{order.Id}/cancel", new { reason = "Đổi ý, không ăn nữa" }))
            .ReadAsAsync<OrderDetailDto>();

        Assert.Equal((OrderStatus.Cancelled, "Đổi ý, không ăn nữa", false), (detail.Status, detail.CancelReason, detail.CanCancel));
        Assert.Equal(0, await Factory.WithDbAsync(db => db.Vouchers.Where(v => v.Code == TestData.Fixed5K).Select(v => v.UsedCount).SingleAsync()));
        // Chỉ có thông báo "đặt món thành công" — tự hủy thì không báo lại.
        Assert.Equal(1, (await (await AsStudent.GetAsync("/api/notifications")).ReadAsAsync<NotificationListDto>()).TotalCount);
    }

    [Fact]
    public async Task SinhVienKhongHuyDuocKhiDangNau_StaffHuyDuoc_CoThongBaoLyDo()
    {
        var order = await PlaceAsync();
        await AsStaff.PatchJsonAsync($"/api/orders/{order.Id}/status", new { status = "cooking" });

        await (await AsStudent.PostAsJsonAsync($"/api/orders/{order.Id}/cancel", new { reason = "Đợi lâu quá" }))
            .ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.OrderNotCancellable);

        await (await AsStaff.PostAsJsonAsync($"/api/orders/{order.Id}/cancel", new { reason = "Hết nguyên liệu" }))
            .ShouldHaveStatusAsync(HttpStatusCode.OK);
        var latest = (await (await AsStudent.GetAsync("/api/notifications")).ReadAsAsync<NotificationListDto>()).Items[0];
        Assert.Equal(("Đơn #001 đã bị hủy", "Lý do: Hết nguyên liệu."), (latest.Title, latest.Body));
    }

    [Fact]
    public async Task HuyDon_LyDoQuaNgan_400_NguoiKhac_404_DaHoanThanh_422()
    {
        var order = await PlaceAsync();

        await (await AsStudent.PostAsJsonAsync($"/api/orders/{order.Id}/cancel", new { reason = "x" }))
            .ShouldBeProblemAsync(HttpStatusCode.BadRequest, ErrorCodes.ValidationError);
        await (await AsStudent2.PostAsJsonAsync($"/api/orders/{order.Id}/cancel", new { reason = "Hủy giùm bạn" }))
            .ShouldBeProblemAsync(HttpStatusCode.NotFound, ErrorCodes.NotFound);

        foreach (var s in new[] { "cooking", "ready", "completed" })
            await AsStaff.PatchJsonAsync($"/api/orders/{order.Id}/status", new { status = s });
        await (await AsStaff.PostAsJsonAsync($"/api/orders/{order.Id}/cancel", new { reason = "Thử hủy đơn xong" }))
            .ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.OrderNotCancellable);
    }

    // ------------------------- Tự hủy đơn chuyển khoản quá hạn -------------------------

    [Fact]
    public async Task QuaHan15Phut_TuHuy_DoHeThong_HoanSuat()
    {
        var order = await PlaceAsync("bankTransfer");
        var cash = await PlaceAsync(client: AsStudent2);
        var canceller = Factory.Services.GetRequiredService<UnpaidOrderCanceller>();

        Factory.Clock.Advance(TimeSpan.FromMinutes(14));
        Assert.Equal(0, await canceller.RunOnceAsync(default)); // chưa quá hạn

        Factory.Clock.Advance(TimeSpan.FromMinutes(2));
        Assert.Equal(1, await canceller.RunOnceAsync(default));

        var detail = await GetAsync(order.Id, AsStaff);
        Assert.Equal((OrderStatus.Cancelled, UnpaidOrderCanceller.ExpiredReason), (detail.Status, detail.CancelReason));
        Assert.Equal("Hệ thống", detail.History.Last().ChangedByName);
        Assert.Contains(FirstOrderCode, Factory.Payments.CancelledLinks);
        Assert.Equal(OrderStatus.Received, (await GetAsync(cash.Id, AsStaff)).Status); // đơn tiền mặt không bị ảnh hưởng
        Assert.Equal("Đơn #001 đã bị hủy",
            (await (await AsStudent.GetAsync("/api/notifications")).ReadAsAsync<NotificationListDto>()).Items[0].Title);
    }

    [Fact]
    public async Task QuaHanNhungKhachVuaTra_KhongHuy_MaGhiNhanDaTra()
    {
        var order = await PlaceAsync("bankTransfer");
        Factory.Payments.SimulatePaid(FirstOrderCode, 40_000);
        Factory.Clock.Advance(TimeSpan.FromMinutes(20));

        Assert.Equal(0, await Factory.Services.GetRequiredService<UnpaidOrderCanceller>().RunOnceAsync(default));

        var detail = await GetAsync(order.Id, AsStaff);
        Assert.Equal((OrderStatus.Received, PaymentStatus.Paid), (detail.Status, detail.PaymentStatus));
    }

    // ------------------------- Thông báo -------------------------

    [Fact]
    public async Task ThongBao_DanhDauDaDoc_TungCaiVaTatCa()
    {
        var order = await PlaceAsync();
        await AsStaff.PatchJsonAsync($"/api/orders/{order.Id}/status", new { status = "cooking" });
        var list = await (await AsStudent.GetAsync("/api/notifications")).ReadAsAsync<NotificationListDto>();
        Assert.Equal(2, list.UnreadCount);

        await (await AsStudent2.PatchAsync($"/api/notifications/{list.Items[0].Id}/read", null))
            .ShouldBeProblemAsync(HttpStatusCode.NotFound, ErrorCodes.NotFound); // không đọc được thông báo của người khác

        await (await AsStudent.PatchAsync($"/api/notifications/{list.Items[0].Id}/read", null)).ShouldHaveStatusAsync(HttpStatusCode.NoContent);
        Assert.Equal(1, (await (await AsStudent.GetAsync("/api/notifications")).ReadAsAsync<NotificationListDto>()).UnreadCount);
        Assert.Contains(list.Items[0].Id, Factory.Realtime.Notifications);

        await (await AsStudent.PostAsync("/api/notifications/read-all", null)).ShouldHaveStatusAsync(HttpStatusCode.OK);
        Assert.Equal(0, (await (await AsStudent.GetAsync("/api/notifications")).ReadAsAsync<NotificationListDto>()).UnreadCount);
        Assert.Contains(TestData.Student1, Factory.Realtime.ReadAll);
    }

    // ------------------------- Dữ liệu realtime -------------------------

    [Fact]
    public async Task DuLieuFirebase_EnumDangChuoi_ThoiGianEpoch_TomTatMon()
    {
        var traSua = await Factory.WithDbAsync(db => db.Foods.Include(f => f.OptionGroups).ThenInclude(g => g.Options)
            .SingleAsync(f => f.Name == TestData.TraSua));
        var options = traSua.OptionGroups.SelectMany(g => g.Options).Where(o => o.Name is "L" or "Pudding").Select(o => o.Id).ToArray();
        var order = await (await CreateOrderTests.CreateAsync(AsStudent, [CreateOrderTests.Line(traSua.Id, 2, options)], note: "Ít đá"))
            .ReadAsAsync<OrderDetailDto>(HttpStatusCode.Created);

        var payload = await Factory.WithDbAsync(async db => RealtimeSyncService.OrderPayload(await db.Orders
            .Include(o => o.User).Include(o => o.Items).ThenInclude(i => i.Options).SingleAsync(o => o.Id == order.Id)));

        Assert.Equal(("received", "cash", "pending", "001", TestData.Student1),
            (payload["status"], payload["paymentMethod"], payload["paymentStatus"], payload["pickupCode"], payload["userId"]));
        Assert.Equal(2, payload["totalItems"]);
        var item = Assert.Single((List<Dictionary<string, object?>>)payload["items"]!);
        Assert.Equal(("Trà sữa trân châu", 2, "L, Pudding"), (item["name"], item["quantity"], item["options"]));
        Assert.Equal(CanteenApiFactory.Now.ToUnixTimeMilliseconds(), payload["createdAt"]);
    }

    [Fact]
    public void KhoaThongBaoTrenFirebase_CoTienTo_DeKhongBiDoiThanhMang() =>
        // Khóa toàn số liên tiếp (1, 2, 3...) bị Realtime Database trả về dạng MẢNG → app lúc nhận Map lúc nhận List.
        Assert.Equal("n12", RealtimeSyncService.NotificationKey(12));

    // ------------------------- Hỗ trợ -------------------------

    private async Task<OrderDetailDto> PlaceAsync(string method = "cash", string? voucher = null, int quantity = 1, HttpClient? client = null)
    {
        var comTam = await Factory.WithDbAsync(db => db.Foods.Where(f => f.Name == TestData.ComTam).Select(f => f.Id).SingleAsync());
        return await (await CreateOrderTests.CreateAsync(client ?? AsStudent, [CreateOrderTests.Line(comTam, quantity)], method, voucher))
            .ReadAsAsync<OrderDetailDto>(HttpStatusCode.Created);
    }

    private static async Task<OrderDetailDto> GetAsync(string id, HttpClient client) =>
        await (await client.GetAsync($"/api/orders/{id}")).ReadAsAsync<OrderDetailDto>();
}
