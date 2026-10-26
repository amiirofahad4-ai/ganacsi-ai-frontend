import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/auth_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'new_sale_screen.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  String _period = 'today';
  Future<List<Sale>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        _future = Api.instance
            .get('/api/sales', {'period': _period})
            .then((l) => (l as List).map((e) => Sale.fromJson(e)).toList());
      });

  Future<void> _newSale() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const NewSaleScreen()));
    if (ok == true) _load();
  }

  Future<void> _openSale(Sale s) async {
    Sale full;
    try {
      full = Sale.fromJson(await Api.instance.get('/api/sales/${s.id}'));
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    final business = context.read<AuthState>().user!.businessName;
    final deleted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Iib #${full.id}', style: Theme.of(c).textTheme.titleLarge),
            Text('${dateTime(full.createdAt)} · ${paymentMethods[full.paymentMethod] ?? full.paymentMethod}${full.customerName != null ? ' · ${full.customerName}' : ''}'),
            const Divider(height: 24),
            ...full.items.map((it) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(child: Text('${it.name}  ×${qty(it.quantity)}')),
                    Text(money(it.quantity * it.price)),
                  ]),
                )),
            const Divider(height: 24),
            _row(c, 'Wadarta', money(full.total), bold: true),
            _row(c, 'La bixiyay', money(full.paid)),
            if (full.due > 0) _row(c, 'Deyn', money(full.due), color: Theme.of(c).colorScheme.error),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Rasiid u dir'),
                  onPressed: () => Share.share(_receiptText(business, full)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Tirtir'),
                  style: TextButton.styleFrom(foregroundColor: Theme.of(c).colorScheme.error),
                  onPressed: () async {
                    if (!await confirm(c, 'Tirtir iibka?', 'Stock-ga iyo deynta dib ayaa loo celin doonaa.')) return;
                    try {
                      await Api.instance.delete('/api/sales/${full.id}');
                      if (c.mounted) Navigator.pop(c, true);
                    } catch (e) {
                      if (c.mounted) showError(c, e);
                    }
                  },
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (deleted == true) _load();
  }

  Widget _row(BuildContext c, String a, String b, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null))),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null, color: color)),
        ]),
      );

  String _receiptText(String business, Sale s) {
    final b = StringBuffer('*$business*\nRasiid #${s.id} — ${dateTime(s.createdAt)}\n\n');
    for (final it in s.items) {
      b.writeln('${it.name} ×${qty(it.quantity)} = ${money(it.quantity * it.price)}');
    }
    b.writeln('\nWadarta: ${money(s.total)}');
    b.writeln('La bixiyay: ${money(s.paid)}');
    if (s.due > 0) b.writeln('Deyn: ${money(s.due)}');
    b.writeln('\nMahadsanid!');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Iibka')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _newSale, icon: const Icon(Icons.add), label: const Text('Iib cusub')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: PeriodSelector(value: _period, onChanged: (p) { _period = p; _load(); })),
        Expanded(
          child: AsyncView<List<Sale>>(
            future: _future,
            onRetry: _load,
            builder: (sales) {
              if (sales.isEmpty) {
                return EmptyState(icon: Icons.point_of_sale_outlined, text: 'Muddadan iib lama diiwaangelin', actionLabel: 'Iib cusub', onAction: _newSale);
              }
              final total = sales.fold<double>(0, (s, e) => s + e.total);
              return RefreshIndicator(
                onRefresh: () async => _load(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                  children: [
                    Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: ListTile(
                        title: Text('${sales.length} iib'),
                        trailing: Text(money(total), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...sales.map((s) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onTap: () => _openSale(s),
                            leading: CircleAvatar(child: Icon(s.due > 0 ? Icons.schedule : Icons.check, size: 18)),
                            title: Text(s.customerName ?? 'Macmiil guud'),
                            subtitle: Text('${dateTime(s.createdAt)} · ${s.itemCount} shay · ${paymentMethods[s.paymentMethod] ?? s.paymentMethod}'),
                            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(money(s.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (s.due > 0) Text('deyn ${money(s.due)}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error)),
                            ]),
                          ),
                        )),
                  ],
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
