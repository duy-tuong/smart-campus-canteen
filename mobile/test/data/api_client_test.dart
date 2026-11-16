import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campus_canteen/data/remote/api_client.dart';
import 'package:campus_canteen/data/remote/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  http.Response json(Object body, int status) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  ApiClient client(MockClientHandler handler, {String? token = 'tok', Duration timeout = const Duration(seconds: 5)}) =>
      ApiClient(
        baseUrl: () => 'http://api.test:5265/',
        tokenProvider: () async => token,
        httpClient: MockClient(handler),
        timeout: timeout,
      );

  test('GET: gắn Bearer token, ghép query (kể cả tham số lặp), giải mã UTF-8', () async {
    late http.Request captured;
    final api = client((request) async {
      captured = request;
      return json({'name': 'Cơm gà xối mỡ'}, 200);
    });

    final body = await api.get('/api/foods', query: {'q': 'com ga', 'ids': [1, 2], 'page': 2, 'skip': null});

    expect(body['name'], 'Cơm gà xối mỡ');
    expect(captured.method, 'GET');
    expect(captured.headers['Authorization'], 'Bearer tok');
    expect(captured.url.toString(), startsWith('http://api.test:5265/api/foods?'));
    expect(captured.url.queryParametersAll['ids'], ['1', '2']);
    expect(captured.url.queryParameters['q'], 'com ga');
    expect(captured.url.queryParameters.containsKey('skip'), isFalse);
  });

  test('POST: gửi JSON + header tùy chọn; chưa đăng nhập thì không có Authorization', () async {
    late http.Request captured;
    final api = client((request) async {
      captured = request;
      return json({'id': 'o1'}, 201);
    }, token: null);

    await api.post('/api/orders', body: {'note': 'Ít cay'}, headers: {'Idempotency-Key': 'k1'});

    expect(captured.headers.containsKey('Authorization'), isFalse);
    expect(captured.headers['Idempotency-Key'], 'k1');
    expect(captured.headers['Content-Type'], contains('application/json'));
    expect(jsonDecode(captured.body), {'note': 'Ít cay'});
  });

  test('PUT / PATCH / DELETE dùng đúng phương thức; 204 trả về null', () async {
    final methods = <String>[];
    final api = client((request) async {
      methods.add(request.method);
      return http.Response('', 204);
    });

    expect(await api.put('/a', body: {}), isNull);
    expect(await api.patch('/a', body: {}), isNull);
    expect(await api.delete('/a'), isNull);
    expect(methods, ['PUT', 'PATCH', 'DELETE']);
  });

  test('lỗi ProblemDetails → ApiException với code, lỗi trường và lỗi từng dòng', () async {
    final api = client((_) async => json({
          'status': 422,
          'title': 'Giỏ hàng có món không hợp lệ',
          'detail': 'Một số món không đặt được.',
          'code': 'ORDER_ITEMS_INVALID',
          'traceId': 't-1',
          'errors': {'Note': ['Ghi chú tối đa 200 ký tự.']},
          'items': [
            {'index': 0, 'foodId': 7, 'code': 'ITEM_SOLD_OUT', 'message': 'Hết món', 'remaining': 0},
          ],
        }, 422));

    try {
      await api.post('/api/orders/quote', body: {});
      fail('phải ném ApiException');
    } on ApiException catch (e) {
      expect(e.statusCode, 422);
      expect(e.code, ApiErrorCodes.orderItemsInvalid);
      expect(e.message, 'Một số món không đặt được.');
      expect(e.fieldError('note'), 'Ghi chú tối đa 200 ký tự.');
      expect(e.lineErrors.single['code'], 'ITEM_SOLD_OUT');
      expect(e.traceId, 't-1');
    }
  });

  test('401 / ACCOUNT_LOCKED được phát lên luồng authErrors; lỗi thường thì không', () async {
    var status = 401;
    var code = 'UNAUTHORIZED';
    final api = client((_) async => json({'code': code}, status));
    final events = <String>[];
    final sub = api.authErrors.listen((e) => events.add(e.code));

    await expectLater(api.get('/x'), throwsA(isA<ApiException>()));
    status = 403;
    code = 'ACCOUNT_LOCKED';
    await expectLater(api.get('/x'), throwsA(isA<ApiException>()));
    status = 409;
    code = 'CONCURRENCY_CONFLICT';
    await expectLater(api.get('/x'), throwsA(isA<ApiException>()));

    await Future<void>.delayed(Duration.zero);
    expect(events, ['UNAUTHORIZED', 'ACCOUNT_LOCKED']);
    await sub.cancel();
  });

  test('body lỗi không phải JSON vẫn có thông báo tiếng Việt theo mã HTTP', () async {
    final api = client((_) async => http.Response('Bad gateway', 502));
    await expectLater(
      api.get('/x'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Máy chủ đang gặp sự cố'))),
    );
  });

  test('mất kết nối và quá thời gian chờ → lỗi mạng', () async {
    final offline = client((_) async => throw const SocketException('down'));
    await expectLater(offline.get('/x'), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', isTrue)));

    final slow = client((_) => Completer<http.Response>().future, timeout: const Duration(milliseconds: 50));
    await expectLater(
      slow.get('/x'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiException.timeoutError)),
    );
  });

  test('checkHealth: dùng địa chỉ truyền vào, trả về true/false', () async {
    Uri? hit;
    final api = client((request) async {
      hit = request.url;
      return request.url.host == 'good' ? http.Response('{"status":"ok"}', 200) : throw const SocketException('x');
    });

    expect(await api.checkHealth(baseUrl: 'http://good:5265/'), isTrue);
    expect(hit.toString(), 'http://good:5265/api/health');
    expect(await api.checkHealth(baseUrl: 'http://bad:5265'), isFalse);
  });

  test('upload: multipart với trường "file"', () async {
    late http.Request captured;
    final api = client((request) async {
      captured = request;
      return json({'imageUrl': 'http://x/a.jpg'}, 200);
    });

    final body = await api.upload('/api/users/me/avatar', bytes: [1, 2, 3], fileName: 'a.jpg');
    expect(body['imageUrl'], 'http://x/a.jpg');
    expect(captured.headers['content-type'], startsWith('multipart/form-data'));
    expect(captured.body, contains('name="file"; filename="a.jpg"'));
  });
}
