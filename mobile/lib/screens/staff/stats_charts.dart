import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/money.dart';
import '../../models/stats.dart';

/// Bước chia trục "đẹp" (1, 2, 2.5, 5 × 10^n) để có khoảng [ticks] vạch ngang.
double niceStep(double max, {int ticks = 4}) {
  if (max <= 0) return 1;
  final raw = max / ticks;
  final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (raw <= m * magnitude) return m * magnitude;
  }
  return 10 * magnitude;
}

/// Kiểu chữ & màu dùng chung cho trục, lưới, tooltip — trục/lưới mờ để dữ liệu nổi bật.
class _ChartStyle {
  _ChartStyle(BuildContext context)
    : scheme = Theme.of(context).colorScheme,
      axis = Theme.of(context).textTheme.labelSmall!.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w400,
      ),
      tooltip = Theme.of(
        context,
      ).textTheme.labelMedium!.copyWith(color: Theme.of(context).colorScheme.onInverseSurface);

  final ColorScheme scheme;
  final TextStyle axis;
  final TextStyle tooltip;

  Color get grid => scheme.outlineVariant.withValues(alpha: 0.5);

  FlGridData horizontalGrid(double interval) => FlGridData(
    drawVerticalLine: false,
    horizontalInterval: interval,
    getDrawingHorizontalLine: (_) => FlLine(color: grid, strokeWidth: 1),
  );

  AxisTitles moneyAxis(double interval) => AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 44,
      interval: interval,
      getTitlesWidget: (value, meta) => value == meta.max && value != 0
          ? const SizedBox.shrink()
          : SideTitleWidget(
              meta: meta,
              child: Text(Money.compact(value), style: axis),
            ),
    ),
  );

  static const AxisTitles none = AxisTitles();
}

/// Doanh thu theo thời gian: đường 2px màu thương hiệu, vùng tô nhạt, chạm để xem đường dóng + tooltip.
class RevenueLineChart extends StatelessWidget {
  const RevenueLineChart({super.key, required this.series});

  final RevenueSeries series;

  String _axisLabel(RevenuePoint p) => switch (series.group) {
    RevenueGroup.month => 'T${p.period.month}',
    _ => '${p.period.day.toString().padLeft(2, '0')}/${p.period.month.toString().padLeft(2, '0')}',
  };

  @override
  Widget build(BuildContext context) {
    final style = _ChartStyle(context);
    final points = series.points;
    final maxRevenue = points.fold<int>(0, (m, p) => math.max(m, p.revenue)).toDouble();
    final step = niceStep(maxRevenue);
    final maxY = math.max(step, (maxRevenue / step).ceil() * step);
    // Tối đa ~6 nhãn ngày dưới trục để không chồng chữ.
    final labelEvery = math.max(1, (points.length / 6).ceil());
    final color = style.scheme.primary;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        gridData: style.horizontalGrid(step),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: _ChartStyle.none,
          rightTitles: _ChartStyle.none,
          leftTitles: style.moneyAxis(step),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i != value || i < 0 || i >= points.length || i % labelEvery != 0) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(_axisLabel(points[i]), style: style.axis),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          getTouchedSpotIndicator: (bar, indexes) => [
            for (final _ in indexes)
              TouchedSpotIndicatorData(
                FlLine(color: style.scheme.outline, strokeWidth: 1, dashArray: const [4, 4]),
                FlDotData(
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(radius: 5, color: color, strokeWidth: 2, strokeColor: style.scheme.surface),
                ),
              ),
          ],
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => style.scheme.inverseSurface,
            tooltipBorderRadius: AppRadius.smAll,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            maxContentWidth: 160,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${points[s.x.toInt()].label}\n',
                  style.tooltip,
                  children: [
                    TextSpan(
                      text: Money.format(points[s.x.toInt()].revenue),
                      style: style.tooltip.copyWith(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: ' · ${points[s.x.toInt()].orders} đơn'),
                  ],
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (final (i, p) in points.indexed) FlSpot(i.toDouble(), p.revenue.toDouble())],
            color: color,
            barWidth: 2,
            isCurved: true,
            preventCurveOverShooting: true,
            dotData: FlDotData(show: points.length <= 12),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
              ),
            ),
          ),
        ],
      ),
      duration: AppDurations.normal,
    );
  }
}

/// Số đơn theo giờ (giờ VN). Chỉ vẽ khung giờ có đơn; cột cao điểm đậm, các cột khác nhạt hơn.
class HourlyBarChart extends StatelessWidget {
  const HourlyBarChart({super.key, required this.hourly, required this.peakHour});

  final List<HourlyStat> hourly;
  final int? peakHour;

  @override
  Widget build(BuildContext context) {
    final style = _ChartStyle(context);
    final active = hourly.where((h) => h.orders > 0).map((h) => h.hour);
    final first = active.reduce(math.min);
    final last = active.reduce(math.max);
    final window = hourly.where((h) => h.hour >= first && h.hour <= last).toList();
    final maxOrders = window.fold<int>(0, (m, h) => math.max(m, h.orders)).toDouble();
    final step = niceStep(maxOrders).ceilToDouble();
    final maxY = math.max(step, (maxOrders / step).ceil() * step);
    final labelEvery = window.length > 10 ? 2 : 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Bề rộng cột theo không gian thật: hẹp thì cột mảnh, rộng thì tối đa 20px.
        final barWidth = ((constraints.maxWidth - 44) / window.length * 0.6).clamp(4.0, 20.0);
        return BarChart(
          BarChartData(
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            gridData: style.horizontalGrid(step),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: _ChartStyle.none,
              rightTitles: _ChartStyle.none,
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  interval: step,
                  getTitlesWidget: (value, meta) => value == meta.max && value != 0
                      ? const SizedBox.shrink()
                      : SideTitleWidget(
                          meta: meta,
                          child: Text(value.toInt().toString(), style: style.axis),
                        ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final hour = value.toInt();
                    if ((hour - first) % labelEvery != 0) return const SizedBox.shrink();
                    return SideTitleWidget(
                      meta: meta,
                      child: Text('${hour}h', style: style.axis),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => style.scheme.inverseSurface,
                tooltipBorderRadius: AppRadius.smAll,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final h = window[groupIndex];
                  final hh = h.hour.toString().padLeft(2, '0');
                  return BarTooltipItem(
                    '$hh:00–$hh:59\n',
                    style.tooltip,
                    children: [
                      TextSpan(
                        text: '${h.orders} đơn',
                        style: style.tooltip.copyWith(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: ' · ${Money.compact(h.revenue)}'),
                    ],
                  );
                },
              ),
            ),
            barGroups: [
              for (final h in window)
                BarChartGroupData(
                  x: h.hour,
                  barRods: [
                    BarChartRodData(
                      toY: h.orders.toDouble(),
                      width: barWidth,
                      color: h.hour == peakHour ? style.scheme.primary : style.scheme.primary.withValues(alpha: 0.45),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ],
                ),
            ],
          ),
          duration: AppDurations.normal,
        );
      },
    );
  }
}

/// Một dòng "tên — thanh — số" (meter): so sánh các phần mà không cần biểu đồ tròn.
class MeterRow extends StatelessWidget {
  const MeterRow({
    super.key,
    required this.label,
    required this.value,
    required this.fraction,
    this.caption,
    this.leading,
    this.color,
  });

  final String label;

  /// Số liệu chính bên phải (VD: "35,7%").
  final String value;

  /// 0..1 — độ dài thanh.
  final double fraction;

  /// Dòng phụ dưới thanh (VD: "13,3tr · 357 phần").
  final String? caption;
  final Widget? leading;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = color ?? theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: AppSpacing.sm)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                ClipRRect(
                  borderRadius: AppRadius.smAll,
                  child: Container(
                    height: 8,
                    color: context.appColors.subtleBrand,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: fraction.clamp(0, 1),
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: barColor, borderRadius: AppRadius.smAll),
                      ),
                    ),
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(caption!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
