using System.Net;
using CanteenApi.Common;
using CanteenApi.Dtos.Menu;
using CanteenApi.Models;
using CanteenApi.Tests.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace CanteenApi.Tests.Api;

/// <summary>Danh mục: hiển thị theo vai trò, trùng tên, sắp xếp, xóa mềm.</summary>
public class CategoriesTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    [Fact]
    public async Task SinhVien_ChiThayDanhMucDangHien_DungThuTu()
    {
        var list = await (await AsStudent.GetAsync("/api/categories?includeInactive=true")) // tham số bị bỏ qua với sinh viên
            .ReadAsAsync<List<CategoryDto>>();

        Assert.Equal([TestData.Rice, TestData.Drinks], list.Select(c => c.Name));
        Assert.Equal(2, list[0].FoodCount);
    }

    [Fact]
    public async Task Staff_IncludeInactive_ThayCaDanhMucAn()
    {
        var list = await (await AsStaff.GetAsync("/api/categories?includeInactive=true"))
            .ReadAsAsync<List<CategoryDto>>();

        Assert.Contains(list, c => c.Name == TestData.HiddenCategory && !c.IsActive);
    }

    [Theory]
    [InlineData("com")]   // không dấu
    [InlineData(" CƠM ")] // hoa thường + khoảng trắng
    public async Task TaoDanhMuc_TrungTen_409(string name)
    {
        var response = await AsStaff.PostJsonAsync("/api/categories", new SaveCategoryRequest(name, null, "rice_bowl", 9, true));
        await response.ShouldBeProblemAsync(HttpStatusCode.Conflict, ErrorCodes.CategoryNameTaken);
    }

    [Fact]
    public async Task TaoDanhMuc_201_CoLocation()
    {
        var response = await AsStaff.PostJsonAsync("/api/categories", new SaveCategoryRequest("Món chay", "Thuần chay", "eco", 5, null));

        var created = await response.ReadAsAsync<CategoryDto>(HttpStatusCode.Created);
        Assert.True(created.IsActive);
        Assert.EndsWith($"/api/categories/{created.Id}", response.Headers.Location?.ToString());
    }

    [Fact]
    public async Task SapXepLai()
    {
        var categories = await Factory.WithDbAsync(db => db.Categories.ToDictionaryAsync(c => c.Name, c => c.Id));

        var list = await (await AsStaff.PutJsonAsync("/api/categories/order", new ReorderCategoriesRequest(
            [new CategoryOrderItem(categories[TestData.Drinks], 0), new CategoryOrderItem(categories[TestData.Rice], 1)])))
            .ReadAsAsync<List<CategoryDto>>();

        Assert.Equal(TestData.Drinks, list[0].Name);
    }

    [Fact]
    public async Task XoaDanhMucConMon_409_XoaHetMonRoiXoa_204_TaoLaiCungTen_201()
    {
        var riceId = await Factory.WithDbAsync(db => db.Categories.Where(c => c.Name == TestData.Rice).Select(c => c.Id).SingleAsync());

        await (await AsStaff.DeleteAsync($"/api/categories/{riceId}"))
            .ShouldBeProblemAsync(HttpStatusCode.Conflict, ErrorCodes.CategoryNotEmpty);

        var foodIds = await Factory.WithDbAsync(db => db.Foods.Where(f => f.CategoryId == riceId).Select(f => f.Id).ToListAsync());
        foreach (var id in foodIds)
            await (await AsStaff.DeleteAsync($"/api/foods/{id}")).ShouldHaveStatusAsync(HttpStatusCode.NoContent);

        await (await AsStaff.DeleteAsync($"/api/categories/{riceId}")).ShouldHaveStatusAsync(HttpStatusCode.NoContent);
        Assert.True(await Factory.WithDbAsync(db => db.Categories.Where(c => c.Id == riceId).Select(c => c.IsDeleted).SingleAsync()));

        // UNIQUE có lọc IsDeleted = 0 → tạo lại cùng tên được.
        await (await AsStaff.PostJsonAsync("/api/categories", new SaveCategoryRequest(TestData.Rice, null, "rice_bowl", 1, true)))
            .ShouldHaveStatusAsync(HttpStatusCode.Created);
    }
}

/// <summary>Món ăn: tìm/lọc/sắp xếp, suất trong ngày, tùy chọn, sửa đồng thời, xóa mềm, yêu thích.</summary>
public class FoodsTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    // ------------------------- Đọc -------------------------

    [Fact]
    public async Task SinhVien_KhongThayMonTrongDanhMucAn()
    {
        var page = await ListAsync(AsStudent, "");

        Assert.Equal(4, page.TotalCount);
        Assert.DoesNotContain(page.Items, f => f.Name == TestData.HiddenFood);

        var hiddenId = await FoodIdAsync(TestData.HiddenFood);
        await (await AsStudent.GetAsync($"/api/foods/{hiddenId}")).ShouldHaveStatusAsync(HttpStatusCode.NotFound);
        await (await AsStaff.GetAsync($"/api/foods/{hiddenId}")).ShouldHaveStatusAsync(HttpStatusCode.OK);
    }

    [Theory]
    [InlineData("com ga", TestData.ComGa)]
    [InlineData("TRA SUA", TestData.TraSua)]
    [InlineData("duong den", TestData.TraSua)] // khớp trong mô tả "đường đen"
    public async Task TimKiemKhongDau(string q, string expected)
    {
        var page = await ListAsync(AsStudent, $"q={Uri.EscapeDataString(q)}");
        Assert.Contains(page.Items, f => f.Name == expected);
    }

    [Fact]
    public async Task LocGia_SapXepGiaTang()
    {
        var page = await ListAsync(AsStudent, "minPrice=10000&maxPrice=40000&sort=price_asc");

        Assert.Equal([25000, 35000, 40000], page.Items.Select(f => f.Price));
    }

    [Theory]
    [InlineData("sort=random")]
    [InlineData("minPrice=50000&maxPrice=10000")]
    [InlineData("pageSize=0")]
    public async Task ThamSoSai_400(string query)
    {
        var response = await AsStudent.GetAsync($"/api/foods?{query}");
        await response.ShouldBeProblemAsync(HttpStatusCode.BadRequest, ErrorCodes.ValidationError);
    }

    [Fact]
    public async Task ChiTiet_AnTuyChonTamHetVoiSinhVien_StaffThayDu()
    {
        var id = await FoodIdAsync(TestData.TraSua);

        var forStudent = await (await AsStudent.GetAsync($"/api/foods/{id}")).ReadAsAsync<FoodDetailDto>();
        var forStaff = await (await AsStaff.GetAsync($"/api/foods/{id}")).ReadAsAsync<FoodDetailDto>();

        Assert.Equal(2, forStudent.OptionGroups.Single(g => g.Name == "Topping").Options.Count);
        Assert.Equal(3, forStaff.OptionGroups.Single(g => g.Name == "Topping").Options.Count);
        Assert.False(string.IsNullOrEmpty(forStudent.RowVersion));
    }

    // ------------------------- Suất trong ngày & bán chạy -------------------------

    [Fact]
    public async Task ConLaiHomNay_TinhTheoGioVietNam_BoQuaDonHuy()
    {
        // "Bây giờ" = 10:00 ngày 16/11 giờ VN. Ngày 16/11 VN bắt đầu lúc 17:00 UTC ngày 15/11.
        await AddOrderAsync(TestData.ComGa, 3, new DateTime(2026, 11, 15, 17, 30, 0)); // 00:30 16/11 VN → tính
        await AddOrderAsync(TestData.ComGa, 2, new DateTime(2026, 11, 16, 2, 0, 0));   // 09:00 16/11 VN → tính
        await AddOrderAsync(TestData.ComGa, 4, new DateTime(2026, 11, 15, 16, 30, 0)); // 23:30 15/11 VN → KHÔNG tính
        await AddOrderAsync(TestData.ComGa, 5, new DateTime(2026, 11, 16, 1, 0, 0), OrderStatus.Cancelled); // hủy → KHÔNG tính

        var comGa = await GetSummaryAsync(TestData.ComGa);

        Assert.Equal(60 - 5, comGa.RemainingToday);
        Assert.False(comGa.IsSoldOut);
    }

    [Fact]
    public async Task HetSuat_IsSoldOut_BiLoaiKhiAvailableOnly()
    {
        await Factory.WithDbAsync(db => db.Foods.Where(f => f.Name == TestData.ComGa)
            .ExecuteUpdateAsync(s => s.SetProperty(f => f.DailyLimit, 2)));
        await AddOrderAsync(TestData.ComGa, 2, CanteenApiFactory.Now.UtcDateTime.AddHours(-1));

        var comGa = await GetSummaryAsync(TestData.ComGa);
        Assert.Equal(0, comGa.RemainingToday);
        Assert.True(comGa.IsSoldOut);

        var available = await ListAsync(AsStudent, "availableOnly=true");
        Assert.DoesNotContain(available.Items, f => f.Name == TestData.ComGa);
    }

    [Fact]
    public async Task SangNgayMoi_SuatDuocTinhLai()
    {
        await AddOrderAsync(TestData.ComGa, 10, CanteenApiFactory.Now.UtcDateTime.AddHours(-1));
        Assert.Equal(50, (await GetSummaryAsync(TestData.ComGa)).RemainingToday);

        Factory.Clock.Advance(TimeSpan.FromDays(1)); // sáng hôm sau

        Assert.Equal(60, (await GetSummaryAsync(TestData.ComGa)).RemainingToday);
    }

    [Fact]
    public async Task BanChay_Theo30NgayGanNhat()
    {
        var now = CanteenApiFactory.Now.UtcDateTime;
        await AddOrderAsync(TestData.NuocSuoi, 10, now.AddDays(-2));
        await AddOrderAsync(TestData.ComTam, 4, now.AddDays(-1));
        await AddOrderAsync(TestData.ComGa, 50, now.AddDays(-40)); // ngoài 30 ngày → không tính

        var page = await ListAsync(AsStudent, "sort=popular&pageSize=2");

        Assert.Equal([TestData.NuocSuoi, TestData.ComTam], page.Items.Select(f => f.Name));
    }

    // ------------------------- Ghi (staff) -------------------------

    [Fact]
    public async Task TaoMonKemTuyChon_201()
    {
        var response = await AsStaff.PostJsonAsync("/api/foods", NewFood("Trà đào", await CategoryIdAsync(TestData.Drinks)));

        var created = await response.ReadAsAsync<FoodDetailDto>(HttpStatusCode.Created);
        Assert.Equal("Size", Assert.Single(created.OptionGroups).Name);
        Assert.Equal(20, created.RemainingToday);
    }

    [Fact]
    public async Task TaoMon_TrungTenTrongDanhMuc_409()
    {
        var response = await AsStaff.PostJsonAsync("/api/foods",
            NewFood("COM GA XOI MO", await CategoryIdAsync(TestData.Rice)) with { OptionGroups = null });

        await response.ShouldBeProblemAsync(HttpStatusCode.Conflict, ErrorCodes.FoodNameTaken);
    }

    [Fact]
    public async Task TaoMon_DanhMucKhongTonTai_422()
    {
        var response = await AsStaff.PostJsonAsync("/api/foods", NewFood("Món mới", 99999) with { OptionGroups = null });
        await response.ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.InvalidCategory);
    }

    [Fact]
    public async Task TaoMon_TuyChonSai_422_LietKeDuLoi()
    {
        var badGroup = new SaveOptionGroupRequest("Size", IsRequired: true, MinSelect: 0, MaxSelect: 3, SortOrder: null,
            Options: [new SaveOptionRequest("M", 0, null, null), new SaveOptionRequest("m", 0, null, null)]);

        var response = await AsStaff.PostJsonAsync("/api/foods",
            NewFood("Món mới", await CategoryIdAsync(TestData.Rice)) with { OptionGroups = [badGroup] });

        var problem = await response.ShouldBeProblemAsync(HttpStatusCode.UnprocessableEntity, ErrorCodes.InvalidOptions);
        var detail = problem.GetProperty("detail").GetString()!;
        Assert.Contains("bắt buộc", detail);
        Assert.Contains("lớn hơn số tùy chọn", detail);
        Assert.Contains("trùng tên tùy chọn", detail);
    }

    [Fact]
    public async Task SuaMon_RowVersionCu_409_KhongGhiDe()
    {
        var id = await FoodIdAsync(TestData.ComTam);
        var original = await (await AsStaff.GetAsync($"/api/foods/{id}")).ReadAsAsync<FoodDetailDto>();

        // Nhân viên A lưu trước.
        await (await AsStaff.PutJsonAsync($"/api/foods/{id}", UpdateOf(original, price: 42000)))
            .ShouldHaveStatusAsync(HttpStatusCode.OK);

        // Nhân viên B vẫn giữ form cũ (rowVersion cũ) → bị chặn.
        await (await AsStaff.PutJsonAsync($"/api/foods/{id}", UpdateOf(original, price: 99000)))
            .ShouldBeProblemAsync(HttpStatusCode.Conflict, ErrorCodes.ConcurrencyConflict);

        Assert.Equal(42000, await Factory.WithDbAsync(db => db.Foods.Where(f => f.Id == id).Select(f => f.Price).SingleAsync()));
    }

    [Fact]
    public async Task ThayTuyChon_GiuTenNhomCu_VaLamDoiRowVersion()
    {
        var id = await FoodIdAsync(TestData.TraSua);
        var before = await (await AsStaff.GetAsync($"/api/foods/{id}")).ReadAsAsync<FoodDetailDto>();

        var after = await (await AsStaff.PutJsonAsync($"/api/foods/{id}/option-groups", new ReplaceOptionGroupsRequest(
            [new SaveOptionGroupRequest("Size", true, 1, 1, null,
                [new SaveOptionRequest("M", 0, null, null), new SaveOptionRequest("L", 8000, null, null)])])))
            .ReadAsAsync<FoodDetailDto>();

        Assert.Equal(8000, Assert.Single(after.OptionGroups).Options.Single(o => o.Name == "L").ExtraPrice);
        Assert.NotEqual(before.RowVersion, after.RowVersion);
        await (await AsStaff.PutJsonAsync($"/api/foods/{id}", UpdateOf(before, price: 30000)))
            .ShouldBeProblemAsync(HttpStatusCode.Conflict, ErrorCodes.ConcurrencyConflict);
    }

    [Fact]
    public async Task TatHetMon_IsSoldOut()
    {
        var id = await FoodIdAsync(TestData.ComTam);

        var detail = await (await AsStaff.PatchJsonAsync($"/api/foods/{id}/availability", new UpdateAvailabilityRequest(false)))
            .ReadAsAsync<FoodDetailDto>();

        Assert.True(detail.IsSoldOut);
        Assert.True((await GetSummaryAsync(TestData.ComTam)).IsSoldOut);
    }

    [Fact]
    public async Task UploadAnhMon()
    {
        var id = await FoodIdAsync(TestData.ComTam);

        var detail = await (await AsStaff.UploadAsync($"/api/foods/{id}/image", HttpExtensions.TinyPng(), "x.png"))
            .ReadAsAsync<FoodDetailDto>();

        Assert.StartsWith("http://localhost/uploads/foods/", detail.ImageUrl);
        var image = await AsStudent.GetAsync(new Uri(detail.ImageUrl!).AbsolutePath);
        await image.ShouldHaveStatusAsync(HttpStatusCode.OK);
        Assert.Equal("image/png", image.Content.Headers.ContentType?.MediaType);
    }

    [Fact]
    public async Task XoaMem_AnKhoiMenuVaYeuThich_DonCuGiuNguyen()
    {
        var id = await FoodIdAsync(TestData.NuocSuoi);
        await AddOrderAsync(TestData.NuocSuoi, 1, CanteenApiFactory.Now.UtcDateTime.AddDays(-1));
        await (await AsStudent.PutAsync($"/api/foods/{id}/favorite", null)).ShouldHaveStatusAsync(HttpStatusCode.NoContent);

        await (await AsStaff.DeleteAsync($"/api/foods/{id}")).ShouldHaveStatusAsync(HttpStatusCode.NoContent);

        await (await AsStudent.GetAsync($"/api/foods/{id}")).ShouldHaveStatusAsync(HttpStatusCode.NotFound);
        var favorites = await (await AsStudent.GetAsync("/api/users/me/favorites")).ReadAsAsync<PagedResult<FoodSummaryDto>>();
        Assert.Empty(favorites.Items);
        Assert.Equal(1, await Factory.WithDbAsync(db => db.OrderItems.CountAsync(i => i.FoodId == id))); // lịch sử còn nguyên
    }

    // ------------------------- Yêu thích -------------------------

    [Fact]
    public async Task YeuThich_Idempotent_TheoTungNguoi_MoiNhatTruoc()
    {
        var traSua = await FoodIdAsync(TestData.TraSua);
        var comGa = await FoodIdAsync(TestData.ComGa);
        var student = AsStudent;

        await (await student.PutAsync($"/api/foods/{traSua}/favorite", null)).ShouldHaveStatusAsync(HttpStatusCode.NoContent);
        await (await student.PutAsync($"/api/foods/{traSua}/favorite", null)).ShouldHaveStatusAsync(HttpStatusCode.NoContent);
        Factory.Clock.Advance(TimeSpan.FromMinutes(1));
        await (await student.PutAsync($"/api/foods/{comGa}/favorite", null)).ShouldHaveStatusAsync(HttpStatusCode.NoContent);

        var mine = await (await student.GetAsync("/api/users/me/favorites")).ReadAsAsync<PagedResult<FoodSummaryDto>>();
        Assert.Equal([TestData.ComGa, TestData.TraSua], mine.Items.Select(f => f.Name));
        Assert.All(mine.Items, f => Assert.True(f.IsFavorite));

        Assert.True((await GetSummaryAsync(TestData.TraSua, AsStudent)).IsFavorite);
        Assert.False((await GetSummaryAsync(TestData.TraSua, AsStudent2)).IsFavorite);

        await (await student.DeleteAsync($"/api/foods/{traSua}/favorite")).ShouldHaveStatusAsync(HttpStatusCode.NoContent);
        var after = await (await student.GetAsync("/api/users/me/favorites")).ReadAsAsync<PagedResult<FoodSummaryDto>>();
        Assert.Equal(TestData.ComGa, Assert.Single(after.Items).Name);
    }

    [Fact]
    public async Task YeuThich_MonTrongDanhMucAn_404()
    {
        var response = await AsStudent.PutAsync($"/api/foods/{await FoodIdAsync(TestData.HiddenFood)}/favorite", null);
        await response.ShouldBeProblemAsync(HttpStatusCode.NotFound, ErrorCodes.NotFound);
    }

    // ------------------------- Hỗ trợ -------------------------

    /// <summary>Gọi GET /api/foods; mặc định pageSize=50 nếu test không tự chỉ định.</summary>
    private static async Task<PagedResult<FoodSummaryDto>> ListAsync(HttpClient client, string query)
    {
        var url = query.Contains("pageSize=") ? $"/api/foods?{query}" : $"/api/foods?pageSize=50&{query}";
        return await (await client.GetAsync(url)).ReadAsAsync<PagedResult<FoodSummaryDto>>();
    }

    private async Task<FoodSummaryDto> GetSummaryAsync(string name, HttpClient? client = null) =>
        (await ListAsync(client ?? AsStudent, $"q={Uri.EscapeDataString(name)}")).Items.Single(f => f.Name == name);

    private Task<int> FoodIdAsync(string name) =>
        Factory.WithDbAsync(db => db.Foods.Where(f => f.Name == name).Select(f => f.Id).SingleAsync());

    private Task<int> CategoryIdAsync(string name) =>
        Factory.WithDbAsync(db => db.Categories.Where(c => c.Name == name).Select(c => c.Id).SingleAsync());

    /// <summary>Chèn đơn trực tiếp vào DB với thời điểm tạo cụ thể (UTC).</summary>
    private Task AddOrderAsync(string foodName, int quantity, DateTime createdAtUtc, OrderStatus status = OrderStatus.Received) =>
        Factory.WithDbAsync(async db =>
        {
            var food = await db.Foods.SingleAsync(f => f.Name == foodName);
            var id = Guid.NewGuid().ToString();
            var total = food.Price * quantity;
            db.Orders.Add(new Order
            {
                Id = id, PickupCode = "T01", UserId = TestData.Student1, Status = status,
                Subtotal = total, TotalAmount = total,
                CancelReason = status == OrderStatus.Cancelled ? "Khách hủy" : null,
                Items = { new OrderItem { FoodId = food.Id, FoodName = food.Name, UnitPrice = food.Price, Quantity = quantity, LineTotal = total } },
            });
            await db.SaveChangesAsync();
            // SaveChanges tự gán CreatedAt = giờ thật → ghi đè bằng thời điểm của kịch bản test.
            await db.Orders.Where(o => o.Id == id).ExecuteUpdateAsync(s => s.SetProperty(o => o.CreatedAt, createdAtUtc));
        });

    private static CreateFoodRequest NewFood(string name, int categoryId) => new(
        categoryId, name, "Mô tả món", 20000, 3, 20, null,
        [new SaveOptionGroupRequest("Size", true, 1, 1, null,
            [new SaveOptionRequest("M", 0, null, null), new SaveOptionRequest("L", 5000, null, null)])]);

    private static UpdateFoodRequest UpdateOf(FoodDetailDto f, int price) => new(
        f.CategoryId, f.Name, f.Description, price, f.PrepTimeMinutes, f.DailyLimit, f.IsAvailable, f.RowVersion);
}
