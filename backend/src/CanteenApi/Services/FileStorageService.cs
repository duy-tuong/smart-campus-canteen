using CanteenApi.Common;

namespace CanteenApi.Services;

/// <summary>Thư mục con trong wwwroot/uploads.</summary>
public enum UploadFolder
{
    Avatars,
    Foods,
}

/// <summary>Lưu/xóa ảnh người dùng tải lên.</summary>
public interface IFileStorage
{
    /// <summary>
    /// Kiểm tra và lưu ảnh. Trả về đường dẫn tương đối dạng "/uploads/foods/{guid}.jpg" để lưu vào database.
    /// </summary>
    Task<string> SaveImageAsync(IFormFile file, UploadFolder folder, long maxBytes, CancellationToken ct = default);

    /// <summary>Xóa file đã upload trước đó (bỏ qua đường dẫn không thuộc /uploads, ví dụ ảnh seed).</summary>
    void Delete(string? relativePath);
}

/// <summary>
/// Lưu ảnh vào wwwroot/uploads (được phục vụ tĩnh qua UseStaticFiles).
///
/// Bảo mật:
///  - Chỉ nhận JPEG / PNG / WebP, xác định bằng MAGIC BYTES (chữ ký nhị phân đầu file),
///    không tin vào đuôi file hay Content-Type do client gửi.
///  - Tên file do server sinh (GUID) → không ghi đè file khác, không bị path traversal.
/// </summary>
public sealed class FileStorageService(IWebHostEnvironment env, ILogger<FileStorageService> logger) : IFileStorage
{
    public const long MaxAvatarBytes = 2 * 1024 * 1024;
    public const long MaxFoodImageBytes = 5 * 1024 * 1024;

    private const string UploadsRoot = "uploads";

    public async Task<string> SaveImageAsync(IFormFile file, UploadFolder folder, long maxBytes, CancellationToken ct = default)
    {
        if (file.Length == 0)
            throw new BadRequestException(ErrorCodes.InvalidFile, "File ảnh rỗng.");

        if (file.Length > maxBytes)
            throw new BadRequestException(ErrorCodes.InvalidFile,
                $"Ảnh vượt quá dung lượng cho phép ({maxBytes / 1024 / 1024} MB).");

        var header = new byte[12];
        await using (var peek = file.OpenReadStream())
        {
            var read = await peek.ReadAtLeastAsync(header, header.Length, throwOnEndOfStream: false, ct);
            Array.Resize(ref header, read);
        }

        var extension = DetectImageExtension(header)
            ?? throw new BadRequestException(ErrorCodes.InvalidFile, "Chỉ chấp nhận ảnh JPEG, PNG hoặc WebP.");

        var folderName = folder.ToString().ToLowerInvariant();
        var directory = Path.Combine(WebRoot, UploadsRoot, folderName);
        Directory.CreateDirectory(directory);

        var fileName = $"{Guid.NewGuid():N}{extension}";
        var fullPath = Path.Combine(directory, fileName);

        await using (var target = File.Create(fullPath))
        await using (var source = file.OpenReadStream())
        {
            await source.CopyToAsync(target, ct);
        }

        return $"/{UploadsRoot}/{folderName}/{fileName}";
    }

    public void Delete(string? relativePath)
    {
        if (string.IsNullOrEmpty(relativePath) || !relativePath.StartsWith($"/{UploadsRoot}/", StringComparison.Ordinal))
            return;

        var root = Path.GetFullPath(Path.Combine(WebRoot, UploadsRoot));
        var fullPath = Path.GetFullPath(Path.Combine(WebRoot, relativePath.TrimStart('/')));

        // Chặn path traversal: chỉ xóa file nằm trong wwwroot/uploads.
        if (!fullPath.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) return;

        try
        {
            if (File.Exists(fullPath)) File.Delete(fullPath);
        }
        catch (IOException ex)
        {
            logger.LogWarning(ex, "Không xóa được file cũ {Path}", fullPath);
        }
    }

    private string WebRoot => env.WebRootPath
        ?? Path.Combine(env.ContentRootPath, "wwwroot");

    /// <summary>Nhận diện định dạng ảnh qua chữ ký nhị phân.</summary>
    internal static string? DetectImageExtension(ReadOnlySpan<byte> h)
    {
        // JPEG: FF D8 FF
        if (h.Length >= 3 && h[0] == 0xFF && h[1] == 0xD8 && h[2] == 0xFF) return ".jpg";

        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if (h.Length >= 8 && h[..8].SequenceEqual(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }))
            return ".png";

        // WebP: "RIFF" ???? "WEBP"
        if (h.Length >= 12 && h[..4].SequenceEqual("RIFF"u8) && h[8..12].SequenceEqual("WEBP"u8))
            return ".webp";

        return null;
    }
}
