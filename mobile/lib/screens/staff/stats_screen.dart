import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/money.dart';
import '../../core/utils/vn_time.dart';
import '../../data/remote/stats_api.dart';
import '../../models/enums.dart';
import '../../models/stats.dart';
import '../../widgets/state_views.dart';
import 'stats_charts.dart';

enum _Preset {
  today('Hôm nay', 1),
  week('7 ngày', 7),
  month('30 ngày', 30),
  custom('Tùy chọn', 0);

  const _Preset(this.label, this.days);
  final String label;
  final int days;
}

/// Bảng thống kê (staff/admin).
///
/// Ba khối dữ liệu, mỗi khối một Future riêng (tạo trong State, KHÔNG tạo trong build):
///  - tổng quan + giờ cao điểm + danh mục (gọi song song) — FutureBuilder xử lý tường minh từng ConnectionState,
///    khi tải lại vẫn giữ số liệu cũ và hiện thanh tiến trình mỏng thay vì nháy trắng;
///  - doanh thu theo ngày/tuần/tháng (đổi cách nhóm chỉ tải lại khối này);
///  - món bán chạy theo số lượng/doanh thu.
/// LayoutBuilder: màn rộng xếp 2 cột, thẻ tổng quan 4 cột; điện thoại 1 cột, thẻ 2 cột.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.now});

  /// Cho test cố định "hôm nay".
  final DateTime? now;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late final StatsApi _api = context.read<StatsApi>();

  _Preset _preset = _Preset.week;
  late StatsRange _range = StatsRange.lastDays(7, now: widget.now);
  late RevenueGroup _group = _range.defaultGroup;
  TopFoodSort _sort = TopFoodSort.quantity;

  late Future<StatsSummary> _summary;
  Future<RevenueSeries>? _revenue;
  late Future<List<TopFood>> _top;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  /// Khối doanh thu / top món chỉ được dựng SAU khi tổng quan về → nếu Future của chúng lỗi trước đó thì
  /// chưa có ai lắng nghe và lỗi bị coi là "unhandled". `ignore()` gắn sẵn một listener rỗng;
  /// FutureBuilder lắng nghe sau vẫn nhận lỗi bình thường.
  static Future<T> _handled<T>(Future<T> future) => future..ignore();

  void _loadAll() {
    _summary = _api.summary(_range);
    _loadRevenue();
    _loadTop();
  }

  /// "Hôm nay" chỉ có 1 điểm doanh thu → không vẽ đường; biểu đồ theo giờ đã đủ.
  void _loadRevenue() {
    _revenue = _range.days > 1 ? _handled(_api.revenue(_range, _group)) : null;
  }

  void _loadTop() {
    _top = _handled(_api.topFoods(_range, sortBy: _sort));
  }

  Future<void> _refresh() async {
    setState(_loadAll);
    await Future.wait<Object?>([
      _summary.then<Object?>((v) => v, onError: (_) => null),
      if (_revenue != null) _revenue!.then<Object?>((v) => v, onError: (_) => null),
      _top.then<Object?>((v) => v, onError: (_) => null),
    ]);
  }

  void _setRange(_Preset preset, StatsRange range) {
    setState(() {
      _preset = preset;
      _range = range;
      _group = range.defaultGroup;
      _loadAll();
    });
  }

  Future<void> _pickCustom() async {
    final today = VnTime.today(now: widget.now);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 2),
      lastDate: DateTime(today.year, today.month, today.day),
      initialDateRange: DateTimeRange(
        start: DateTime(_range.from.year, _range.from.month, _range.from.day),
        end: DateTime(_range.to.year, _range.to.month, _range.to.day),
      ),
      helpText: 'Chọn khoảng thống kê',
      saveText: 'Xem',
    );
    if (picked == null || !mounted) return;
    final range = StatsRange(
      DateTime.utc(picked.start.year, picked.start.month, picked.start.day),
      DateTime.utc(picked.end.year, picked.end.month, picked.end.day),
    );
    if (range.days > 366) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Khoảng thống kê tối đa 366 ngày.')));
      return;
    }
    _setRange(_Preset.custom, range);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thống kê'),
        actions: [IconButton(onPressed: _refresh, tooltip: 'Tải lại', icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<StatsSummary>(
          future: _summary,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final children = <Widget>[_RangeBar(preset: _preset, range: _range, onPreset: _onPreset)];

            switch (snapshot.connectionState) {
              case ConnectionState.none:
              case ConnectionState.waiting:
              case ConnectionState.active:
                // Đổi khoảng ngày: FutureBuilder vẫn giữ dữ liệu cũ → hiện số cũ mờ đi + thanh tiến trình.
                children.add(const LinearProgressIndicator(minHeight: 2));
                children.add(
                  data == null
                      ? const _DashboardSkeleton()
                      : Opacity(opacity: 0.5, child: IgnorePointer(child: _dashboard(data))),
                );
              case ConnectionState.done:
                if (snapshot.hasError) {
                  children.add(
                    SizedBox(
                      height: 360,
                      child: ErrorView(error: snapshot.error!, onRetry: () => setState(_loadAll)),
                    ),
                  );
                } else if (data!.overview.isEmpty) {
                  children.add(
                    const SizedBox(
                      height: 360,
                      child: EmptyState(
                        icon: Icons.query_stats_rounded,
                        title: 'Chưa có đơn trong khoảng này',
                        message: 'Thử chọn khoảng thời gian dài hơn.',
                      ),
                    ),
                  );
                } else {
                  children.add(_dashboard(data));
                }
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: children,
            );
          },
        ),
      ),
    );
  }

  void _onPreset(_Preset p) {
    if (p == _Preset.custom) {
      _pickCustom();
    } else {
      _setRange(p, StatsRange.lastDays(p.days, now: widget.now));
    }
  }

  Widget _dashboard(StatsSummary data) {
    final overview = data.overview;
    final peak = data.peakHour;

    final revenueCard = _revenue == null
        ? null
        : _ChartCard(
            title: 'Doanh thu',
            trailing: SegmentedButton<RevenueGroup>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [for (final g in RevenueGroup.values) ButtonSegment(value: g, label: Text(g.label))],
              selected: {_group},
              onSelectionChanged: (s) => setState(() {
                _group = s.first;
                _loadRevenue();
              }),
            ),
            child: _SectionFuture<RevenueSeries>(
              future: _revenue!,
              height: 220,
              onRetry: () => setState(_loadRevenue),
              builder: (series) => SizedBox(
                height: 220,
                child: series.points.length < 2
                    ? const _ChartNote('Cần ít nhất 2 kỳ để vẽ xu hướng — hãy chọn cách nhóm nhỏ hơn.')
                    // Chừa lề phải để nhãn ngày cuối trục không bị cắt.
                    : Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: RevenueLineChart(series: series),
                      ),
              ),
            ),
          );

    final hourlyCard = _ChartCard(
      title: 'Giờ cao điểm',
      subtitle: peak == null ? null : 'Đông nhất ${peak.hour}:00–${peak.hour}:59 · ${peak.orders} đơn',
      child: SizedBox(
        height: 200,
        child: peak == null
            ? const _ChartNote('Chưa có đơn.')
            : HourlyBarChart(hourly: data.hourly, peakHour: peak.hour),
      ),
    );

    final categoryCard = _ChartCard(
      title: 'Doanh thu theo danh mục',
      child: Column(
        children: [
          for (final c in data.categories)
            MeterRow(
              label: c.name,
              value: '${c.percent.toStringAsFixed(1).replaceAll('.', ',')}%',
              fraction: c.percent / 100,
              caption: '${Money.compact(c.revenue)} · ${c.quantity} phần',
            ),
        ],
      ),
    );

    final topCard = _ChartCard(
      title: 'Món bán chạy',
      trailing: SegmentedButton<TopFoodSort>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [for (final s in TopFoodSort.values) ButtonSegment(value: s, label: Text(s.label))],
        selected: {_sort},
        onSelectionChanged: (s) => setState(() {
          _sort = s.first;
          _loadTop();
        }),
      ),
      child: _SectionFuture<List<TopFood>>(
        future: _top,
        height: 280,
        onRetry: () => setState(_loadTop),
        builder: (foods) => foods.isEmpty ? const _ChartNote('Chưa có món nào được bán.') : _TopFoods(foods, _sort),
      ),
    );

    final paymentCard = _ChartCard(title: 'Thanh toán & khuyến mãi', child: _PaymentDetails(overview));

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final kpis = _KpiGrid(overview: overview, columns: constraints.maxWidth >= 720 ? 4 : 2);
        if (!wide) {
          return Column(children: [kpis, ?revenueCard, hourlyCard, categoryCard, topCard, paymentCard]);
        }
        return Column(
          children: [
            kpis,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(children: [?revenueCard, topCard])),
                Expanded(child: Column(children: [hourlyCard, categoryCard, paymentCard])),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Chọn khoảng: Hôm nay / 7 ngày / 30 ngày / Tùy chọn (DateRangePicker), kèm dòng mô tả kỳ so sánh.
class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.preset, required this.range, required this.onPreset});

  final _Preset preset;
  final StatsRange range;
  final ValueChanged<_Preset> onPreset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final p in _Preset.values)
                ChoiceChip(
                  label: Text(p.label),
                  avatar: p == _Preset.custom ? const Icon(Icons.date_range_rounded, size: 18) : null,
                  showCheckmark: false,
                  selected: p == preset,
                  onSelected: (_) => onPreset(p),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${range.label} · ${range.days} ngày',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 4 thẻ số liệu chính. Số lớn bọc FittedBox để không tràn ở màn hẹp / chữ lớn.
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.overview, required this.columns});

  final StatsOverview overview;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final tiles = [
      _KpiTile(
        icon: Icons.payments_outlined,
        label: 'Doanh thu',
        value: Money.format(o.revenue),
        change: o.revenueChangePercent,
        hasPrevious: o.previousRevenue > 0,
      ),
      _KpiTile(
        icon: Icons.receipt_long_outlined,
        label: 'Đơn hoàn thành',
        value: '${o.completedOrders}',
        change: o.ordersChangePercent,
        hasPrevious: o.previousCompletedOrders > 0,
      ),
      _KpiTile(
        icon: Icons.shopping_basket_outlined,
        label: 'Trung bình / đơn',
        value: Money.format(o.averageOrderValue),
        note: '${o.uniqueCustomers} khách hàng',
      ),
      _KpiTile(
        icon: Icons.cancel_outlined,
        label: 'Tỷ lệ hủy',
        value: '${o.cancelRate.toStringAsFixed(1).replaceAll('.', ',')}%',
        note: '${o.cancelledOrders} đơn bị hủy',
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - AppSpacing.xxs),
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i += columns)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final t in tiles.skip(i).take(columns)) Expanded(child: t)],
              ),
            ),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.icon,
    required this.label,
    required this.value,
    this.change,
    this.hasPrevious = false,
    this.note,
  });

  final IconData icon;
  final String label;
  final String value;

  /// % thay đổi so với kỳ trước (tăng = tốt).
  final double? change;
  final bool hasPrevious;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget footer;
    if (note != null) {
      footer = Text(note!, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis);
    } else if (change == null || !hasPrevious) {
      footer = Text('Kỳ trước chưa có dữ liệu', style: muted, maxLines: 1, overflow: TextOverflow.ellipsis);
    } else {
      final up = change! >= 0;
      final color = up ? context.appColors.success : context.appColors.cancelled;
      final pct = change!.abs() >= 1000 ? '>999' : change!.abs().toStringAsFixed(1).replaceAll('.', ',');
      // Mũi tên + chữ (không chỉ dựa vào màu) — người mù màu vẫn đọc được.
      footer = Row(
        children: [
          Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: color),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${up ? '+' : '−'}$pct%',
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(text: ' so với kỳ trước'),
                ],
              ),
              style: muted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.all(AppSpacing.xxs),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(label, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            footer,
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wrap: tiêu đề + nút chọn tự xuống dòng khi màn hẹp.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// FutureBuilder cho một khối nhỏ: giữ chiều cao cố định khi đang tải / lỗi để trang không nhảy.
class _SectionFuture<T> extends StatelessWidget {
  const _SectionFuture({required this.future, required this.builder, required this.onRetry, required this.height});

  final Future<T> future;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        final Widget child;
        if (snapshot.connectionState != ConnectionState.done) {
          child = snapshot.hasData
              ? Opacity(opacity: 0.5, child: builder(snapshot.data as T))
              : const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          child = Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(ErrorView.messageOf(snapshot.error!), textAlign: TextAlign.center),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Thử lại'),
                ),
              ],
            ),
          );
        } else {
          return builder(snapshot.data as T);
        }
        return snapshot.hasData ? child : SizedBox(height: height, child: child);
      },
    );
  }
}

class _ChartNote extends StatelessWidget {
  const _ChartNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Top món: hạng, tên, thanh so với món đứng đầu, số liệu theo tiêu chí đang chọn.
class _TopFoods extends StatelessWidget {
  const _TopFoods(this.foods, this.sort);

  final List<TopFood> foods;
  final TopFoodSort sort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    int metric(TopFood f) => sort == TopFoodSort.quantity ? f.quantity : f.revenue;
    final best = foods.map(metric).fold<int>(1, (m, v) => v > m ? v : m);
    return Column(children: [for (final (i, f) in foods.indexed) _row(context, theme, i, f, metric, best)]);
  }

  Widget _row(BuildContext context, ThemeData theme, int i, TopFood f, int Function(TopFood) metric, int best) {
    final rating = f.ratingCount == 0
        ? 'chưa có đánh giá'
        : '★ ${f.averageRating.toStringAsFixed(1).replaceAll('.', ',')} (${f.ratingCount})';
    return MeterRow(
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: i < 3 ? theme.colorScheme.primary : context.appColors.subtleBrand,
        child: Text(
          '${i + 1}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: i < 3 ? theme.colorScheme.onPrimary : theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      label: f.name,
      value: sort == TopFoodSort.quantity ? '${f.quantity} phần' : Money.compact(f.revenue),
      fraction: metric(f) / best,
      caption:
          '${f.categoryName} · ${sort == TopFoodSort.quantity ? Money.compact(f.revenue) : '${f.quantity} phần'} · $rating',
    );
  }
}

class _PaymentDetails extends StatelessWidget {
  const _PaymentDetails(this.o);

  final StatsOverview o;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalOrders = o.byPaymentMethod.fold<int>(0, (s, p) => s + p.orders);
    Widget line(IconData icon, String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );

    return Column(
      children: [
        for (final p in o.byPaymentMethod)
          MeterRow(
            label: p.method == PaymentMethod.cash ? 'Tiền mặt' : 'Chuyển khoản',
            value: Money.compact(p.revenue),
            fraction: totalOrders == 0 ? 0 : p.orders / totalOrders,
            caption: '${p.orders} đơn · ${totalOrders == 0 ? 0 : (p.orders * 100 / totalOrders).round()}% số đơn',
          ),
        const Divider(height: AppSpacing.lg),
        line(Icons.restaurant_menu_rounded, 'Món đã bán', '${o.itemsSold}'),
        line(Icons.local_offer_outlined, 'Đã giảm cho khách', Money.format(o.discountTotal)),
        o.refundOrders > 0
            ? line(
                Icons.warning_amber_rounded,
                'Cần hoàn tiền (${o.refundOrders} đơn)',
                Money.format(o.refundAmount),
                color: context.appColors.warning,
              )
            : line(Icons.check_circle_outline_rounded, 'Cần hoàn tiền', 'Không có'),
      ],
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 96, radius: AppRadius.lg)),
              SizedBox(width: AppSpacing.xs),
              Expanded(child: SkeletonBox(height: 96, radius: AppRadius.lg)),
            ],
          ),
          SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 96, radius: AppRadius.lg)),
              SizedBox(width: AppSpacing.xs),
              Expanded(child: SkeletonBox(height: 96, radius: AppRadius.lg)),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 260, radius: AppRadius.lg),
        ],
      ),
    );
  }
}
