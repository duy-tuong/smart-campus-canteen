using System.Net;
using System.Net.Http.Json;
using CanteenApi.Common;
using CanteenApi.Dtos.Orders;
using CanteenApi.Models;
using CanteenApi.Services.Ordering;
using CanteenApi.Services.Payments;
using CanteenApi.Tests.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace CanteenApi.Tests.Api;

/// <summary>Thanh toán chuyển khoản (payOS): tạo link, webhook, đồng bộ chủ động, staff xác nhận, hủy và hoàn tiền.</summary>
public class PaymentTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    private const long FirstOrderCode = 2611160001; // yyMMdd(16/11/2026) × 10000 + #001

    // ------------------------- Tạo link thanh toán -------------------------

    [Fact]
    public async Task DatChuyenKhoan_TaoLinkPayOS_TraVeQrVaThongTinChuyenKhoan()
    {
        var order = await PlaceTransferAsync();

        Assert.Equal((PaymentMethod.BankTransfer, PaymentStatus.Pending), (order.PaymentMethod, order.PaymentStatus));
        var p = order.Payment!;
        Assert.Equal(("SC1160001", "0123456789", "CANTEEN DEMO", "970422"),
            (p.TransferContent, p.BankAccountNumber, p.BankAccountName, p.BankBin));
        Assert.StartsWith("https://pay.payos.vn/", p.CheckoutUrl);
        Assert.False(string.IsNullOrEmpty(p.QrCode));
        Assert.Equal(CanteenApiFactory.Now.UtcDateTime.AddMinutes(15), p.ExpiresAt);

        var link = Assert.Single(Factory.Payments.CreatedLinks);
        Assert.Equal((FirstOrderCode, 40_000, "SC1160001"), (link.OrderCode, link.Amount, link.Description));
        Assert.Contains($"/payment/result?orderId={order.Id}", link.ReturnUrl);
    }

    [Fact]
    public async Task PayOSLoi_502_DonTuHuy_HoanVoucher()
    {
        Factory.Payments.FailNextCreate = true;

        var response = await CreateOrderTests.CreateAsync(AsStudent, [await ComTamAsync(2)], "bankTransfer", voucher: TestData.Fixed5K);

        await response.ShouldBeProblemAsync(HttpStatusCode.BadGateway, ErrorCodes.PaymentProviderError);
        var order = await Factory.WithDbAsync(db => db.Orders.Include(o => o.StatusHistory).Include(o => o.Payments).SingleAsync());
        Assert.Equal((OrderStatus.Cancelled, PaymentStatus.Failed), (order.Status, order.PaymentStatus));
        Assert.Equal("Không tạo được thanh toán chuyển khoản", order.CancelReason);
        Assert.Null(order.StatusHistory.Single(h => h.ToStatus == OrderStatus.Cancelled).ChangedByUserId); // hệ thống
        Assert.Equal(PaymentStatus.Failed, Assert.Single(order.Payments).Status);
        Assert.Equal(0, await VoucherUsedAsync(TestData.Fixed5K));
    }

    // ------------------------- Webhook -------------------------

    [Fact]
    public async Task Webhook_HopLe_DonChuyenSangDaThanhToan()
    {
        var order = await PlaceTransferAsync();

        var response = await WebhookAsync(FirstOrderCode, 40_000, "FT26111600001");

        await response.ShouldHaveStatusAsync(HttpStatusCode.OK);
        var detail = await GetAsync(order.Id);
        Assert.Equal(PaymentStatus.Paid, detail.PaymentStatus);
        Assert.Equal(PaymentStatus.Paid, detail.Payment!.Status);
        Assert.Null(detail.Payment.QrCode); // đã trả → không hiện QR nữa
        Assert.Equal("FT26111600001", await Factory.WithDbAsync(db => db.Payments.Select(p => p.TransactionRef).SingleAsync()));
    }

    [Fact]
    public async Task Webhook_SaiChuKy_400_KhongDoiGi()
    {
        var order = await PlaceTransferAsync();

        var response = await WebhookAsync(FirstOrderCode, 40_000, "FT-GIA-MAO", signature: "chu-ky-gia");

        await response.ShouldBeProblemAsync(HttpStatusCode.BadRequest, ErrorCodes.InvalidWebhook);
        Assert.Equal(PaymentStatus.Pending, (await GetAsync(order.Id)).PaymentStatus);
    }

    [Fact]
    public async Task Webhook_GuiLaiNhieuLan_ChiGhiNhanMotLan()
    {
        await PlaceTransferAsync();

        for (var i = 0; i < 3; i++)
            await (await WebhookAsync(FirstOrderCode, 40_000, "FT-001")).ShouldHaveStatusAsync(HttpStatusCode.OK);

        Assert.Equal(1, await Factory.WithDbAsync(db => db.Payments.CountAsync(p => p.Status == PaymentStatus.Paid)));
    }

    [Fact]
    public async Task Webhook_ThieuTien_KhongChuyenPaid()
    {
        var order = await PlaceTransferAsync();

        await (await WebhookAsync(FirstOrderCode, 39_000, "FT-THIEU")).ShouldHaveStatusAsync(HttpStatusCode.OK);

        Assert.Equal(PaymentStatus.Pending, (await GetAsync(order.Id)).PaymentStatus);
    }

    [Fact]
    public async Task Webhook_OrderCodeKhongTonTai_VanTra200()
    {
        // Gói tin mẫu payOS gửi khi đăng ký webhook (confirm-webhook) mang orderCode không có trong hệ thống.
        await (await WebhookAsync(123, 3_000, "TEST")).ShouldHaveStatusAsync(HttpStatusCode.OK);
    }

    // ------------------------- Đồng bộ chủ động -------------------------

    [Fact]
    public async Task ToiDaChuyenKhoan_SyncNgay_DaThanhToan()
    {
        var order = await PlaceTransferAsync();
        var pending = await (await AsStudent.PostAsync($"/api/orders/{order.Id}/payment/sync", null)).ReadAsAsync<OrderDetailDto>();
        Assert.Equal(PaymentStatus.Pending, pending.PaymentStatus); // chưa trả

        Factory.Payments.SimulatePaid(FirstOrderCode, 40_000);
        var paid = await (await AsStudent.PostAsync($"/api/orders/{order.Id}/payment/sync", null)).ReadAsAsync<OrderDetailDto>();

        Assert.Equal(PaymentStatus.Paid, paid.PaymentStatus);
    }

    [Fact]
    public async Task Sync_DonCuaNguoiKhac_404()
    {
        var order = await PlaceTransferAsync();
        await (await AsStudent2.PostAsync($"/api/orders/{order.Id}/payment/sync", null))
            .ShouldBeProblemAsync(HttpStatusCode.NotFound, ErrorCodes.NotFound);
    }

    [Fact]
    public async Task Poller_XacNhanCacKhoanDaTra()
    {
        var mine = await PlaceTransferAsync();
        var other = await PlaceTransferAsync(AsStudent2);
        Factory.Payments.SimulatePaid(FirstOrderCode, 40_000);

        var confirmed = await Factory.Services.GetRequiredService<PaymentStatusPoller>().RunOnceAsync(default);

        Assert.Equal(1, confirmed);
        Assert.Equal(PaymentStatus.Paid, (await GetAsync(mine.Id)).PaymentStatus);
        Assert.Equal(PaymentStatus.Pending, (await GetAsync(other.Id, AsStudent2)).PaymentStatus);
    }

    [Fact]
    public async Task WebhookVaSyncCungLuc_ChiMotGiaoDichDuocGhiNhan()
    {
        var order = await PlaceTransferAsync();
        Factory.Payments.SimulatePaid(FirstOrderCode, 40_000, "FT-DONG-THOI");

        var tasks = Enumerable.Range(0, 6).Select(i => i % 2 == 0
            ? WebhookAsync(FirstOrderCode, 40_000, "FT-DONG-THOI")
            : AsStudent.PostAsync($"/api/orders/{order.Id}/payment/sync", null));
        var responses = await Task.WhenAll(tasks);

        Assert.All(responses, r => Assert.True(r.IsSuccessStatusCode, $"{(int)r.StatusCode}"));
        Assert.Equal(1, await Factory.WithDbAsync(db => db.Payments.CountAsync(p => p.Status == PaymentStatus.Paid)));
        Assert.Equal(PaymentStatus.Paid, (await GetAsync(order.Id)).PaymentStatus);
    }

    // ------------------------- Staff xác nhận tay -------------------------

    [Fact]
    public async Task StaffXacNhanTay_DaThanhToan_VaHuyLinkPayOS()
    {
        var order = await PlaceTransferAsync();

        await (await AsStudent.PostAsync($"/api/orders/{order.Id}/payment/confirm", null))
            .ShouldBeProblemAsync(HttpStatusCode.Forbidden, ErrorCodes.Forbidden);

        var detail = await (await AsStaff.PostAsync($"/api/orders/{order.Id}/payment/confirm", null)).ReadAsAsync<OrderDetailDto>();
        Assert.Equal(PaymentStatus.Paid, detail.PaymentStatus);
        Assert.Equal(FirstOrderCode, Assert.Single(Factory.Payments.CancelledLinks));
        Assert.StartsWith("MANUAL-", await Factory.WithDbAsync(db => db.Payments.Select(p => p.TransactionRef).SingleAsync()));

        await (await AsStaff.PostAsync($"/api/orders/{order.Id}/payment/confirm", null))
            .ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.PaymentNotPending);
    }

    // ------------------------- Hủy đơn & tiền về muộn -------------------------

    [Fact]
    public async Task HuyDonChuaTra_ThanhToanFailed_HuyLink_HoanVoucher()
    {
        var order = await PlaceTransferAsync(voucher: TestData.Fixed5K);
        Assert.Equal(1, await VoucherUsedAsync(TestData.Fixed5K));

        await CancelAsync(order.Id, "Đặt nhầm món");

        var detail = await GetAsync(order.Id);
        Assert.Equal((OrderStatus.Cancelled, PaymentStatus.Failed), (detail.Status, detail.PaymentStatus));
        Assert.Equal(FirstOrderCode, Assert.Single(Factory.Payments.CancelledLinks));
        Assert.Equal(0, await VoucherUsedAsync(TestData.Fixed5K));
    }

    [Fact]
    public async Task TienVeSauKhiDonDaHuy_GhiNhanCanHoanTien()
    {
        var order = await PlaceTransferAsync();
        await CancelAsync(order.Id, "Quá hạn thanh toán");

        await (await WebhookAsync(FirstOrderCode, 40_000, "FT-MUON")).ShouldHaveStatusAsync(HttpStatusCode.OK);

        var payments = await Factory.WithDbAsync(db => db.Payments.OrderBy(p => p.Id).ToListAsync());
        Assert.Equal([PaymentStatus.Paid, PaymentStatus.Refunded], payments.Select(p => p.Status));
        Assert.Equal(PaymentStatus.Refunded, (await GetAsync(order.Id)).PaymentStatus);
    }

    [Fact]
    public async Task HuyDonDaTra_GhiNhanHoanTien()
    {
        var order = await PlaceTransferAsync();
        await WebhookAsync(FirstOrderCode, 40_000, "FT-DA-TRA");

        await CancelAsync(order.Id, "Hết nguyên liệu", TestData.Staff);

        Assert.Equal(PaymentStatus.Refunded, (await GetAsync(order.Id)).PaymentStatus);
        Assert.Empty(Factory.Payments.CancelledLinks); // link đã trả, không cần hủy
    }

    // ------------------------- Hỗ trợ -------------------------

    private async Task<CartLineRequest> ComTamAsync(int quantity) => CreateOrderTests.Line(
        await Factory.WithDbAsync(db => db.Foods.Where(f => f.Name == TestData.ComTam).Select(f => f.Id).SingleAsync()), quantity);

    private async Task<OrderDetailDto> PlaceTransferAsync(HttpClient? client = null, string? voucher = null) =>
        await (await CreateOrderTests.CreateAsync(client ?? AsStudent, [await ComTamAsync(1)], "bankTransfer", voucher))
            .ReadAsAsync<OrderDetailDto>(HttpStatusCode.Created);

    private async Task<OrderDetailDto> GetAsync(string id, HttpClient? client = null) =>
        await (await (client ?? AsStudent).GetAsync($"/api/orders/{id}")).ReadAsAsync<OrderDetailDto>();

    private Task<HttpResponseMessage> WebhookAsync(long orderCode, long amount, string reference, string signature = FakePaymentGateway.ValidSignature) =>
        Anonymous.PostAsJsonAsync("/api/payments/payos/webhook", new
        {
            code = "00", desc = "success", success = true, signature,
            data = new { orderCode, amount, reference, code = "00" },
        });

    private Task<int> VoucherUsedAsync(string code) =>
        Factory.WithDbAsync(db => db.Vouchers.Where(v => v.Code == code).Select(v => v.UsedCount).SingleAsync());

    /// <summary>Hủy đơn qua OrderLifecycleService (API hủy đơn sẽ có ở Phần E4).</summary>
    private async Task CancelAsync(string orderId, string reason, string? actor = TestData.Student1)
    {
        await using var scope = Factory.Services.CreateAsyncScope();
        var lifecycle = scope.ServiceProvider.GetRequiredService<OrderLifecycleService>();
        var order = await lifecycle.LoadForUpdateAsync(orderId, default);
        await lifecycle.CancelAsync(order!, reason, actor, default);
    }
}
