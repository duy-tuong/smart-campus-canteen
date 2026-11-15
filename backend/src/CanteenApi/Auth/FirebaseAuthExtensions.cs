using CanteenApi.Models;
using CanteenApi.Options;
using CanteenApi.Services;
using FirebaseAdmin;
using Google.Apis.Auth.OAuth2;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;

namespace CanteenApi.Auth;

/// <summary>
/// Giá trị custom claim "role" trong Firebase ID token, dùng trong [Authorize(Roles = ...)].
/// </summary>
public static class Roles
{
    public const string Student = "student";
    public const string Staff = "staff";
    public const string Admin = "admin";

    /// <summary>Staff hoặc Admin (dùng cho API quản lý căn-tin).</summary>
    public const string StaffOrAdmin = Staff + "," + Admin;

    public static string ToClaim(UserRole role) => role switch
    {
        UserRole.Staff => Staff,
        UserRole.Admin => Admin,
        _ => Student,
    };
}

public static class FirebaseAuthExtensions
{
    /// <summary>
    /// Đăng ký toàn bộ phần Firebase cho backend:
    ///  - Service account credential + FirebaseApp (Admin SDK: gán custom claim role)
    ///  - FirebaseDbService (truy cập Realtime Database qua REST)
    ///  - Xác thực JWT: Flutter gửi Firebase ID token trong header "Authorization: Bearer ..."
    /// </summary>
    public static IServiceCollection AddFirebase(this IServiceCollection services, IConfiguration configuration)
    {
        var options = configuration.GetSection(FirebaseOptions.SectionName).Get<FirebaseOptions>()
            ?? throw new InvalidOperationException("Thiếu cấu hình 'Firebase' (xem README: dotnet user-secrets).");

        if (string.IsNullOrWhiteSpace(options.ProjectId) ||
            string.IsNullOrWhiteSpace(options.DatabaseUrl) ||
            string.IsNullOrWhiteSpace(options.CredentialPath))
        {
            throw new InvalidOperationException(
                "Cấu hình Firebase chưa đủ: cần ProjectId, DatabaseUrl, CredentialPath (xem README).");
        }

        // 1. Credential từ file service account (nằm NGOÀI repo).
        var credential = CredentialFactory
            .FromFile<ServiceAccountCredential>(options.CredentialPath)
            .ToGoogleCredential();
        services.AddSingleton(credential);
        services.AddSingleton(new RtdbCredential(credential.CreateScoped(FirebaseDbService.Scopes)));

        // 2. Firebase Admin SDK (dùng FirebaseAuth.DefaultInstance cho custom claims).
        if (FirebaseApp.DefaultInstance is null)
        {
            FirebaseApp.Create(new AppOptions { Credential = credential, ProjectId = options.ProjectId });
        }

        // 3. Realtime Database qua REST.
        services.AddHttpClient<FirebaseDbService>(client => client.Timeout = TimeSpan.FromSeconds(15));

        // 4. Xác minh Firebase ID token (JWT do securetoken.google.com phát hành).
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
                    NameClaimType = "user_id",
                    RoleClaimType = "role", // custom claim do backend gán cho nhân viên căn-tin
                };
            });

        services.AddAuthorization();
        return services;
    }
}
