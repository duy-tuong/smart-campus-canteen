using CanteenApi.Options;
using FirebaseAdmin;
using Google.Apis.Auth.OAuth2;
using Microsoft.Extensions.Options;

namespace CanteenApi.Services.Firebase;

/// <summary>
/// Nạp service account và khởi tạo Firebase Admin SDK theo kiểu LAZY:
/// chỉ đọc file khóa ở lần đầu thực sự cần (gọi Admin SDK hoặc Realtime Database).
///
/// Nhờ vậy backend vẫn khởi động được (ví dụ trong môi trường test) khi không có file khóa,
/// miễn là không gọi tới các chức năng cần quyền admin.
/// </summary>
public sealed class FirebaseCredentialProvider
{
    /// <summary>OAuth2 scopes cần cho Realtime Database REST API.</summary>
    private static readonly string[] RtdbScopes =
    [
        "https://www.googleapis.com/auth/firebase.database",
        "https://www.googleapis.com/auth/userinfo.email",
    ];

    private static readonly Lock AppLock = new();

    private readonly FirebaseOptions _options;
    private readonly Lazy<GoogleCredential> _credential;

    // Credential đã gắn scope được giữ singleton để access token được cache và tự làm mới.
    private readonly Lazy<ITokenAccess> _rtdbToken;

    public FirebaseCredentialProvider(IOptions<FirebaseOptions> options)
    {
        _options = options.Value;
        _credential = new Lazy<GoogleCredential>(() => LoadCredential(_options));
        _rtdbToken = new Lazy<ITokenAccess>(() => _credential.Value.CreateScoped(RtdbScopes));
    }

    /// <summary>Credential đã gắn scope Realtime Database.</summary>
    public ITokenAccess RtdbToken => _rtdbToken.Value;

    /// <summary>Bảo đảm FirebaseApp mặc định đã được tạo (dùng cho FirebaseAuth.DefaultInstance).</summary>
    public FirebaseApp EnsureApp()
    {
        if (FirebaseApp.DefaultInstance is { } existing) return existing;

        lock (AppLock)
        {
            return FirebaseApp.DefaultInstance ?? FirebaseApp.Create(new AppOptions
            {
                Credential = _credential.Value,
                ProjectId = _options.ProjectId,
            });
        }
    }

    private static GoogleCredential LoadCredential(FirebaseOptions o)
    {
        if (string.IsNullOrWhiteSpace(o.CredentialPath) || !File.Exists(o.CredentialPath))
        {
            throw new InvalidOperationException(
                "Chưa cấu hình Firebase:CredentialPath hoặc không tìm thấy file service account (xem README).");
        }

        return CredentialFactory
            .FromFile<ServiceAccountCredential>(o.CredentialPath)
            .ToGoogleCredential();
    }
}
