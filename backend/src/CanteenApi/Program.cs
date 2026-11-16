using System.Text.Json;
using System.Text.Json.Serialization;
using CanteenApi.Auth;
using CanteenApi.Common;
using CanteenApi.Data;
using CanteenApi.Middleware;
using CanteenApi.OpenApi;
using CanteenApi.Options;
using CanteenApi.Services;
using CanteenApi.Services.Ordering;
using CanteenApi.Services.Notifications;
using CanteenApi.Services.Payments;
using CanteenApi.Services.Realtime;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Scalar.AspNetCore;

var builder = WebApplication.CreateBuilder(args);

// ---------- Cấu hình ----------
builder.Services.Configure<FirebaseOptions>(
    builder.Configuration.GetSection(FirebaseOptions.SectionName));
builder.Services.AddOptions<CanteenOptions>()
    .Bind(builder.Configuration.GetSection(CanteenOptions.SectionName))
    .ValidateDataAnnotations()
    .Validate(o => o.CloseTime > o.OpenTime, "Canteen:CloseTime phải sau Canteen:OpenTime.")
    .ValidateOnStart();
builder.Services.Configure<PayOsOptions>(builder.Configuration.GetSection(PayOsOptions.SectionName));
builder.Services.AddOptions<ReviewOptions>()
    .Bind(builder.Configuration.GetSection(ReviewOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();
builder.Services.AddOptions<WorkerOptions>()
    .Bind(builder.Configuration.GetSection(WorkerOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();

// ---------- MVC + JSON + lỗi chuẩn ----------
builder.Services
    .AddControllers()
    .AddJsonOptions(o =>
        // Enum trả về dạng chuỗi camelCase: "received", "cooking", "ready"...
        o.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase)))
    .ConfigureApiBehaviorOptions(o =>
    {
        // Lỗi validate DTO → ValidationProblemDetails có mã VALIDATION_ERROR và lỗi theo từng field.
        o.InvalidModelStateResponseFactory = context =>
        {
            var problem = new ValidationProblemDetails(context.ModelState)
            {
                Status = StatusCodes.Status400BadRequest,
                Title = "Dữ liệu không hợp lệ",
                Detail = "Vui lòng kiểm tra lại các trường được đánh dấu.",
                Type = "https://httpstatuses.io/400",
                Instance = context.HttpContext.Request.Path,
            };
            problem.Extensions["code"] = ErrorCodes.ValidationError;
            Problems.AddTraceId(context.HttpContext, problem);
            return new BadRequestObjectResult(problem) { ContentTypes = { "application/problem+json" } };
        };
    });

builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();

builder.Services.AddOpenApi(o => o.AddDocumentTransformer<BearerSecuritySchemeTransformer>());

// ---------- Dữ liệu ----------
// SQL Server (EF Core) — nguồn dữ liệu chính: menu, người dùng, đơn hàng.
builder.Services.AddDbContext<CanteenDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("CanteenDb")
        ?? throw new InvalidOperationException("Thiếu ConnectionStrings:CanteenDb.")));

// ---------- Firebase + xác thực/phân quyền ----------
builder.Services.AddFirebase(builder.Configuration);

// ---------- Dịch vụ dùng chung ----------
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<IFileStorage, FileStorageService>();
builder.Services.AddScoped<IPublicUrlBuilder, PublicUrlBuilder>();
builder.Services.AddHttpClient();

// ---------- Nghiệp vụ ----------
builder.Services.AddScoped<UserService>();
builder.Services.AddScoped<CategoryService>();
builder.Services.AddScoped<FoodService>();
builder.Services.AddScoped<VoucherService>();
builder.Services.AddScoped<OrderPricingService>();
builder.Services.AddScoped<OrderService>();
builder.Services.AddScoped<OrderLifecycleService>();
builder.Services.AddScoped<PaymentService>();
builder.Services.AddScoped<NotificationService>();
builder.Services.AddScoped<CanteenApi.Services.Reviews.ReviewService>();
builder.Services.AddScoped<CanteenApi.Services.Statistics.StatisticsService>();

// ---------- Đồng bộ realtime lên Firebase (hàng đợi trong bộ nhớ + worker ghi nền) ----------
builder.Services.AddSingleton<RealtimeQueue>();
builder.Services.AddSingleton<IRealtimePublisher>(sp => sp.GetRequiredService<RealtimeQueue>());
builder.Services.AddScoped<RealtimeSyncService>();

// ---------- Thanh toán payOS ----------
builder.Services.AddSingleton<IPaymentGateway, PayOsGateway>();

// ---------- Tác vụ chạy nền (tắt trong môi trường test bằng Workers:Enabled=false) ----------
builder.Services.AddSingleton<PaymentStatusPoller>();
builder.Services.AddSingleton<UnpaidOrderCanceller>();
if (builder.Configuration.GetValue("Workers:Enabled", true))
{
    builder.Services.AddHostedService(sp => sp.GetRequiredService<PaymentStatusPoller>());
    builder.Services.AddHostedService(sp => sp.GetRequiredService<UnpaidOrderCanceller>());
    builder.Services.AddHostedService<RealtimeSyncWorker>();
}

var app = builder.Build();

// ---------- Pipeline ----------
app.UseExceptionHandler();
app.UseStatusCodePages(); // 404/405... không có body → trả ProblemDetails

if (app.Environment.IsDevelopment())
{
    // Tự áp dụng migration khi chạy local: clone repo về, chạy là có database.
    using (var scope = app.Services.CreateScope())
    {
        scope.ServiceProvider.GetRequiredService<CanteenDbContext>().Database.Migrate();
    }

    app.MapOpenApi().AllowAnonymous();          // /openapi/v1.json
    app.MapScalarApiReference().AllowAnonymous(); // /scalar - giao diện tài liệu API
}

// Không dùng UseHttpsRedirection: emulator gọi http://10.0.2.2.
app.UseStaticFiles(); // ảnh món ăn (wwwroot/images) và ảnh upload (wwwroot/uploads)

// Ảnh không tồn tại → 404 rõ ràng (thay vì rơi xuống phân quyền mặc định và nhận 401).
app.Use(async (context, next) =>
{
    if (context.Request.Path.StartsWithSegments("/uploads") || context.Request.Path.StartsWithSegments("/images"))
    {
        await Problems.WriteAsync(context, StatusCodes.Status404NotFound, ErrorCodes.NotFound, "Không tìm thấy file.");
        return;
    }
    await next();
});

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();

/// <summary>Khai báo public để project test (WebApplicationFactory) tham chiếu được.</summary>
public partial class Program;
