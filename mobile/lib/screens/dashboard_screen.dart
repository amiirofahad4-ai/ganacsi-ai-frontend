import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/auth_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'customers_screen.dart';
import 'invoices_screen.dart';

class DashboardData {
  final Summary summary;
  final List<DailyPoint> daily;
  final List<TopProduct> top;
  final List<Product> lowStock;
  final List<Insight> insights;
  DashboardData.fromJson(Map<String, dynamic> j)
      : summary = Summary.fromJson(j['summary']),
        daily = (j['daily'] as List).map((e) => DailyPoint.fromJson(e)).toList(),
        top = (j['top_products'] as List).map((e) => TopProduct.fromJson(e)).toList(),
        lowStock = (j['low_stock'] as List).map((e) => Product.fromJson(e)).toList(),
        insights = (j['insights'] as List).map((e) => Insight.fromJson(e)).toList();
}

class DashboardScreen extends StatefulWidget {
  final VoidCallback onOpenChat, onOpenSales, onOpenStock;
  const DashboardScreen({super.key, required this.onOpenChat, required this.onOpenSales, required this.onOpenStock});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _period = 'today';
  Future<DashboardData>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = Api.instance.get('/api/dashboard', {'period': _period}).then((j) => DashboardData.fromJson(j));
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthState>().user!;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user.businessName, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('Salaan, ${user.name.split(' ').first}', style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Cusboonaysii')],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onOpenChat,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Weydii Kaaliye'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _load();
          try {
            await _future;
          } catch (_) {}
        },
        child: AsyncView<DashboardData>(
          future: _future,
          onRetry: _load,
          builder: (d) => _body(context, d),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, DashboardData d) {
    final s = d.summary;
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Center(child: PeriodSelector(value: _period, onChanged: (p) { _period = p; _load(); })),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.6,
          children: [
            StatCard(label: 'Iibka (${s.salesCount})', value: money(s.revenue), icon: Icons.trending_up, onTap: widget.onOpenSales),
            StatCard(label: 'Faa\'iido saafi ah', value: money(s.netProfit), icon: Icons.savings_outlined, color: s.netProfit >= 0 ? Colors.green : cs.error),
            StatCard(label: 'Kharash', value: money(s.expenses), icon: Icons.receipt_long_outlined, color: Colors.orange),
            StatCard(
              label: 'Deyn (${s.customersWithDebt} macmiil)',
              value: money(s.customerDebtTotal),
              icon: Icons.account_balance_wallet_outlined,
              color: Colors.purple,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomersScreen(debtOnly: true))),
            ),
          ],
        ),
        if (d.insights.isNotEmpty) ...[
          const SectionTitle('Talooyin'),
          ...d.insights.map((i) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(_insightIcon(i.type), color: i.type == 'warning' ? cs.error : cs.primary),
                  title: Text(i.text),
                  onTap: () => _openInsight(i.type),
                ),
              )),
        ],
        const SectionTitle('Iibka 7-da maalmood'),
        Card(
          child: Padding(padding: const EdgeInsets.fromLTRB(8, 16, 8, 12), child: SalesBarChart(points: d.daily)),
        ),
        SectionTitle('Alaabta ugu iibka badan (bil)', trailing: TextButton(onPressed: widget.onOpenStock, child: const Text('Stock'))),
        if (d.top.isEmpty)
          const Card(child: ListTile(title: Text('Wali iib lama diiwaangelin')))
        else
          Card(
            child: Column(
              children: d.top.asMap().entries.map((e) {
                final p = e.value;
                return ListTile(
                  leading: CircleAvatar(radius: 14, child: Text('${e.key + 1}', style: const TextStyle(fontSize: 12))),
                  title: Text(p.name),
                  subtitle: Text('${qty(p.quantity)} la iibiyay · faa\'iido ${money(p.profit)}'),
                  trailing: Text(money(p.revenue), style: const TextStyle(fontWeight: FontWeight.w600)),
                );
              }).toList(),
            ),
          ),
        if (d.lowStock.isNotEmpty) ...[
          const SectionTitle('Stock dhammaanaya'),
          Card(
            child: Column(
              children: d.lowStock
                  .map((p) => ListTile(
                        leading: Icon(Icons.warning_amber_rounded, color: cs.error),
                        title: Text(p.name),
                        trailing: Text('${qty(p.quantity)} ${p.unit ?? ''}', style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
                        onTap: widget.onOpenStock,
                      ))
                  .toList(),
            ),
          ),
        ],
        const SectionTitle('Xaaladda guud'),
        Card(
          child: Column(children: [
            ListTile(leading: const Icon(Icons.inventory_2_outlined), title: const Text('Qiimaha stock-ga (cost)'), trailing: Text(money(s.stockValue))),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text('Invoices aan la bixin (${s.unpaidInvoicesCount})'),
              trailing: Text(money(s.unpaidInvoicesTotal)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InvoicesScreen())),
            ),
            ListTile(leading: const Icon(Icons.payments_outlined), title: const Text('Lacag la helay'), trailing: Text(money(s.cashReceived))),
          ]),
        ),
      ],
    );
  }

  IconData _insightIcon(String t) => switch (t) {
        'stock' => Icons.inventory_2_outlined,
        'debt' => Icons.account_balance_wallet_outlined,
        'invoice' => Icons.description_outlined,
        _ => Icons.lightbulb_outline,
      };

  void _openInsight(String t) {
    switch (t) {
      case 'stock':
        widget.onOpenStock();
      case 'debt':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomersScreen(debtOnly: true)));
      case 'invoice':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const InvoicesScreen()));
      default:
        widget.onOpenChat();
    }
  }
}
