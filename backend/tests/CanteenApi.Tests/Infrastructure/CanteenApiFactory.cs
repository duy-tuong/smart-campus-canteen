using System.Net.Http.Headers;
using CanteenApi.Data;
using CanteenApi.Services.Firebase;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace CanteenApi.Tests.Infrastructure;

/// <summary>
/// Chạy toàn bộ backend THẬT trong bộ nhớ (TestServer) với các thay thế tối thiểu:
///  - SQL Server: database riêng SmartCanteenDb_Test (tạo lại bằng migration mỗi lượt chạy)
///  - Xác thực: TestAuthHandler thay cho Firebase JWT
///  - Firebase Admin: FakeFirebaseAuthService (không gọi mạng)
///  - payOS: FakePaymentGateway (không gọi mạng, dựng được kịch bản đã trả tiền / lỗi)
///  - Tác vụ chạy nền: tắt (test gọi trực tiếp RunOnceAsync)
///  - Đồng hồ: TestClock cố định 10:00 sáng 16/11/2026 giờ Việt Nam
///  - wwwroot: thư mục tạm (ảnh upload khi test không làm bẩn source)
/// Không cần file service account, không cần Internet.
/// </summary>
public sealed class CanteenApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    /// <summary>"Bây giờ" trong test: 2026-11-16 03:00 UTC = 10:00 giờ Việt Nam.</summary>
    public static readonly DateTimeOffset Now = new(2026, 11, 16, 3, 0, 0, TimeSpan.Zero);

    private static readonly string ConnectionString =
        Environment.GetEnvironmentVariable("CANTEEN_TEST_DB")
        ?? "Server=localhost;Database=SmartCanteenDb_Test;Trusted_Connection=True;TrustServerCertificate=True;MultipleActiveResultSets=true";

    private readonly string _webRoot = Path.Combine(Path.GetTempPath(), "canteen-tests-" + Guid.NewGuid().ToString("N"));

    public FakeFirebaseAuthService Firebase { get; } = new();
    public FakePaymentGateway Payments { get; } = new();
    public TestClock Clock { get; } = new(Now);
    public string WebRoot => _webRoot;

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        Directory.CreateDirectory(_webRoot);

        builder.UseEnvironment("Testing");
        builder.UseWebRoot(_webRoot);
        // UseSetting được áp dụng trước khi Program.cs đọc cấu hình.
        builder.UseSetting("ConnectionStrings:CanteenDb", ConnectionString);
        builder.UseSetting("Firebase:ProjectId", "test-project");
        builder.UseSetting("Firebase:DatabaseUrl", "");
        builder.UseSetting("Firebase:CredentialPath", "");
        builder.UseSetting("Workers:Enabled", "false"); // test tự gọi từng lượt worker

        builder.ConfigureTestServices(services =>
        {
            services.AddAuthentication(o =>
                {
                    o.DefaultScheme = TestAuthHandler.SchemeName;
                    o.DefaultAuthenticateScheme = TestAuthHandler.SchemeName;
                    o.DefaultChallengeScheme = TestAuthHandler.SchemeName;
                })
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(TestAuthHandler.SchemeName, _ => { });

            services.RemoveAll<IFirebaseAuthService>();
            services.AddSingleton<IFirebaseAuthService>(Firebase);

            services.RemoveAll<CanteenApi.Services.Payments.IPaymentGateway>();
            services.AddSingleton<CanteenApi.Services.Payments.IPaymentGateway>(Payments);

            services.RemoveAll<TimeProvider>();
            services.AddSingleton<TimeProvider>(Clock);
        });
    }

    /// <summary>Tạo lại database test từ migration (một lần cho cả lượt chạy).</summary>
    public async Task InitializeAsync()
    {
        await using var scope = Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<CanteenDbContext>();
        await db.Database.EnsureDeletedAsync();
        await db.Database.MigrateAsync();
    }

    /// <summary>Xóa sạch dữ liệu và nạp lại TestData — gọi trước MỖI test để các test độc lập nhau.</summary>
    public async Task ResetAsync()
    {
        Clock.Set(Now);
        Firebase.Reset();
        Payments.Reset();
        ((MemoryCache)Services.GetRequiredService<IMemoryCache>()).Compact(1.0); // xóa cache phân quyền

        await using var scope = Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<CanteenDbContext>();

        // Xóa theo thứ tự khóa ngoại (bảng con trước).
        await db.Reviews.ExecuteDeleteAsync();
        await db.Orders.ExecuteDeleteAsync();
        await db.Notifications.ExecuteDeleteAsync();
        await db.Favorites.ExecuteDeleteAsync();
        await db.Foods.ExecuteDeleteAsync();
        await db.Categories.ExecuteDeleteAsync();
        await db.Vouchers.ExecuteDeleteAsync();
        await db.Users.ExecuteDeleteAsync();

        await TestData.SeedAsync(db);
    }

    /// <summary>HttpClient đăng nhập dưới danh nghĩa <paramref name="uid"/> (null = khách chưa đăng nhập).</summary>
    public HttpClient ClientFor(string? uid, string? email = null, string? tokenRole = null)
    {
        var client = CreateClient();
        client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        if (uid is not null) client.DefaultRequestHeaders.Add(TestAuthHandler.UidHeader, uid);
        if (email is not null) client.DefaultRequestHeaders.Add(TestAuthHandler.EmailHeader, email);
        if (tokenRole is not null) client.DefaultRequestHeaders.Add(TestAuthHandler.RoleHeader, tokenRole);
        return client;
    }

    /// <summary>Chạy một thao tác trực tiếp trên database test (chuẩn bị dữ liệu / kiểm tra kết quả).</summary>
    public async Task<T> WithDbAsync<T>(Func<CanteenDbContext, Task<T>> action)
    {
        await using var scope = Services.CreateAsyncScope();
        return await action(scope.ServiceProvider.GetRequiredService<CanteenDbContext>());
    }

    public Task WithDbAsync(Func<CanteenDbContext, Task> action) =>
        WithDbAsync(async db => { await action(db); return true; });

    async Task IAsyncLifetime.DisposeAsync()
    {
        await base.DisposeAsync();
        try { Directory.Delete(_webRoot, recursive: true); } catch (IOException) { }
    }
}

/// <summary>Mọi test class dùng chung một server + database, chạy tuần tự.</summary>
[CollectionDefinition(Name)]
public sealed class ApiCollection : ICollectionFixture<CanteenApiFactory>
{
    public const string Name = "api";
}

/// <summary>Lớp cơ sở: tự reset dữ liệu trước mỗi test.</summary>
[Collection(ApiCollection.Name)]
public abstract class ApiTestBase(CanteenApiFactory factory) : IAsyncLifetime
{
    protected CanteenApiFactory Factory { get; } = factory;

    protected HttpClient Anonymous => Factory.ClientFor(null);
    protected HttpClient AsStudent => Factory.ClientFor(TestData.Student1, "sv01@test.vn");
    protected HttpClient AsStudent2 => Factory.ClientFor(TestData.Student2, "sv02@test.vn");
    protected HttpClient AsStaff => Factory.ClientFor(TestData.Staff, "staff@test.vn");
    protected HttpClient AsAdmin => Factory.ClientFor(TestData.Admin, "admin@test.vn");

    public Task InitializeAsync() => Factory.ResetAsync();
    public Task DisposeAsync() => Task.CompletedTask;
}
