using System.Text;
using CanteenApi.Services;

namespace CanteenApi.Tests.Unit;

/// <summary>Nhận diện định dạng ảnh bằng magic bytes, không tin đuôi file.</summary>
public class ImageSignatureTests
{
    [Fact]
    public void Jpeg() =>
        Assert.Equal(".jpg", FileStorageService.DetectImageExtension([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0]));

    [Fact]
    public void Png() =>
        Assert.Equal(".png", FileStorageService.DetectImageExtension([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]));

    [Fact]
    public void WebP() =>
        Assert.Equal(".webp", FileStorageService.DetectImageExtension(Encoding.ASCII.GetBytes("RIFF\0\0\0\0WEBP")));

    [Theory]
    [InlineData("day khong phai anh")]  // file text đổi đuôi thành .jpg
    [InlineData("GIF89a......")]        // GIF không được hỗ trợ
    [InlineData("<svg></svg>")]          // SVG có thể chứa script
    [InlineData("")]
    public void DinhDangKhongHopLe_TraVeNull(string content) =>
        Assert.Null(FileStorageService.DetectImageExtension(Encoding.ASCII.GetBytes(content)));
}
