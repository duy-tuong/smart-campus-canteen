using System.Net;
using CanteenApi.Services.Dev;
using CanteenApi.Tests.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace CanteenApi.Tests.Api;

/// <summary>Gắn ảnh mẫu (wwwroot/images) cho món theo tên — không ghi đè ảnh đã upload trừ khi yêu cầu.</summary>
public class FoodImageSeederTests(CanteenApiFactory factory) : ApiTestBase(factory)
{
    private const string ComGaImage = "/images/com-ga-test.jpg";
    private const string ComTamImage = "/images/com-tam-test.jpg";

    private Task<FoodImageSeedResult> ApplyAsync(Dictionary<string, string> images, bool overwrite = false) =>
        WithSeederAsync(s => s.ApplyAsync(images, overwrite, default));

    private async Task<T> WithSeederAsync<T>(Func<FoodImageSeeder, Task<T>> action)
    {
        await using var scope = Factory.Services.CreateAsyncScope();
        return await action(scope.ServiceProvider.GetRequiredService<FoodImageSeeder>());
    }

    /// <summary>Tạo file ảnh mẫu trong wwwroot tạm của test.</summary>
    private string CreateImage(string url)
    {
        var path = Path.Combine(Factory.WebRoot, url.TrimStart('/').Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, [0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, (byte)'J', (byte)'F', (byte)'I', (byte)'F', 0, 0xFF, 0xD9]);
        return path;
    }

    private Task<string?> ImageOfAsync(string foodName) =>
        Factory.WithDbAsync(db => db.Foods.Where(f => f.Name == foodName).Select(f => f.ImageUrl).SingleAsync());

    [Fact]
    public async Task GanAnhTheoTen_AnhPhucVuDuoc_BaoFileThieuVaTenLa()
    {
        CreateImage(ComGaImage);

        var r = await ApplyAsync(new()
        {
            [TestData.ComGa] = ComGaImage,
            [TestData.ComTam] = ComTamImage,       // chưa có file
            ["Món không tồn tại"] = ComGaImage,
        });

        Assert.Equal(1, r.Updated);
        Assert.Equal([ComTamImage], r.MissingFiles);
        Assert.Equal(["Món không tồn tại"], r.UnknownFoods);
        Assert.Equal(ComGaImage, await ImageOfAsync(TestData.ComGa));
        Assert.Null(await ImageOfAsync(TestData.ComTam));

        // API trả URL tuyệt đối và file được phục vụ tĩnh.
        var foodId = await Factory.WithDbAsync(db => db.Foods.Where(f => f.Name == TestData.ComGa).Select(f => f.Id).SingleAsync());
        var detail = await (await AsStudent.GetAsync($"/api/foods/{foodId}")).ReadAsAsync<FoodImageView>();
        Assert.Equal("http://localhost" + ComGaImage, detail.ImageUrl);
        await (await AsStudent.GetAsync(ComGaImage)).ShouldHaveStatusAsync(HttpStatusCode.OK);

        // Chạy lại: không đổi gì.
        var again = await ApplyAsync(new() { [TestData.ComGa] = ComGaImage });
        Assert.Equal((0, 1), (again.Updated, again.Skipped));
    }

    [Fact]
    public async Task AnhDaUpload_KhongBiGhiDe_TruKhiOverwrite_VaFileCuBiXoa()
    {
        CreateImage(ComGaImage);
        var uploaded = "/uploads/foods/old-test.jpg";
        var uploadedPath = CreateImage(uploaded);
        await Factory.WithDbAsync(db =>
            db.Foods.Where(f => f.Name == TestData.ComGa).ExecuteUpdateAsync(s => s.SetProperty(f => f.ImageUrl, uploaded)));

        var r = await ApplyAsync(new() { [TestData.ComGa] = ComGaImage });
        Assert.Equal((0, 1), (r.Updated, r.Skipped));
        Assert.Equal(uploaded, await ImageOfAsync(TestData.ComGa));

        r = await ApplyAsync(new() { [TestData.ComGa] = ComGaImage }, overwrite: true);
        Assert.Equal(1, r.Updated);
        Assert.Equal(ComGaImage, await ImageOfAsync(TestData.ComGa));
        Assert.False(File.Exists(uploadedPath), "ảnh upload cũ phải được dọn");
    }

    [Theory]
    [InlineData("/uploads/foods/x.jpg")]
    [InlineData("/images/../appsettings.json")]
    public async Task DuongDanNgoaiImages_BiTuChoi(string url)
    {
        await Assert.ThrowsAsync<ArgumentException>(() => ApplyAsync(new() { [TestData.ComGa] = url }));
    }

    private sealed record FoodImageView(int Id, string? ImageUrl);
}
