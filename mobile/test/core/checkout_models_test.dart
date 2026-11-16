import 'package:campus_canteen/core/utils/vn_time.dart';
import 'package:campus_canteen/models/cart_item.dart';
import 'package:campus_canteen/models/checkout.dart';
import 'package:campus_canteen/screens/checkout/idempotency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> infoJson({String close = '19:00', String serverTime = '2026-11-16T03:00:00Z'}) => {
    'openTime': '06:30',
    'closeTime': close,
    'isOpen': true,
    'serverTime': serverTime,
    'minPickupLeadMinutes': 10,
    'unpaidTransferTimeoutMinutes': 15,
    'maxActiveOrdersPerUser': 3,
    'maxLinesPerOrder': 20,
    'bankTransferEnabled': true,
  };

  group('CanteenInfo', () {
    test('đọc giờ mở cửa; khung giờ hẹn làm tròn mốc 15 phút từ "bây giờ + 10 + 10 dự phòng"', () {
      final received = DateTime.utc(2026, 11, 16, 3, 7); // 10:07 giờ VN
      final info = CanteenInfo.fromJson(infoJson(serverTime: '2026-11-16T03:07:00Z'), receivedAt: received);
      expect(info.hoursLabel, '06:30–19:00');

      final slots = info.pickupSlots(deviceNow: received);
      expect(VnTime.time(slots.first), '10:30', reason: '10:07 + 20 = 10:27 → làm tròn lên 10:30');
      expect(VnTime.time(slots[1]), '10:45');
      expect(slots.first.isUtc, isTrue);
      expect(slots.first, DateTime.utc(2026, 11, 16, 3, 30));
      expect(slots, hasLength(16), reason: 'giới hạn số mốc hiển thị');
    });

    test('khung giờ không vượt quá giờ đóng cửa', () {
      final received = DateTime.utc(2026, 11, 16, 11, 20); // 18:20 VN
      final info = CanteenInfo.fromJson(infoJson(serverTime: '2026-11-16T11:20:00Z'), receivedAt: received);
      expect(info.pickupSlots(deviceNow: received).map(VnTime.time), ['18:45', '19:00']);
    });

    test('dùng giờ MÁY CHỦ: điện thoại chạy nhanh 30 phút vẫn ra đúng khung giờ', () {
      final received = DateTime.utc(2026, 11, 16, 3, 37); // đồng hồ điện thoại sai: 10:37
      final info = CanteenInfo.fromJson(infoJson(serverTime: '2026-11-16T03:07:00Z'), receivedAt: received);
      expect(info.clockSkew, const Duration(minutes: -30));
      expect(VnTime.time(info.pickupSlots(deviceNow: received).first), '10:30');
    });
  });

  group('Quote', () {
    test('đọc dòng, lỗi theo dòng, voucher', () {
      final quote = Quote.fromJson({
        'lines': [
          {
            'index': 0,
            'foodId': 2,
            'foodName': 'Trà sữa',
            'unitPrice': 25000,
            'optionsPrice': 6000,
            'quantity': 2,
            'lineTotal': 62000,
            'options': [
              {'optionId': 21, 'groupName': 'Size', 'optionName': 'L', 'extraPrice': 6000},
            ],
          },
        ],
        'errors': [
          {'index': 0, 'foodId': 2, 'code': 'ITEM_SOLD_OUT', 'message': 'Chỉ còn 1 suất.', 'remaining': 1},
        ],
        'totalItems': 2,
        'subtotal': 62000,
        'voucher': {'code': 'GIAM10', 'isValid': true, 'discount': 6200, 'message': 'OK'},
        'discountAmount': 6200,
        'totalAmount': 55800,
        'canOrder': false,
      });
      expect(quote.lines.single.optionsText, 'L');
      expect(quote.errorAt(0)!.remaining, 1);
      expect(quote.errorAt(1), isNull);
      expect(quote.voucher!.isValid, isTrue);
      expect(quote.canOrder, isFalse);
    });
  });

  group('AvailableVoucher', () {
    AvailableVoucher voucher(String type, int value, {int? max, int min = 0}) => AvailableVoucher.fromJson({
      'code': 'X',
      'description': '',
      'discountType': type,
      'discountValue': value,
      'maxDiscount': max,
      'minOrderAmount': min,
      'endAt': '2026-12-31T16:59:59Z',
    });

    test('mô tả và ước tính tiền giảm (giới hạn, đơn tối thiểu)', () {
      final percent = voucher('percent', 10, max: 15000, min: 30000);
      expect(percent.title, 'Giảm 10% (tối đa 15.000đ)');
      expect(percent.estimateFor(20000), 0, reason: 'chưa đủ đơn tối thiểu');
      expect(percent.estimateFor(100000), 10000);
      expect(percent.estimateFor(500000), 15000, reason: 'không vượt mức tối đa');

      final fixed = voucher('fixed', 20000);
      expect(fixed.title, 'Giảm 20.000đ');
      expect(fixed.estimateFor(8000), 8000, reason: 'không giảm quá giá trị đơn');
    });
  });

  test('dòng giỏ gửi lên máy chủ KHÔNG kèm giá', () {
    final json = cartLineJson(
      CartItem(
        userId: 'u',
        foodId: 2,
        foodName: 'Trà sữa',
        unitPrice: 25000,
        quantity: 2,
        createdAt: DateTime.utc(2026),
        note: 'Ít đá',
        options: const [CartItemOption(optionId: 21, groupName: 'Size', optionName: 'L', extraPrice: 6000)],
      ),
    );
    expect(json, {
      'foodId': 2,
      'quantity': 2,
      'optionIds': [21],
      'note': 'Ít đá',
    });
  });

  group('IdempotencyKeeper', () {
    test('cùng nội dung → dùng lại key; đổi nội dung hoặc reset → key mới', () {
      var n = 0;
      final keeper = IdempotencyKeeper(generate: () => 'key-${++n}');
      expect(keeper.keyFor('A'), 'key-1');
      expect(keeper.keyFor('A'), 'key-1', reason: 'bấm lại sau khi mất mạng');
      expect(keeper.keyFor('B'), 'key-2', reason: 'đổi giỏ / voucher / phương thức → đơn khác');
      keeper.reset();
      expect(keeper.keyFor('B'), 'key-3');
    });

    test('mặc định sinh GUID', () {
      expect(IdempotencyKeeper().keyFor('x'), matches(RegExp(r'^[0-9a-f-]{36}$')));
    });
  });
}
