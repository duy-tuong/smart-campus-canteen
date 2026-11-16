import 'package:campus_canteen/data/firebase/auth_service.dart';
import 'package:campus_canteen/providers/settings_provider.dart';
import 'package:campus_canteen/screens/auth/complete_profile_screen.dart';
import 'package:campus_canteen/screens/auth/login_screen.dart';
import 'package:campus_canteen/screens/auth/register_screen.dart';
import 'package:campus_canteen/screens/home/home_shell.dart';
import 'package:campus_canteen/screens/staff/staff_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_harness.dart';
import '../support/fakes.dart';

/// Luồng xác thực đầy đủ qua giao diện: AuthGate (authStateChanges) → Đăng nhập / Đăng ký /
/// Hoàn tất hồ sơ / Bị khóa / Lỗi mạng → khung theo vai trò.
void main() {
  late AppHarness app;
  late SettingsProvider settings;
  late FakeAuthService auth;
  late FakeBackend backend;

  setUp(() async {
    app = await AppHarness.create();
    settings = app.settings;
    backend = app.backend;
  });

  Future<void> pumpApp(WidgetTester tester, {AuthUser? signedIn}) async {
    await app.pump(tester, signedIn: signedIn);
    auth = app.auth;
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> tapText(WidgetTester tester, String text, {Type? type}) async {
    final finder = type == null ? find.text(text) : find.widgetWithText(type, text);
    await tester.ensureVisible(finder.first);
    await tester.pump(); // ensureVisible chỉ đổi vị trí cuộn — cần một khung hình để bố cục lại
    await tester.tap(finder.first);
    await tester.pumpAndSettle();
  }

  group('Đăng nhập', () {
    testWidgets('chưa đăng nhập → màn Đăng nhập; bỏ trống → báo lỗi từng ô', (tester) async {
      await pumpApp(tester);
      expect(find.byType(LoginScreen), findsOneWidget);

      await tapText(tester, 'Đăng nhập', type: FilledButton);
      expect(find.text('Vui lòng nhập email.'), findsOneWidget);
      expect(find.text('Vui lòng nhập mật khẩu.'), findsOneWidget);
    });

    testWidgets('sai mật khẩu → thông báo lỗi tiếng Việt', (tester) async {
      await pumpApp(tester);
      await tester.enterText(field('Email'), 'sv01@smartcanteen.vn');
      await tester.enterText(field('Mật khẩu'), 'sai-mat-khau');
      await tapText(tester, 'Đăng nhập', type: FilledButton);

      expect(find.text('Email hoặc mật khẩu không đúng.'), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('tài khoản demo sinh viên → khung Sinh viên, tab Tài khoản hiện hồ sơ', (tester) async {
      await pumpApp(tester);
      await tapText(tester, 'Sinh viên');
      await tapText(tester, 'Đăng nhập', type: FilledButton);

      expect(find.byType(HomeShell), findsOneWidget);
      await tapText(tester, 'Tài khoản');
      expect(find.text('Nguyễn Văn An'), findsOneWidget);
      expect(find.text('0023410001'), findsOneWidget);
    });

    testWidgets('nhân viên → khung Nhân viên (không có tab Người dùng); admin thì có', (tester) async {
      await pumpApp(tester);
      await tapText(tester, 'Nhân viên');
      await tapText(tester, 'Đăng nhập', type: FilledButton);
      expect(find.byType(StaffShell), findsOneWidget);
      expect(find.text('Bảng đơn'), findsWidgets);
      expect(find.text('Người dùng'), findsNothing);
      expect(auth.tokenRequests, contains(true), reason: 'làm mới token để có claim role');

      await auth.signOut();
      await tester.pumpAndSettle();
      await tapText(tester, 'Quản trị');
      await tapText(tester, 'Đăng nhập', type: FilledButton);
      expect(find.text('Người dùng'), findsWidgets);
    });

    testWidgets('quên mật khẩu: điền sẵn email, gửi liên kết', (tester) async {
      await pumpApp(tester);
      await tester.enterText(field('Email'), 'sv01@smartcanteen.vn');
      await tapText(tester, 'Quên mật khẩu?');

      expect(find.text('Quên mật khẩu'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'sv01@smartcanteen.vn'), findsOneWidget);
      await tapText(tester, 'Gửi liên kết');
      expect(auth.lastResetEmail, 'sv01@smartcanteen.vn');
      expect(find.text('Quay lại đăng nhập'), findsOneWidget);

      await tapText(tester, 'Quay lại đăng nhập');
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('Đăng ký', () {
    Future<void> fillRegister(WidgetTester tester, {String studentCode = '0023418888'}) async {
      await tester.enterText(field('Họ và tên'), 'Lê Minh Châu');
      await tester.enterText(field('Mã số sinh viên'), studentCode);
      await tester.enterText(field('Email'), 'moi@smartcanteen.vn');
      await tester.enterText(field('Mật khẩu'), 'Canteen@123');
      await tester.enterText(field('Nhập lại mật khẩu'), 'Canteen@123');
    }

    testWidgets('kiểm tra form: MSSV chỉ nhận số, mật khẩu nhập lại phải khớp', (tester) async {
      await pumpApp(tester);
      await tapText(tester, 'Đăng ký', type: TextButton);
      expect(find.byType(RegisterScreen), findsOneWidget);

      await tester.enterText(field('Mã số sinh viên'), 'ab12');
      expect(find.widgetWithText(TextFormField, '12'), findsOneWidget, reason: 'bộ lọc chỉ giữ chữ số');
      await tester.enterText(field('Mật khẩu'), 'Canteen@123');
      await tester.enterText(field('Nhập lại mật khẩu'), 'khac');
      await tapText(tester, 'Đăng ký', type: FilledButton);

      expect(find.text('Mã số sinh viên gồm đúng 10 chữ số.'), findsOneWidget);
      expect(find.text('Mật khẩu nhập lại không khớp.'), findsOneWidget);
    });

    testWidgets('đăng ký thành công → đóng màn Đăng ký, vào khung Sinh viên', (tester) async {
      await pumpApp(tester);
      await tapText(tester, 'Đăng ký', type: TextButton);
      await fillRegister(tester);
      await tapText(tester, 'Đăng ký', type: FilledButton);

      expect(find.byType(RegisterScreen), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(backend.profiles['uid-moi']!['fullName'], 'Lê Minh Châu');
    });

    testWidgets('trùng MSSV → màn Hoàn tất hồ sơ điền sẵn + báo lỗi; sửa MSSV → vào app', (tester) async {
      backend.takenStudentCodes.add('0023410001');
      await pumpApp(tester);
      await tapText(tester, 'Đăng ký', type: TextButton);
      await fillRegister(tester, studentCode: '0023410001');
      await tapText(tester, 'Đăng ký', type: FilledButton);

      expect(find.byType(CompleteProfileScreen), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Lê Minh Châu'), findsOneWidget);
      expect(find.text('Mã số sinh viên đã được sử dụng.'), findsOneWidget);

      await tester.enterText(field('Mã số sinh viên'), '0023417777');
      await tapText(tester, 'Bắt đầu đặt món');
      expect(find.byType(HomeShell), findsOneWidget);
    });

    testWidgets('email đã đăng ký → báo lỗi ngay ô Email', (tester) async {
      await pumpApp(tester);
      await tapText(tester, 'Đăng ký', type: TextButton);
      await fillRegister(tester);
      await tester.enterText(field('Email'), 'sv01@smartcanteen.vn');
      await tapText(tester, 'Đăng ký', type: FilledButton);

      expect(find.text('Email này đã được đăng ký. Hãy đăng nhập.'), findsOneWidget);
      expect(find.byType(RegisterScreen), findsOneWidget);
    });
  });

  group('Phiên đăng nhập', () {
    testWidgets('đã đăng nhập nhưng chưa có hồ sơ → Hoàn tất hồ sơ', (tester) async {
      await pumpApp(
        tester,
        signedIn: const AuthUser(uid: 'uid-new', email: 'new@smartcanteen.vn'),
      );
      expect(find.byType(CompleteProfileScreen), findsOneWidget);
      expect(find.text('new@smartcanteen.vn'), findsOneWidget);

      await tester.enterText(field('Họ và tên'), 'Phạm Dũng');
      await tester.enterText(field('Mã số sinh viên'), '0023416666');
      await tapText(tester, 'Bắt đầu đặt món');
      expect(find.byType(HomeShell), findsOneWidget);
    });

    testWidgets('tài khoản bị khóa → màn thông báo; Đăng xuất → về Đăng nhập', (tester) async {
      backend.locked.add('uid-sv01');
      await pumpApp(
        tester,
        signedIn: const AuthUser(uid: 'uid-sv01', email: 'sv01@smartcanteen.vn'),
      );
      expect(find.text('Tài khoản đã bị khóa'), findsOneWidget);

      await tapText(tester, 'Đăng xuất');
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('mất kết nối → màn lỗi; Thử lại khi có mạng → vào app', (tester) async {
      backend.offline = true;
      await pumpApp(
        tester,
        signedIn: const AuthUser(uid: 'uid-sv01', email: 'sv01@smartcanteen.vn'),
      );
      expect(find.text('Không có kết nối'), findsOneWidget);

      backend.offline = false;
      await tapText(tester, 'Thử lại');
      expect(find.byType(HomeShell), findsOneWidget);
    });

    testWidgets('đăng xuất từ tab Tài khoản (có hỏi xác nhận)', (tester) async {
      await pumpApp(
        tester,
        signedIn: const AuthUser(uid: 'uid-sv01', email: 'sv01@smartcanteen.vn'),
      );
      await tapText(tester, 'Tài khoản');
      await tapText(tester, 'Đăng xuất', type: OutlinedButton);
      expect(find.text('Đăng xuất?'), findsOneWidget);

      await tapText(tester, 'Đăng xuất', type: FilledButton);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(auth.signOutCount, 1);
    });

    testWidgets('đổi giao diện Tối ở tab Tài khoản và lưu lại', (tester) async {
      await pumpApp(
        tester,
        signedIn: const AuthUser(uid: 'uid-sv01', email: 'sv01@smartcanteen.vn'),
      );
      await tapText(tester, 'Tài khoản');
      await tapText(tester, 'Tối');

      expect(settings.themeMode, ThemeMode.dark);
      expect(Theme.of(tester.element(find.text('Giao diện'))).brightness, Brightness.dark);
      expect((await SharedPreferences.getInstance()).getString('settings.themeMode'), 'dark');
    });
  });

  testWidgets('Cài đặt máy chủ (mở từ màn Đăng nhập): kiểm tra địa chỉ, kết nối, lưu', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Cài đặt máy chủ'));
    await tester.pumpAndSettle();
    expect(find.text('Cài đặt máy chủ'), findsOneWidget);

    final input = find.byType(TextFormField);
    await tester.enterText(input, '192.168.1.10');
    await tapText(tester, 'Kiểm tra kết nối');
    expect(find.text('Địa chỉ dạng http://192.168.1.10:5265'), findsOneWidget);

    await tester.enterText(input, 'http://192.168.1.10:5265/');
    await tapText(tester, 'Kiểm tra kết nối');
    expect(find.text('Kết nối thành công'), findsOneWidget);

    await tapText(tester, 'Lưu');
    expect(settings.apiBaseUrl, 'http://192.168.1.10:5265');
    expect(find.byType(LoginScreen), findsOneWidget, reason: 'lưu xong quay lại');
  });
}
