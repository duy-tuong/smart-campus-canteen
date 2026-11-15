using System.Globalization;

namespace CanteenApi.Common;

/// <summary>Định dạng tiền Việt Nam cố định ("8.000đ"), không phụ thuộc ngôn ngữ của máy chủ.</summary>
public static class Money
{
    private static readonly CultureInfo Vietnamese = CultureInfo.GetCultureInfo("vi-VN");

    public static string Format(long amount) => amount.ToString("N0", Vietnamese) + "đ";
}
