using Microsoft.AspNetCore.OpenApi;
using Microsoft.OpenApi;

namespace CanteenApi.OpenApi;

/// <summary>
/// Khai báo cơ chế xác thực Bearer (Firebase ID token) trong tài liệu OpenAPI,
/// để giao diện Scalar có ô nhập token và gửi kèm header Authorization khi thử API.
/// </summary>
internal sealed class BearerSecuritySchemeTransformer : IOpenApiDocumentTransformer
{
    private const string SchemeName = "Bearer";

    public Task TransformAsync(OpenApiDocument document, OpenApiDocumentTransformerContext context, CancellationToken ct)
    {
        document.Info.Title = "Smart Campus Canteen API";
        document.Info.Description =
            "REST API cho ứng dụng đặt món căn-tin. Xác thực bằng Firebase ID token: " +
            "header `Authorization: Bearer <idToken>`. Môi trường Development có `POST /api/dev/token` để lấy token từ tài khoản demo.";

        document.Components ??= new OpenApiComponents();
        document.Components.SecuritySchemes ??= new Dictionary<string, IOpenApiSecurityScheme>();
        document.Components.SecuritySchemes[SchemeName] = new OpenApiSecurityScheme
        {
            Type = SecuritySchemeType.Http,
            Scheme = "bearer",
            BearerFormat = "JWT",
            Description = "Firebase ID token",
        };

        document.Security ??= [];
        document.Security.Add(new OpenApiSecurityRequirement
        {
            [new OpenApiSecuritySchemeReference(SchemeName, document)] = [],
        });

        return Task.CompletedTask;
    }
}
