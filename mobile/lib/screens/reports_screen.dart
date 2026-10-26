import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

class _ReportData {
  final Summary summary;
  final List<TopProduct> top;
  final List<Map<String, dynamic>> expenses;
  final List<DailyPoint> daily;
  _ReportData(this.summary, this.top, this.expenses, this.daily);
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _period = 'month';
  Future<_ReportData>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final q = {'period': _period};
    setState(() {
      _future = Future.wait([
        Api.instance.get('/api/reports/summary', q),
        Api.instance.get('/api/reports/top-products', {...q, 'limit': 10}),
        Api.instance.get('/api/reports/expenses-by-category', q),
        Api.instance.get('/api/reports/daily', {'days': 7}),
      ]).then((r) => _ReportData(
            Summary.fromJson(r[0]),
            (r[1] as List).map((e) => TopProduct.fromJson(e)).toList(),
            (r[2] as List).map((e) => Map<String, dynamic>.from(e)).toList(),
            (r[3] as List).map((e) => DailyPoint.fromJson(e)).toList(),
          ));
    });
  }

  Widget _row(String a, String b, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null))),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Warbixinno')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: PeriodSelector(value: _period, onChanged: (p) { _period = p; _load(); })),
        Expanded(
          child: AsyncView<_ReportData>(
            future: _future,
            onRetry: _load,
            builder: (d) {
              final s = d.summary;
              final cs = Theme.of(context).colorScheme;
              final margin = s.revenue == 0 ? 0 : (s.grossProfit / s.revenue * 100);
              return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
                const SectionTitle('Faa\'iido & Khasaare'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      _row('Dakhliga (${s.salesCount} iib)', money(s.revenue)),
                      _row('Qiimaha alaabta (COGS)', '− ${money(s.revenue - s.grossProfit)}'),
                      const Divider(),
                      _row('Faa\'iido guud (${margin.toStringAsFixed(1)}%)', money(s.grossProfit), bold: true),
                      _row('Kharashka', '− ${money(s.expenses)}'),
                      const Divider(),
                      _row('Faa\'iido saafi ah', money(s.netProfit), bold: true, color: s.netProfit >= 0 ? Colors.green : cs.error),
                    ]),
                  ),
                ),
                const SectionTitle('7-da maalmood'),
                Card(child: Padding(padding: const EdgeInsets.fromLTRB(8, 16, 8, 12), child: SalesBarChart(points: d.daily))),
                const SectionTitle('Alaabta ugu fiican'),
                Card(
                  child: d.top.isEmpty
                      ? const ListTile(title: Text('Xog ma jirto'))
                      : Column(
                          children: d.top
                              .map((p) => ListTile(
                                    dense: true,
                                    title: Text(p.name),
                                    subtitle: Text('${qty(p.quantity)} · faa\'iido ${money(p.profit)}'),
                                    trailing: Text(money(p.revenue)),
                                  ))
                              .toList(),
                        ),
                ),
                const SectionTitle('Kharashka nooc ahaan'),
                Card(
                  child: d.expenses.isEmpty
                      ? const ListTile(title: Text('Xog ma jirto'))
                      : Column(
                          children: d.expenses
                              .map((e) => ListTile(
                                    dense: true,
                                    title: Text(expenseCategories[e['category']] ?? '${e['category']}'),
                                    subtitle: Text('${e['count']} jeer'),
                                    trailing: Text(money((e['total'] as num).toDouble())),
                                  ))
                              .toList(),
                        ),
                ),
                const SectionTitle('Xaaladda hadda'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      _row('Deynta macaamiisha (${s.customersWithDebt})', money(s.customerDebtTotal)),
                      _row('Invoices aan la bixin (${s.unpaidInvoicesCount})', money(s.unpaidInvoicesTotal)),
                      _row('Qiimaha stock-ga', money(s.stockValue)),
                      _row('Alaab dhammaanaysa', '${s.lowStockCount}'),
                    ]),
                  ),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
