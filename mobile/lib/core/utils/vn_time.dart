import 'package:intl/intl.dart';

/// Thời gian theo giờ Việt Nam (UTC+7, không có giờ mùa hè).
///
/// Backend luôn trả thời gian UTC dạng ISO có hậu tố "Z"; Firebase trả epoch mili-giây.
/// App hiển thị theo giờ Việt Nam CỐ ĐỊNH (không theo múi giờ của điện thoại) để thống nhất
/// với căn-tin — sinh viên đổi múi giờ máy cũng không thấy sai giờ lấy món.
abstract final class VnTime {
  static const Duration offset = Duration(hours: 7);

  /// Đổi một thời điểm (bất kỳ múi giờ) sang "đồng hồ treo tường" Việt Nam.
  static DateTime toVietnam(DateTime instant) => instant.toUtc().add(offset);

  /// Đọc chuỗi ISO từ API ("2026-11-16T03:00:00Z").
  static DateTime parse(String iso) => DateTime.parse(iso).toUtc();

  static DateTime? tryParse(String? iso) => iso == null ? null : DateTime.tryParse(iso)?.toUtc();

  /// Đọc epoch mili-giây từ Firebase.
  static DateTime? fromEpochMs(Object? value) =>
      value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true) : null;

  /// "10:05"
  static String time(DateTime instant) => DateFormat('HH:mm').format(toVietnam(instant));

  /// "16/11/2026"
  static String date(DateTime instant) => DateFormat('dd/MM/yyyy').format(toVietnam(instant));

  /// "10:05 · 16/11/2026"
  static String dateTime(DateTime instant) => '${time(instant)} · ${date(instant)}';

  /// "Vừa xong", "5 phút trước", "2 giờ trước", "Hôm qua 10:05", rồi tới ngày đầy đủ.
  static String relative(DateTime instant, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    final diff = current.difference(instant.toUtc());
    if (diff.inSeconds < 60) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';

    final today = DateTime.utc(toVietnam(current).year, toVietnam(current).month, toVietnam(current).day);
    final local = toVietnam(instant);
    final day = DateTime.utc(local.year, local.month, local.day);
    final days = today.difference(day).inDays;
    if (days == 0) return '${diff.inHours} giờ trước';
    if (days == 1) return 'Hôm qua ${time(instant)}';
    return dateTime(instant);
  }

  /// Ngày hôm nay theo giờ Việt Nam (dùng cho tham số ?from=&to= của thống kê).
  static DateTime today({DateTime? now}) {
    final local = toVietnam(now ?? DateTime.now());
    return DateTime.utc(local.year, local.month, local.day);
  }

  /// "2026-11-16" — định dạng ngày cho query string.
  static String isoDate(DateTime day) => DateFormat('yyyy-MM-dd').format(day);
}
