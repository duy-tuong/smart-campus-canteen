import 'dart:async';

/// Gộp nhiều lần gọi liên tiếp thành một (ví dụ ô tìm kiếm: chỉ gọi API khi người dùng ngừng gõ 400ms).
class Debouncer {
  Debouncer({this.delay = const Duration(milliseconds: 400)});

  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() => _timer?.cancel();

  void dispose() => _timer?.cancel();
}
