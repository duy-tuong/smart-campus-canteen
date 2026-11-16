import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/validators.dart';
import '../../../data/remote/api_exception.dart';

/// Lỗi của một ô trong form hồ sơ, lấy từ phản hồi backend
/// (lỗi validate theo trường hoặc mã lỗi nghiệp vụ như STUDENT_CODE_TAKEN).
String? profileFieldError(ApiException? error, String field) {
  if (error == null) return null;
  if (field == 'studentCode' &&
      (error.code == ApiErrorCodes.studentCodeTaken || error.code == ApiErrorCodes.studentCodeLocked)) {
    return error.message;
  }
  return error.fieldError(field);
}

/// Lỗi chung (không gắn được vào ô nào) để hiện trên banner đầu form.
String? profileGeneralError(ApiException? error) {
  if (error == null) return null;
  final hasFieldError = const ['fullName', 'studentCode', 'phone'].any((f) => profileFieldError(error, f) != null);
  return hasFieldError ? null : error.message;
}

/// Ba ô thông tin sinh viên dùng chung cho màn Đăng ký và Hoàn tất hồ sơ.
class ProfileFields extends StatelessWidget {
  const ProfileFields({
    super.key,
    required this.fullName,
    required this.studentCode,
    required this.phone,
    this.error,
    this.lastAction = TextInputAction.next,
    this.onSubmitted,
  });

  final TextEditingController fullName;
  final TextEditingController studentCode;
  final TextEditingController phone;
  final ApiException? error;
  final TextInputAction lastAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        controller: fullName,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.name],
        validator: Validators.fullName,
        decoration: InputDecoration(
          labelText: 'Họ và tên',
          prefixIcon: const Icon(Icons.badge_outlined),
          errorText: profileFieldError(error, 'fullName'),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      TextFormField(
        controller: studentCode,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        validator: Validators.studentCode,
        decoration: InputDecoration(
          labelText: 'Mã số sinh viên',
          hintText: '10 chữ số',
          prefixIcon: const Icon(Icons.school_outlined),
          errorText: profileFieldError(error, 'studentCode'),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      TextFormField(
        controller: phone,
        keyboardType: TextInputType.phone,
        textInputAction: lastAction,
        onFieldSubmitted: onSubmitted,
        autofillHints: const [AutofillHints.telephoneNumber],
        validator: Validators.optionalPhone,
        decoration: InputDecoration(
          labelText: 'Số điện thoại (không bắt buộc)',
          prefixIcon: const Icon(Icons.phone_outlined),
          errorText: profileFieldError(error, 'phone'),
        ),
      ),
    ],
  );
}
