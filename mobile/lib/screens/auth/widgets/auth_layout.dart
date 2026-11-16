import 'package:flutter/material.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';

/// Khung chung cho màn Đăng nhập / Đăng ký / Quên mật khẩu / Hoàn tất hồ sơ.
///
/// LayoutBuilder chọn bố cục:
///  - hẹp (< 840): một cột — logo nhỏ, tiêu đề, form;
///  - rộng: hai cột — khối thương hiệu bên trái, form bên phải.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBack = false,
    this.actions,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: showBack,
        actions:
            actions ??
            [
              IconButton(
                tooltip: 'Cài đặt máy chủ',
                icon: const Icon(Icons.dns_outlined),
                onPressed: () => Navigator.pushNamed(context, AppRoutes.serverSettings),
              ),
            ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final form = _FormColumn(
              title: title,
              subtitle: subtitle,
              showLogo: constraints.maxWidth < 840,
              child: child,
            );
            if (constraints.maxWidth < 840) return form;
            return Row(
              children: [
                const Expanded(child: _BrandPanel()),
                Expanded(child: form),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FormColumn extends StatelessWidget {
  const _FormColumn({required this.title, required this.subtitle, required this.showLogo, required this.child});

  final String title;
  final String subtitle;
  final bool showLogo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        // Chừa chỗ cho bàn phím để nút cuối form không bị che.
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: MaxWidthBox(
        maxWidth: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showLogo) ...[
              const Align(alignment: Alignment.centerLeft, child: AppLogo(size: 56)),
              const SizedBox(height: AppSpacing.lg),
            ],
            Text(title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.xl),
            child,
          ],
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(color: context.appColors.subtleBrand, borderRadius: AppRadius.xlAll),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppLogo(size: 72),
          const SizedBox(height: AppSpacing.lg),
          Text('Smart Canteen', style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Đặt món trước, đến quầy là có — không cần xếp hàng.',
            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xl),
          for (final (icon, text) in const [
            (Icons.restaurant_menu_rounded, 'Thực đơn căn-tin cập nhật theo ngày'),
            (Icons.qr_code_2_rounded, 'Thanh toán chuyển khoản bằng QR'),
            (Icons.notifications_active_rounded, 'Báo ngay khi món sẵn sàng'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                children: [
                  Icon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Logo app: ô vuông bo góc màu cam với biểu tượng món ăn.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(color: primary.withValues(alpha: 0.3), blurRadius: size * 0.3, offset: Offset(0, size * 0.1)),
        ],
      ),
      child: Icon(Icons.lunch_dining_rounded, color: Colors.white, size: size * 0.56),
    );
  }
}

/// Thông báo lỗi chung của form (lỗi không thuộc ô nhập nào) — nền đỏ nhạt, có biểu tượng.
class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final color = context.appColors.cancelled;
    return AnimatedSize(
      duration: AppDurations.normal,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: AppRadius.mdAll),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, color: color, size: 20),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(message!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Nút chính có trạng thái đang xử lý (khóa nút, hiện vòng xoay) — tránh bấm hai lần.
class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.busy, required this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy ? null : onPressed,
    child: busy
        ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Text(label),
  );
}

/// Ô mật khẩu có nút hiện/ẩn.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Mật khẩu',
    this.validator,
    this.errorText,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.autofillHints = const [AutofillHints.password],
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final String? errorText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String> autofillHints;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    obscureText: _obscure,
    validator: widget.validator,
    textInputAction: widget.textInputAction,
    onFieldSubmitted: widget.onSubmitted,
    autofillHints: widget.autofillHints,
    decoration: InputDecoration(
      labelText: widget.label,
      errorText: widget.errorText,
      prefixIcon: const Icon(Icons.lock_outline_rounded),
      suffixIcon: IconButton(
        tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    ),
  );
}
