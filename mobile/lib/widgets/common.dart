import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../utils/format.dart';

/// Wuxuu muujiyaa loading / error (oo leh "Isku day mar kale") / xogta.
class AsyncView<T> extends StatelessWidget {
  final Future<T>? future;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;
  const AsyncView({super.key, required this.future, required this.builder, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) {
          final e = snap.error;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 12),
                Text(e is ApiException ? e.message : '$e', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.tonal(onPressed: onRetry, child: const Text('Isku day mar kale')),
              ]),
            ),
          );
        }
        return builder(snap.data as T);
      },
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({super.key, required this.icon, required this.text, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onAction, icon: const Icon(Icons.add), label: Text(actionLabel!)),
          ],
        ]),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;
  const StatCard({super.key, required this.label, required this.value, required this.icon, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: c.withAlpha(30), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 18, color: c),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: Theme.of(context).textTheme.labelMedium, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Bar chart fudud: iibka 7-da maalmood (package dibadda looma baahna).
class SalesBarChart extends StatelessWidget {
  final List<DailyPoint> points;
  const SalesBarChart({super.key, required this.points});

  static const _days = ['Isn', 'Tal', 'Arb', 'Kha', 'Jim', 'Sab', 'Axd'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxV = points.fold<double>(0, (m, p) => p.revenue > m ? p.revenue : m);
    return SizedBox(
      height: 170,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: points.map((p) {
          final h = maxV == 0 ? 0.0 : (p.revenue / maxV);
          final day = DateTime.parse(p.day);
          return Expanded(
            child: Tooltip(
              message: '${p.day}\n${money(p.revenue)}',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (p.revenue > 0)
                    FittedBox(child: Text(_short(p.revenue), style: Theme.of(context).textTheme.labelSmall)),
                  const SizedBox(height: 4),
                  Container(
                    height: 4 + 116 * h,
                    decoration: BoxDecoration(
                      color: p.revenue > 0 ? cs.primary : cs.surfaceContainerHighest,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_days[day.weekday - 1], style: Theme.of(context).textTheme.labelSmall),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _short(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0);
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
          if (trailing != null) trailing!,
        ]),
      );
}

class PeriodSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const PeriodSelector({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: periods.entries.map((e) => ButtonSegment(value: e.key, label: Text(e.value))).toList(),
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      );
}
