import 'package:campus_canteen/core/config/app_config.dart';
import 'package:campus_canteen/core/responsive/breakpoints.dart';
import 'package:campus_canteen/core/utils/money.dart';
import 'package:campus_canteen/core/utils/validators.dart';
import 'package:campus_canteen/core/utils/vn_time.dart';
import 'package:campus_canteen/models/enums.dart';
import 'package:campus_canteen/models/menu.dart';
import 'package:campus_canteen/models/order.dart';
import 'package:campus_canteen/models/paged_result.dart';
import 'package:campus_canteen/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money', () {
    test('định dạng VNĐ', () {
      expect(Money.format(8000), '8.000đ');
      expect(Money.format(1250000), '1.250.000đ');
      expect(Money.format(0), '0đ');
      expect(Money.signed(5000), '+5.000đ');
      expect(Money.signed(-5000), '−5.000đ');
    });

    test('rút gọn cho biểu đồ', () {
      expect(Money.compact(56000), '56k');
      expect(Money.compact(36821300), '36,8tr');
      expect(Money.compact(1500000000), '1,5tỷ');
      expect(Money.compact(900), '900');
    });
  });

  group('VnTime', () {
    test('UTC → giờ Việt Nam (+7)', () {
      final t = VnTime.parse('2026-11-16T17:30:00Z');
      expect(t.isUtc, isTrue);
      expect(VnTime.time(t), '00:30');
      expect(VnTime.date(t), '17/11/2026');
    });

    test('thời gian tương đối', () {
      final now = DateTime.utc(2026, 11, 16, 5); // 12:00 giờ VN
      expect(VnTime.relative(now.subtract(const Duration(seconds: 20)), now: now), 'Vừa xong');
      expect(VnTime.relative(now.subtract(const Duration(minutes: 5)), now: now), '5 phút trước');
      expect(VnTime.relative(now.subtract(const Duration(hours: 3)), now: now), '3 giờ trước');
      expect(VnTime.relative(DateTime.utc(2026, 11, 15, 3, 5), now: now), 'Hôm qua 10:05');
    });

    test('hôm nay theo giờ VN (23:30 UTC đã là ngày hôm sau)', () {
      expect(VnTime.today(now: DateTime.utc(2026, 11, 16, 23, 30)), DateTime.utc(2026, 11, 17));
      expect(VnTime.isoDate(DateTime.utc(2026, 11, 7)), '2026-11-07');
      expect(VnTime.fromEpochMs(0), DateTime.utc(1970));
    });
  });

  group('Validators', () {
    test('email, mật khẩu, họ tên', () {
      expect(Validators.email('sv01@smartcanteen.vn'), isNull);
      expect(Validators.email('sv01'), isNotNull);
      expect(Validators.password('12345'), isNotNull);
      expect(Validators.password('Canteen@123'), isNull);
      expect(Validators.fullName('A'), isNotNull);
      expect(Validators.fullName('Nguyễn Văn A'), isNull);
    });

    test('MSSV 10 số, số điện thoại không bắt buộc, địa chỉ máy chủ', () {
      expect(Validators.studentCode('0023414143'), isNull);
      expect(Validators.studentCode('12345'), isNotNull);
      expect(Validators.optionalPhone(''), isNull);
      expect(Validators.optionalPhone('0912345678'), isNull);
      expect(Validators.optionalPhone('+84912345678'), isNull);
      expect(Validators.optionalPhone('12345'), isNotNull);
      expect(Validators.serverUrl('http://192.168.1.10:5265'), isNull);
      expect(Validators.serverUrl('192.168.1.10'), isNotNull);
      expect(Validators.serverUrl(''), isNotNull);
    });

    test('chuẩn hóa địa chỉ máy chủ', () {
      expect(AppConfig.normalizeBaseUrl('  http://10.0.2.2:5265// '), 'http://10.0.2.2:5265');
    });
  });

  test('số cột lưới món và cỡ màn hình', () {
    expect(Breakpoints.gridColumns(360), 2);
    expect(Breakpoints.gridColumns(700), 3);
    expect(Breakpoints.gridColumns(1100), 4);
    expect(Breakpoints.gridColumns(1400), 5);
    expect(ScreenSize.fromWidth(599), ScreenSize.compact);
    expect(ScreenSize.fromWidth(600), ScreenSize.medium);
    expect(ScreenSize.fromWidth(1024), ScreenSize.expanded);
  });

  group('Model fromJson', () {
    test('enum đọc chuỗi camelCase, không phân biệt hoa thường, giá trị lạ dùng mặc định', () {
      expect(OrderStatus.fromJson('cooking'), OrderStatus.cooking);
      expect(OrderStatus.fromJson('Ready'), OrderStatus.ready);
      expect(PaymentMethod.fromJson('bankTransfer'), PaymentMethod.bankTransfer);
      expect(UserRole.fromJson('staff').isStaffOrAdmin, isTrue);
      expect(PaymentStatus.fromJson('???'), PaymentStatus.pending);
      expect(OrderStatus.ready.isActive, isTrue);
      expect(OrderStatus.cancelled.step, -1);
    });

    test('UserProfile', () {
      final u = UserProfile.fromJson({
        'id': 'uid1',
        'email': 'sv01@smartcanteen.vn',
        'fullName': 'Nguyễn Văn An',
        'studentCode': '0023414143',
        'role': 'student',
        'isActive': true,
        'createdAt': '2026-11-01T02:00:00Z',
        'lastLoginAt': null,
      });
      expect(u.role, UserRole.student);
      expect(u.createdAt, DateTime.utc(2026, 11, 1, 2));
      expect(u.lastLoginAt, isNull);
      expect(u.initials, isNotEmpty);
    });

    test('FoodDetail + nhóm tùy chọn, imageUrl null', () {
      final f = FoodDetail.fromJson({
        'id': 3,
        'name': 'Trà sữa trân châu',
        'price': 25000,
        'imageUrl': null,
        'categoryId': 2,
        'categoryName': 'Đồ uống',
        'averageRating': 4.5,
        'ratingCount': 12,
        'remainingToday': 8,
        'description': 'Ngon',
        'dailyLimit': 50,
        'rowVersion': 'AAAA',
        'createdAt': '2026-11-01T00:00:00Z',
        'updatedAt': '2026-11-02T00:00:00Z',
        'optionGroups': [
          {
            'id': 1,
            'name': 'Size',
            'isRequired': true,
            'minSelect': 1,
            'maxSelect': 1,
            'options': [
              {'id': 12, 'name': 'L', 'extraPrice': 5000},
            ],
          },
        ],
      });
      expect(f.summary.imageUrl, isNull);
      expect(f.summary.hasOptions, isTrue);
      expect(f.summary.averageRating, 4.5);
      expect(f.optionGroups.single.isSingleChoice, isTrue);
      expect(f.optionGroups.single.options.single.extraPrice, 5000);
    });

    test('PagedResult + OrderSummary', () {
      final page = PagedResult.fromJson({
        'items': [
          {
            'id': 'o1',
            'pickupCode': 'A001',
            'status': 'ready',
            'paymentMethod': 'cash',
            'paymentStatus': 'pending',
            'totalAmount': 35000,
            'totalItems': 1,
            'itemsPreview': 'Cơm gà ×1',
            'customerName': 'An',
            'createdAt': '2026-11-16T03:00:00Z',
            'pickupTime': '2026-11-16T04:30:00Z',
          },
        ],
        'page': 1,
        'pageSize': 20,
        'totalCount': 21,
        'totalPages': 2,
        'hasNext': true,
      }, OrderSummary.fromJson);
      expect(page.hasNext, isTrue);
      expect(page.items.single.status, OrderStatus.ready);
      expect(VnTime.time(page.items.single.pickupTime!), '11:30');
    });

    test('OrderDetail với thanh toán chuyển khoản đang chờ', () {
      final o = OrderDetail.fromJson({
        'id': 'o1',
        'pickupCode': 'A001',
        'pickupDate': '2026-11-16',
        'status': 'received',
        'paymentMethod': 'bankTransfer',
        'paymentStatus': 'pending',
        'subtotal': 8000,
        'discountAmount': 0,
        'totalAmount': 8000,
        'totalItems': 1,
        'createdAt': '2026-11-16T03:00:00Z',
        'updatedAt': '2026-11-16T03:00:00Z',
        'customer': {'id': 'u1', 'fullName': 'An'},
        'items': [
          {'id': 1, 'foodId': null, 'foodName': 'Nước suối', 'unitPrice': 8000, 'quantity': 1, 'lineTotal': 8000},
        ],
        'history': [
          {'fromStatus': null, 'toStatus': 'received', 'changedByName': 'An', 'changedAt': '2026-11-16T03:00:00Z'},
        ],
        'payment': {'method': 'bankTransfer', 'status': 'pending', 'amount': 8000, 'qrCode': '000201...', 'expiresAt': '2026-11-16T03:15:00Z'},
        'canCancel': true,
        'allowedNextStatuses': ['cooking', 'cancelled'],
      });
      expect(o.payment!.awaitingTransfer, isTrue);
      expect(o.items.single.foodId, isNull);
      expect(o.history.single.fromStatus, isNull);
      expect(o.allowedNextStatuses, [OrderStatus.cooking, OrderStatus.cancelled]);
      expect(o.itemsPreview, 'Nước suối ×1');
    });
  });
}
