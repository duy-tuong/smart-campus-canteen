import 'package:flutter/material.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import 'categories_screen.dart';
import 'menu_manage_screen.dart';
import 'reviews_moderation_screen.dart';
import 'vouchers_screen.dart';

/// Tab "Quản lý" của nhân viên: lối vào Thực đơn, Danh mục, Voucher, Đánh giá.
/// LayoutBuilder: điện thoại 1 cột, màn rộng lưới 2 cột.
class ManageHubScreen extends StatelessWidget {
  const ManageHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String, Widget Function())>[
      (
        Icons.restaurant_menu_rounded,
        'Thực đơn',
        'Thêm, sửa món · bật/tắt còn bán · ảnh · tùy chọn',
        MenuManageScreen.new,
      ),
      (Icons.category_rounded, 'Danh mục', 'Thêm, đổi tên, sắp xếp, ẩn danh mục', CategoriesScreen.new),
      (Icons.local_offer_rounded, 'Voucher', 'Tạo mã giảm giá, thời hạn, giới hạn lượt dùng', VouchersScreen.new),
      (Icons.rate_review_rounded, 'Đánh giá', 'Trả lời khách, ẩn đánh giá vi phạm', ReviewsModerationScreen.new),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 720 ? 2 : 1;
          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              mainAxisExtent: 96 * MediaQuery.textScalerOf(context).scale(14) / 14,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final (icon, title, subtitle, page) = items[i];
              return Card(
                child: InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page())),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: context.appColors.subtleBrand,
                            borderRadius: AppRadius.mdAll,
                          ),
                          child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: Theme.of(context).textTheme.titleMedium),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Giới hạn bề rộng form trên màn rộng (dùng chung cho các màn quản lý).
Widget formWidth(Widget child) => MaxWidthBox(maxWidth: 640, child: child);
