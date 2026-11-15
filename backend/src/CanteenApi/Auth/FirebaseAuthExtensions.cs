using CanteenApi.Common;
using CanteenApi.Options;
using CanteenApi.Services;
using CanteenApi.Services.Firebase;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.IdentityModel.Tokens;

namespace CanteenApi.Auth;

public static class FirebaseAuthExtensions
{
    /// <summary>
    /// Đăng ký phần Firebase và xác thực/phân quyền cho backend:
    ///  - FirebaseCredentialProvider: nạp service account LAZY (chỉ khi thực sự cần quyền admin)
    ///  - IFirebaseAuthService: tạo tài khoản, gán claim role, khóa/mở tài khoản
    ///  - FirebaseDbService: truy cập Realtime Database qua REST
    ///  - Xác thực JWT: Flutter gửi Firebase ID token trong header "Authorization: Bearer ..."
    ///  - Đối chiếu bảng Users (vai trò, khóa tài khoản) + các policy phân quyền
    /// </summary>
    public static IServiceCollection AddFirebase(this IServiceCollection services, IConfiguration configuration)
    {
        var options = configuration.GetSection(FirebaseOptions.SectionName).Get<FirebaseOptions>() ?? new();
        if (string.IsNullOrWhiteSpace(options.ProjectId))
        {
            throw new InvalidOperationException(
                "Thiếu cấu hình Firebase:ProjectId (xem README: dotnet user-secrets).");
        }

        // 1. Firebase Admin (lazy) + Realtime Database qua REST.
        services.AddSingleton<FirebaseCredentialProvider>();
        services.AddSingleton<IFirebaseAuthService, FirebaseAuthService>();
        services.AddHttpClient<FirebaseDbService>(client => client.Timeout = TimeSpan.FromSeconds(15));

        // 2. Xác minh Firebase ID token (JWT do securetoken.google.com phát hành).
        var issuer = $"https://securetoken.google.com/{options.ProjectId}";
        services
            .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(jwt =>
            {
                jwt.Authority = issuer;
                jwt.MapInboundClaims = false; // giữ nguyên tên claim: "user_id", "email", "role"
                jwt.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidIssuer = issuer,
                    ValidateAudience = true,
                    ValidAudience = options.ProjectId,
                    ValidateLifetime = true,
                    NameClaimType = AppClaims.UserId,
                    RoleClaimType = AppClaims.Role,
                };
                jwt.Events = new JwtBearerEvents
                {
                    // Trả 401 dạng ProblemDetails thay vì response rỗng.
                    OnChallenge = async context =>
                    {
                        context.HandleResponse();
                        var expired = context.AuthenticateFailure is SecurityTokenExpiredException;
                        await Problems.WriteAsync(context.HttpContext, StatusCodes.Status401Unauthorized,
                            ErrorCodes.Unauthorized,
                            expired ? "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại."
                                    : "Bạn chưa đăng nhập hoặc token không hợp lệ.");
                    },
                };
            });

        // 3. Đối chiếu bảng Users + phân quyền.
        services.AddMemoryCache();
        services.AddHttpContextAccessor();
        services.AddSingleton<UserAccessCache>();
        services.AddScoped<IClaimsTransformation, UserClaimsTransformation>();
        services.AddScoped<ICurrentUser, CurrentUser>();
        services.AddSingleton<IAuthorizationMiddlewareResultHandler, ProblemAuthorizationResultHandler>();
        services.AddAppAuthorization();

        return services;
    }
}
