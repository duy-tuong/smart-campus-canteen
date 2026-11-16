import 'package:flutter/material.dart';

import 'state_views.dart';

/// FutureBuilder dùng chung, xử lý ĐỦ các ConnectionState:
///  - none / waiting  → [loading] (mặc định: skeleton danh sách)
///  - done + lỗi      → [ErrorView] kèm nút Thử lại ([onRetry])
///  - done + rỗng     → [empty] (khi [isEmpty] trả về true)
///  - done + dữ liệu  → [builder]
///
/// LƯU Ý: [future] phải được tạo sẵn trong initState / provider (giữ trong State),
/// KHÔNG tạo trong build() — nếu không mỗi lần rebuild sẽ gọi API lại.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.future,
    required this.builder,
    this.onRetry,
    this.isEmpty,
    this.empty,
    this.loading,
  });

  final Future<T>? future;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;
  final Widget? empty;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        switch (snapshot.connectionState) {
          case ConnectionState.none:
          case ConnectionState.waiting:
          case ConnectionState.active:
            return loading ?? const SkeletonList();
          case ConnectionState.done:
            if (snapshot.hasError) return ErrorView(error: snapshot.error!, onRetry: onRetry);
            final data = snapshot.data as T;
            if (isEmpty?.call(data) ?? false) {
              return empty ?? const EmptyState(icon: Icons.inbox_outlined, title: 'Chưa có dữ liệu');
            }
            return builder(context, data);
        }
      },
    );
  }
}
