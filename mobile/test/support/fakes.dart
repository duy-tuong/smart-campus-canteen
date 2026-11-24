import 'dart:async';
import 'dart:convert';

import 'package:campus_canteen/data/firebase/auth_service.dart';
import 'package:campus_canteen/data/remote/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_admin.dart';
import 'fake_orders.dart';
import 'fake_reviews.dart';
import 'fake_staff.dart';

/// Firebase Auth giả: giữ người dùng trong bộ nhớ, phát sự kiện như authStateChanges() thật.
class FakeAuthService implements AuthService {
  FakeAuthService({AuthUser? signedIn, this.password = 'Canteen@123'}) : _user = signedIn;

  final String password;
  final _changes = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;

  final List<bool> tokenRequests = [];
  int signOutCount = 0;
  String? lastResetEmail;

  /// Email đã có tài khoản (đăng ký lại sẽ báo email-already-in-use).
  final Set<String> existingEmails = {'sv01@smartcanteen.vn'};

  static String uidFor(String email) => 'uid-${email.split('@').first}';

  void emit(AuthUser? user) {
    _user = user;
    _changes.add(user);
  }

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (password != this.password) throw FirebaseAuthService.failureFor('invalid-credential');
    emit(AuthUser(uid: uidFor(email.trim()), email: email.trim()));
  }

  @override
  Future<void> register({required String email, required String password}) async {
    if (existingEmails.contains(email.trim())) throw FirebaseAuthService.failureFor('email-already-in-use');
    emit(AuthUser(uid: uidFor(email.trim()), email: email.trim()));
  }

  @override
  Future<void> sendPasswordReset(String email) async => lastResetEmail = email;

  @override
  Future<void> signOut() async {
    signOutCount++;
    emit(null);
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    tokenRequests.add(forceRefresh);
    return _user == null ? null : 'token-${_user!.uid}';
  }

  Future<void> dispose() => _changes.close();
}

/// Hồ sơ JSON giống backend trả về.
Map<String, Object?> profileJson({
  String id = 'uid-sv01',
  String email = 'sv01@smartcanteen.vn',
  String fullName = 'Nguyễn Văn An',
  String role = 'student',
  String? studentCode = '0023410001',
}) => {
  'id': id,
  'email': email,
  'fullName': fullName,
  'studentCode': studentCode,
  'phone': null,
  'avatarUrl': null,
  'role': role,
  'isActive': true,
  'createdAt': '2026-11-01T02:00:00Z',
  'lastLoginAt': null,
};

http.Response jsonResponse(Object? body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response problem(int status, String code, String detail, {Map<String, List<String>>? errors}) =>
    jsonResponse({'status': status, 'title': detail, 'detail': detail, 'code': code, 'errors': ?errors}, status);

/// Backend giả cho /api/users/me: hồ sơ lưu theo uid (lấy từ token dạng `token-{uid}`).
class FakeBackend with FakeOrdering, FakeReviewing, FakeStaffing, FakeAdmin {
  @override
  final Map<String, Map<String, Object?>> profiles = {};
  @override
  final Set<String> locked = {};

  /// uid có token hết hạn → 401.
  final Set<String> expired = {};
  final Set<String> takenStudentCodes = {};
  final List<String> calls = [];
  bool offline = false;

  /// Trả lời trễ (để thử tình huống kết quả về muộn).
  Duration delay = Duration.zero;

  void addProfile(Map<String, Object?> json) => profiles[json['id'] as String] = json;

  ApiClient client({required AuthService auth}) =>
      ApiClient(baseUrl: () => 'http://api.test', tokenProvider: auth.idToken, httpClient: MockClient(_handle));

  Future<http.Response> _handle(http.Request request) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    calls.add('${request.method} ${request.url.path}');
    if (request.url.path == '/api/health') return http.Response('{"status":"ok"}', 200);
    if (offline) throw http.ClientException('offline');

    final token = request.headers['Authorization']?.replaceFirst('Bearer token-', '');
    if (token == null || expired.contains(token)) return problem(401, 'UNAUTHORIZED', 'Chưa đăng nhập.');
    if (locked.contains(token)) return problem(403, 'ACCOUNT_LOCKED', 'Tài khoản đã bị khóa.');

    if (request.url.path == '/api/users/me' && request.method == 'GET') {
      final profile = profiles[token];
      return profile == null
          ? problem(404, 'PROFILE_NOT_FOUND', 'Tài khoản chưa có hồ sơ.')
          : jsonResponse(profile, 200);
    }
    if (request.url.path == '/api/users/me' && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final code = body['studentCode'] as String;
      if (takenStudentCodes.contains(code)) {
        return problem(409, 'STUDENT_CODE_TAKEN', 'Mã số sinh viên đã được sử dụng.');
      }
      final profile = profileJson(
        id: token,
        email: '$token@test',
        fullName: body['fullName'] as String,
        studentCode: code,
      );
      profiles[token] = profile;
      return jsonResponse(profile, 201);
    }
    final adminResponse = handleAdmin(request, token);
    if (adminResponse != null) return adminResponse;
    final staffResponse = handleStaffing(request);
    if (staffResponse != null) return staffResponse;
    final reviewResponse = handleReviewing(request, token);
    if (reviewResponse != null) return reviewResponse;
    final orderResponse = handleOrdering(request, token);
    if (orderResponse != null) return orderResponse;
    final menuResponse = _menu(request);
    if (menuResponse != null) return menuResponse;
    return problem(404, 'NOT_FOUND', 'Không tìm thấy.');
  }

  // ------------------------------ Thực đơn giả ------------------------------

  /// Món đang yêu thích (PUT/DELETE /api/foods/{id}/favorite).
  final Set<int> favoriteIds = {};

  /// Bật để PUT/DELETE yêu thích trả lỗi 500 (thử hoàn tác cập nhật lạc quan).
  bool failFavorite = false;

  @override
  final List<Map<String, Object?>> categories = [
    {'id': 1, 'name': 'Cơm', 'icon': 'rice_bowl', 'sortOrder': 1, 'isActive': true, 'foodCount': 20},
    {'id': 3, 'name': 'Nước uống', 'icon': 'local_drink', 'sortOrder': 2, 'isActive': true, 'foodCount': 5},
  ];

  /// 25 món (2 trang khi pageSize = 20): #1 Cơm gà (tùy chọn không bắt buộc), #2 Trà sữa (Size bắt buộc),
  /// #3 Bánh flan (hết món), còn lại "Món số N".
  @override
  late final List<Map<String, Object?>> foods = [
    foodJson(1, 'Cơm gà xối mỡ', 35000, categoryId: 1, hasOptions: true, remaining: 8),
    foodJson(2, 'Trà sữa trân châu', 25000, categoryId: 3, hasOptions: true, rating: 4.5, ratingCount: 2),
    foodJson(3, 'Bánh flan', 12000, categoryId: 1, soldOut: true),
    for (var i = 4; i <= 25; i++) foodJson(i, 'Món số $i', 20000 + i * 100, categoryId: i.isEven ? 1 : 3),
  ];

  static Map<String, Object?> foodJson(
    int id,
    String name,
    int price, {
    int categoryId = 1,
    bool hasOptions = false,
    bool soldOut = false,
    int? remaining,
    double rating = 0,
    int ratingCount = 0,
  }) => {
    'id': id,
    'name': name,
    'price': price,
    'imageUrl': null,
    'categoryId': categoryId,
    'categoryName': categoryId == 1 ? 'Cơm' : 'Nước uống',
    'prepTimeMinutes': 5,
    'averageRating': rating,
    'ratingCount': ratingCount,
    'isAvailable': true,
    'remainingToday': soldOut ? 0 : remaining,
    'isSoldOut': soldOut,
    'hasOptions': hasOptions,
    'isFavorite': false,
  };

  static Map<String, Object?> _option(int id, String name, int extra, {bool available = true}) => {
    'id': id,
    'name': name,
    'extraPrice': extra,
    'isAvailable': available,
    'sortOrder': id,
  };

  @override
  List<Map<String, Object?>> groupsOf(int foodId) => _groupsOf(foodId);

  List<Map<String, Object?>> _groupsOf(int foodId) => switch (foodId) {
    1 => [
      {
        'id': 1,
        'name': 'Món thêm',
        'isRequired': false,
        'minSelect': 0,
        'maxSelect': 2,
        'sortOrder': 1,
        'options': [_option(11, 'Trứng ốp la', 6000), _option(12, 'Thêm cơm', 5000), _option(13, 'Canh rau', 3000)],
      },
    ],
    2 => [
      {
        'id': 2,
        'name': 'Size',
        'isRequired': true,
        'minSelect': 1,
        'maxSelect': 1,
        'sortOrder': 1,
        'options': [_option(21, 'L', 6000), _option(22, 'XL', 9000)],
      },
      {
        'id': 3,
        'name': 'Topping',
        'isRequired': false,
        'minSelect': 0,
        'maxSelect': 2,
        'sortOrder': 2,
        'options': [_option(31, 'Trân châu', 5000), _option(32, 'Pudding', 7000, available: false)],
      },
    ],
    _ => const [],
  };

  Map<String, Object?> _withFavorite(Map<String, Object?> food) => {
    ...food,
    'isFavorite': favoriteIds.contains(food['id']),
  };

  Map<String, Object?> _page(List<Map<String, Object?>> all, Uri url) {
    final page = int.tryParse(url.queryParameters['page'] ?? '') ?? 1;
    final size = int.tryParse(url.queryParameters['pageSize'] ?? '') ?? 20;
    final items = all.skip((page - 1) * size).take(size).toList();
    final totalPages = (all.length / size).ceil();
    return {
      'items': items,
      'page': page,
      'pageSize': size,
      'totalCount': all.length,
      'totalPages': totalPages,
      'hasNext': page < totalPages,
    };
  }

  Map<String, Object?> _review(int id, int rating, String? comment, String? reply) => {
    'id': id,
    'foodId': 2,
    'foodName': 'Trà sữa trân châu',
    'orderId': 'o$id',
    'rating': rating,
    'comment': comment,
    'authorName': 'An N.',
    'isMine': false,
    'canEdit': false,
    'isHidden': false,
    'hiddenReason': null,
    'staffReply': reply,
    'repliedAt': null,
    'createdAt': '2026-11-15T04:00:00Z',
    'updatedAt': '2026-11-15T04:00:00Z',
  };

  http.Response? _menu(http.Request request) {
    final path = request.url.path;
    final query = request.url.queryParameters;
    if (path == '/api/categories') return jsonResponse(categories, 200);

    if (path == '/api/foods') {
      final q = query['q']?.toLowerCase();
      final categoryId = int.tryParse(query['categoryId'] ?? '');
      final list = foods
          .where((f) => q == null || (f['name'] as String).toLowerCase().contains(q))
          .where((f) => categoryId == null || f['categoryId'] == categoryId)
          .where((f) => query['availableOnly'] != 'true' || f['isSoldOut'] != true)
          .map(_withFavorite)
          .toList();
      return jsonResponse(_page(list, request.url), 200);
    }

    if (path == '/api/users/me/favorites') {
      final list = foods.where((f) => favoriteIds.contains(f['id'])).map(_withFavorite).toList();
      return jsonResponse(_page(list, request.url), 200);
    }

    final match = RegExp(r'^/api/foods/(\d+)(/favorite|/reviews)?$').firstMatch(path);
    if (match == null) return null;
    final id = int.parse(match.group(1)!);
    final food = foods.where((f) => f['id'] == id).firstOrNull;
    if (food == null) return problem(404, 'NOT_FOUND', 'Không tìm thấy món.');

    switch (match.group(2)) {
      case '/favorite':
        if (failFavorite) return problem(500, 'INTERNAL', 'Máy chủ lỗi.');
        request.method == 'PUT' ? favoriteIds.add(id) : favoriteIds.remove(id);
        return http.Response('', 204);
      case '/reviews':
        final reviews = id == 2
            ? [_review(1, 5, 'Rất ngon!', 'Cảm ơn bạn!'), _review(2, 4, null, null)]
            : const <Map<String, Object?>>[];
        return jsonResponse({
          'summary': {
            'foodId': id,
            'average': id == 2 ? 4.5 : 0,
            'count': reviews.length,
            'distribution': {'5': id == 2 ? 1 : 0, '4': id == 2 ? 1 : 0, '3': 0, '2': 0, '1': 0},
          },
          'reviews': _page(reviews, request.url),
        }, 200);
      default:
        return jsonResponse({
          ..._withFavorite(food),
          'description': 'Mô tả món ${food['name']}',
          'dailyLimit': null,
          'optionGroups': _groupsOf(id),
          'rowVersion': 'AAAA',
          'createdAt': '2026-11-01T00:00:00Z',
          'updatedAt': '2026-11-01T00:00:00Z',
        }, 200);
    }
  }
}
