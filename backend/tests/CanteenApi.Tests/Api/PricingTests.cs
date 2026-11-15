using System.Net;
using CanteenApi.Common;
using CanteenApi.Dtos.Orders;
using CanteenApi.Models;
using CanteenApi.Services.Ordering;
using CanteenApi.Tests.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace CanteenApi.Tests.Api;

/// <summary>Báo giá giỏ hàng: giá lấy từ database, kiểm tra tùy chọn, suất trong ngày, voucher.</summary>
public class QuoteTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    [Fact]
    public async Task TinhGiaTuDatabase_CoTuyChon()
    {
        var (comGa, traSua) = (await FoodAsync(TestData.ComGa), await FoodAsync(TestData.TraSua));
        var sizeL = OptionId(traSua, "L");
        var tranChau = OptionId(traSua, "Trân châu");

        var quote = await QuoteAsync(
            Line(comGa.Id, 2),
            Line(traSua.Id, 1, sizeL, tranChau) with { Note = " ít đá " });

        Assert.True(quote.CanOrder);
        Assert.Empty(quote.Errors);
        Assert.Equal(70_000, quote.Lines[0].LineTotal);
        var tea = quote.Lines[1];
        Assert.Equal((25_000, 11_000, 36_000, "ít đá"), (tea.UnitPrice, tea.OptionsPrice, tea.LineTotal, tea.Note));
        Assert.Equal(["Size", "Topping"], tea.Options.Select(o => o.GroupName));
        Assert.Equal((106_000, 106_000, 3), (quote.Subtotal, quote.TotalAmount, quote.TotalItems));
    }

    [Fact]
    public async Task ClientGuiGia_BiBoQua()
    {
        var comGa = await FoodAsync(TestData.ComGa);

        // Request "chế" thêm trường price/unitPrice/total: server không đọc các trường này.
        var response = await AsStudent.PostJsonAsync("/api/orders/quote", new
        {
            items = new[] { new { foodId = comGa.Id, quantity = 1, price = 1, unitPrice = 1 } },
            subtotal = 1,
            totalAmount = 1,
        });

        var quote = await response.ReadAsAsync<QuoteDto>();
        Assert.Equal(35_000, quote.TotalAmount);
    }

    [Theory]
    [InlineData(new string[0], "vui lòng chọn Size")]                    // thiếu nhóm bắt buộc
    [InlineData(new[] { "M", "L" }, "tối đa 1 Size")]                    // vượt MaxSelect
    [InlineData(new[] { "M", "Thạch (tạm hết)" }, "đang tạm hết")]       // tùy chọn tạm hết
    [InlineData(new[] { "M", "Trân châu", "Pudding", "Pudding" }, "trùng")] // chọn trùng
    public async Task TuyChonSai_LoiTheoDong(string[] optionNames, string expectedMessage)
    {
        var traSua = await FoodAsync(TestData.TraSua);
        var ids = optionNames.Select(n => OptionId(traSua, n)).ToArray();

        var quote = await QuoteAsync(Line(traSua.Id, 1, ids));

        Assert.False(quote.CanOrder);
        var error = Assert.Single(quote.Errors);
        Assert.Equal((0, ErrorCodes.OptionInvalid), (error.Index, error.Code));
        Assert.Contains(expectedMessage, error.Message);
    }

    [Fact]
    public async Task TuyChonCuaMonKhac_OptionInvalid()
    {
        var (comGa, traSua) = (await FoodAsync(TestData.ComGa), await FoodAsync(TestData.TraSua));

        var quote = await QuoteAsync(Line(comGa.Id, 1, OptionId(traSua, "M")));

        Assert.Equal(ErrorCodes.OptionInvalid, Assert.Single(quote.Errors).Code);
    }

    [Fact]
    public async Task MonAnHoacTamHet_ItemUnavailable_DongHopLeVanDuocTinh()
    {
        var hidden = await FoodAsync(TestData.HiddenFood);
        var comTam = await FoodAsync(TestData.ComTam);
        var water = await FoodAsync(TestData.NuocSuoi);
        await Factory.WithDbAsync(db => db.Foods.Where(f => f.Id == comTam.Id)
            .ExecuteUpdateAsync(s => s.SetProperty(f => f.IsAvailable, false)));

        var quote = await QuoteAsync(Line(hidden.Id, 1), Line(comTam.Id, 1), Line(water.Id, 2), Line(99999, 1));

        Assert.Equal([0, 1, 3], quote.Errors.Select(e => e.Index));
        Assert.All(quote.Errors, e => Assert.Equal(ErrorCodes.ItemUnavailable, e.Code));
        Assert.Equal(16_000, quote.Subtotal); // chỉ tính dòng hợp lệ
        Assert.False(quote.CanOrder);
    }

    [Fact]
    public async Task SuatHomNay_CongDonNhieuDongCungMon()
    {
        var comGa = await FoodAsync(TestData.ComGa); // DailyLimit = 60
        // Đã bán 58/60 (mỗi dòng đơn tối đa 50 — CHECK trong database — nên chia 2 đơn).
        await TestOrders.AddAsync(Factory, TestData.ComGa, 50, CanteenApiFactory.Now.UtcDateTime.AddHours(-2));
        await TestOrders.AddAsync(Factory, TestData.ComGa, 8, CanteenApiFactory.Now.UtcDateTime.AddHours(-1));

        var ok = await QuoteAsync(Line(comGa.Id, 1), Line(comGa.Id, 1) with { Note = "không hành" });
        Assert.True(ok.CanOrder);

        var tooMany = await QuoteAsync(Line(comGa.Id, 2), Line(comGa.Id, 1) with { Note = "không hành" });
        Assert.Equal(2, tooMany.Errors.Count);
        Assert.All(tooMany.Errors, e => Assert.Equal((ErrorCodes.ItemSoldOut, 2), (e.Code, e.Remaining)));
    }

    [Fact]
    public async Task GioHangRong_400()
    {
        var response = await AsStudent.PostJsonAsync("/api/orders/quote", new QuoteRequest([], null));
        await response.ShouldBeProblemAsync(HttpStatusCode.BadRequest, ErrorCodes.ValidationError);
    }

    [Fact]
    public async Task SoLuong0_400()
    {
        var comGa = await FoodAsync(TestData.ComGa);
        var response = await AsStudent.PostJsonAsync("/api/orders/quote", new QuoteRequest([Line(comGa.Id, 0)], null));
        await response.ShouldBeProblemAsync(HttpStatusCode.BadRequest, ErrorCodes.ValidationError);
    }

    // ------------------------- Voucher trong báo giá -------------------------

    [Fact]
    public async Task VoucherPhanTram_DuocGiam_KhongPhanBietHoaThuong()
    {
        var comGa = await FoodAsync(TestData.ComGa);

        var quote = await QuoteAsync([Line(comGa.Id, 2)], "tansv10");

        Assert.True(quote.Voucher!.IsValid);
        Assert.Equal((70_000, 7_000, 63_000), (quote.Subtotal, quote.DiscountAmount, quote.TotalAmount));
    }

    [Fact]
    public async Task VoucherPhanTram_KhongVuotMaxDiscount()
    {
        var comTam = await FoodAsync(TestData.ComTam);

        var quote = await QuoteAsync([Line(comTam.Id, 5)], TestData.Percent10); // 10% của 200k = 20k > max 15k

        Assert.Equal(15_000, quote.DiscountAmount);
    }

    [Theory]
    [InlineData(TestData.Expired, ErrorCodes.VoucherExpired)]
    [InlineData(TestData.NotStarted, ErrorCodes.VoucherExpired)]
    [InlineData(TestData.Inactive, ErrorCodes.VoucherInvalid)]
    [InlineData("KHONGCO", ErrorCodes.VoucherInvalid)]
    [InlineData(TestData.Exhausted, ErrorCodes.VoucherExhausted)]
    public async Task VoucherKhongDung_KhongGiam_NhungVanDatDuoc(string code, string expectedError)
    {
        var comTam = await FoodAsync(TestData.ComTam);

        var quote = await QuoteAsync([Line(comTam.Id, 2)], code);

        Assert.False(quote.Voucher!.IsValid);
        Assert.Equal(expectedError, quote.Voucher.ErrorCode);
        Assert.Equal(0, quote.DiscountAmount);
        Assert.True(quote.CanOrder);
    }

    [Fact]
    public async Task VoucherChuaDuGiaTriToiThieu_BaoSoTienConThieu()
    {
        var water = await FoodAsync(TestData.NuocSuoi);

        var quote = await QuoteAsync([Line(water.Id, 3)], TestData.Fixed5K); // 24k < 40k

        Assert.Equal(ErrorCodes.VoucherMinOrder, quote.Voucher!.ErrorCode);
        Assert.Contains("16.000", quote.Voucher.Message.Replace(',', '.'));
    }

    [Fact]
    public async Task VoucherHetLuotCuaToi_DonHuyKhongTinh()
    {
        var comTam = await FoodAsync(TestData.ComTam);
        var now = CanteenApiFactory.Now.UtcDateTime;
        await TestOrders.AddAsync(Factory, TestData.ComTam, 1, now.AddDays(-1), voucherCode: TestData.Percent10);
        await TestOrders.AddAsync(Factory, TestData.ComTam, 1, now.AddDays(-1), OrderStatus.Cancelled, voucherCode: TestData.Percent10);

        Assert.True((await QuoteAsync([Line(comTam.Id, 1)], TestData.Percent10)).Voucher!.IsValid); // 1/2 lượt

        await TestOrders.AddAsync(Factory, TestData.ComTam, 1, now.AddHours(-2), voucherCode: TestData.Percent10);
        var quote = await QuoteAsync([Line(comTam.Id, 1)], TestData.Percent10);
        Assert.Equal(ErrorCodes.VoucherUserLimit, quote.Voucher!.ErrorCode);

        // Người khác vẫn dùng được.
        var other = await (await AsStudent2.PostJsonAsync("/api/orders/quote",
            new QuoteRequest([Line(comTam.Id, 1)], TestData.Percent10))).ReadAsAsync<QuoteDto>();
        Assert.True(other.Voucher!.IsValid);
    }

    // ------------------------- Hỗ trợ -------------------------

    private Task<QuoteDto> QuoteAsync(params CartLineRequest[] lines) => QuoteAsync(lines, null);

    private async Task<QuoteDto> QuoteAsync(CartLineRequest[] lines, string? voucher) =>
        await (await AsStudent.PostJsonAsync("/api/orders/quote", new QuoteRequest([.. lines], voucher)))
            .ReadAsAsync<QuoteDto>();

    private static CartLineRequest Line(int foodId, int quantity, params int[] optionIds) =>
        new(foodId, quantity, [.. optionIds], null);

    private Task<Food> FoodAsync(string name) => Factory.WithDbAsync(db =>
        db.Foods.AsNoTracking().Include(f => f.OptionGroups).ThenInclude(g => g.Options).SingleAsync(f => f.Name == name));

    private static int OptionId(Food food, string name) =>
        food.OptionGroups.SelectMany(g => g.Options).Single(o => o.Name == name).Id;
}

/// <summary>Quy tắc tính tiền giảm (unit test thuần, không cần database).</summary>
public class DiscountCalculationTests
{
    [Theory]
    [InlineData(35_550, 10, null, 3_500)]    // 3.555 → làm tròn xuống 100đ
    [InlineData(200_000, 10, 15_000, 15_000)] // chạm mức giảm tối đa
    [InlineData(1_000, 100, null, 1_000)]    // giảm 100% = tạm tính
    public void Percent(int subtotal, int percent, int? max, int expected) =>
        Assert.Equal(expected, VoucherService.CalculateDiscount(
            new Voucher { DiscountType = DiscountType.Percent, DiscountValue = percent, MaxDiscount = max }, subtotal));

    [Fact]
    public void Fixed_KhongVuotTamTinh() =>
        Assert.Equal(3_000, VoucherService.CalculateDiscount(
            new Voucher { DiscountType = DiscountType.Fixed, DiscountValue = 5_000 }, 3_000));
}

/// <summary>Voucher: danh sách cho sinh viên, quản lý cho staff/admin, giữ lượt an toàn khi chạy song song.</summary>
public class VoucherApiTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    [Fact]
    public async Task SinhVien_ChiThayVoucherDungDuoc()
    {
        var list = await (await AsStudent.GetAsync("/api/vouchers/available")).ReadAsAsync<List<AvailableVoucherDto>>();

        Assert.Equal([TestData.Fixed5K, TestData.Percent10], list.Select(v => v.Code)); // sắp hết hạn trước
        Assert.Equal(2, list.Single(v => v.Code == TestData.Percent10).RemainingForMe);
        Assert.Null(list.Single(v => v.Code == TestData.Fixed5K).RemainingForMe);
    }

    [Fact]
    public async Task SinhVien_KhongVaoDuocTrangQuanLy()
    {
        var response = await AsStudent.GetAsync("/api/admin/vouchers");
        await response.ShouldBeProblemAsync(HttpStatusCode.Forbidden, ErrorCodes.Forbidden);
    }

    [Fact]
    public async Task TaoVoucher_MaVietHoa_201_TrungMa_409()
    {
        var created = await (await AsStaff.PostJsonAsync("/api/admin/vouchers", NewVoucher("trasua20")))
            .ReadAsAsync<VoucherDto>(HttpStatusCode.Created);
        Assert.Equal("TRASUA20", created.Code);
        // JSON trả về dạng "...Z" → đọc ra DateTime Kind=Utc (không bị hiểu nhầm là giờ địa phương).
        Assert.Equal(DateTimeKind.Utc, created.StartAt.Kind);

        await (await AsStaff.PostJsonAsync("/api/admin/vouchers", NewVoucher("TraSua20")))
            .ShouldBeProblemAsync(HttpStatusCode.Conflict, ErrorCodes.VoucherCodeTaken);
    }

    [Theory]
    [InlineData("percent", 150, null, 1, "DiscountValue")] // % > 100
    [InlineData("fixed", 5000, 10000, 1, "MaxDiscount")]   // max chỉ dùng cho %
    [InlineData("percent", 10, null, -1, "EndAt")]         // kết thúc trước bắt đầu
    public async Task TaoVoucher_DuLieuSai_400(string type, int value, int? max, int days, string field)
    {
        var start = CanteenApiFactory.Now;
        var response = await AsStaff.PostJsonAsync("/api/admin/vouchers", new
        {
            code = "SAI01", description = "Voucher sai", discountType = type, discountValue = value, maxDiscount = max,
            minOrderAmount = 0, startAt = start, endAt = start.AddDays(days),
        });

        var problem = await response.ShouldBeProblemAsync(HttpStatusCode.BadRequest, ErrorCodes.ValidationError);
        Assert.True(problem.GetProperty("errors").TryGetProperty(field, out _), $"Thiếu lỗi cho {field}");
    }

    [Fact]
    public async Task SuaVoucher_RowVersionCu_409()
    {
        var voucher = await GetByCodeAsync(TestData.Fixed5K);

        await (await AsStaff.PutJsonAsync($"/api/admin/vouchers/{voucher.Id}", EditOf(voucher, minOrder: 30_000)))
            .ShouldHaveStatusAsync(HttpStatusCode.OK);
        await (await AsStaff.PutJsonAsync($"/api/admin/vouchers/{voucher.Id}", EditOf(voucher, minOrder: 10_000)))
            .ShouldBeProblemAsync(HttpStatusCode.Conflict, ErrorCodes.ConcurrencyConflict);
    }

    [Fact]
    public async Task VoucherDaDung_KhongDoiMa_KhongXoa_NhungTatDuoc()
    {
        await TestOrders.AddAsync(Factory, TestData.ComTam, 1, CanteenApiFactory.Now.UtcDateTime.AddHours(-1),
            voucherCode: TestData.Fixed5K);
        var voucher = await GetByCodeAsync(TestData.Fixed5K);
        Assert.Equal(1, voucher.OrderCount);

        await (await AsStaff.PutJsonAsync($"/api/admin/vouchers/{voucher.Id}", EditOf(voucher) with { Code = "MAMOI" }))
            .ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.VoucherInUse);
        await (await AsStaff.DeleteAsync($"/api/admin/vouchers/{voucher.Id}"))
            .ShouldBeProblemAsync(HttpStatusCode.Conflict, ErrorCodes.VoucherInUse);

        var disabled = await (await AsStaff.PatchJsonAsync($"/api/admin/vouchers/{voucher.Id}/status", new { isActive = false }))
            .ReadAsAsync<VoucherDto>();
        Assert.False(disabled.IsActive);
    }

    [Fact]
    public async Task VoucherChuaDung_XoaDuoc_204()
    {
        var voucher = await GetByCodeAsync(TestData.NotStarted);
        await (await AsAdmin.DeleteAsync($"/api/admin/vouchers/{voucher.Id}")).ShouldHaveStatusAsync(HttpStatusCode.NoContent);
        Assert.False(await Factory.WithDbAsync(db => db.Vouchers.AnyAsync(v => v.Id == voucher.Id)));
    }

    [Fact]
    public async Task GiuLuot_10YeuCauSongSong_ChiDung3Luot()
    {
        var voucherId = await Factory.WithDbAsync(async db =>
        {
            var v = await db.Vouchers.SingleAsync(x => x.Code == TestData.Fixed5K);
            v.UsageLimit = 3;
            await db.SaveChangesAsync();
            return v.Id;
        });

        // Mỗi "request" dùng scope (DbContext) riêng như request thật.
        var results = await Task.WhenAll(Enumerable.Range(0, 10).Select(async _ =>
        {
            await using var scope = Factory.Services.CreateAsyncScope();
            return await scope.ServiceProvider.GetRequiredService<VoucherService>().TryConsumeAsync(voucherId, default);
        }));

        Assert.Equal(3, results.Count(ok => ok));
        Assert.Equal(3, await Factory.WithDbAsync(db => db.Vouchers.Where(v => v.Id == voucherId).Select(v => v.UsedCount).SingleAsync()));
    }

    private async Task<VoucherDto> GetByCodeAsync(string code)
    {
        var page = await (await AsStaff.GetAsync($"/api/admin/vouchers?q={code}")).ReadAsAsync<PagedResult<VoucherDto>>();
        return page.Items.Single(v => v.Code == code);
    }

    private static SaveVoucherRequest NewVoucher(string code) => new(
        code, "Giảm 20% trà sữa", DiscountType.Percent, 20, 10_000, 20_000,
        CanteenApiFactory.Now, CanteenApiFactory.Now.AddDays(10), 50, 1, true, null);

    private static SaveVoucherRequest EditOf(VoucherDto v, int? minOrder = null) => new(
        v.Code, v.Description, v.DiscountType, v.DiscountValue, v.MaxDiscount, minOrder ?? v.MinOrderAmount,
        new DateTimeOffset(v.StartAt), new DateTimeOffset(v.EndAt), v.UsageLimit, v.PerUserLimit, v.IsActive, v.RowVersion);
}
