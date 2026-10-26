import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String _period = 'month';
  Future<List<Expense>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        _future = Api.instance
            .get('/api/expenses', {'period': _period})
            .then((l) => (l as List).map((e) => Expense.fromJson(e)).toList());
      });

  Future<void> _add() async {
    final amount = TextEditingController();
    final note = TextEditingController();
    var category = 'other';
    var date = DateTime.now();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Kharash cusub', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Xaddiga', prefixIcon: Icon(Icons.payments_outlined)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: expenseCategories.entries
                  .map((e) => ChoiceChip(label: Text(e.value), selected: category == e.key, onSelected: (_) => set(() => category = e.key)))
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Qoraal (ikhtiyaari)')),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(dateOnly(date)),
              trailing: const Text('Beddel'),
              onTap: () async {
                final d = await showDatePicker(context: c, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (d != null) set(() => date = d);
              },
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Keydi')),
          ]),
        ),
      ),
    );
    final a = double.tryParse(amount.text.trim());
    final n = note.text.trim();
    if (ok != true) return;
    if (a == null || a <= 0) {
      if (mounted) showError(context, 'Xaddi sax ah geli');
      return;
    }
    try {
      final d = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      await Api.instance.post('/api/expenses', {'category': category, 'amount': a, 'note': n, 'date': d});
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(Expense e) async {
    if (!await confirm(context, 'Tirtir kharashka?', '${expenseCategories[e.category] ?? e.category} · ${money(e.amount)}')) return;
    try {
      await Api.instance.delete('/api/expenses/${e.id}');
      _load();
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  IconData _icon(String c) => switch (c) {
        'rent' => Icons.home_work_outlined,
        'salary' => Icons.badge_outlined,
        'utilities' => Icons.bolt_outlined,
        'transport' => Icons.local_shipping_outlined,
        'stock_purchase' => Icons.shopping_cart_outlined,
        'marketing' => Icons.campaign_outlined,
        _ => Icons.receipt_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kharashka')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Kharash')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: PeriodSelector(value: _period, onChanged: (p) { _period = p; _load(); })),
        Expanded(
          child: AsyncView<List<Expense>>(
            future: _future,
            onRetry: _load,
            builder: (list) {
              if (list.isEmpty) return EmptyState(icon: Icons.receipt_long_outlined, text: 'Muddadan kharash ma jiro', actionLabel: 'Kharash', onAction: _add);
              final total = list.fold<double>(0, (s, e) => s + e.amount);
              final byCat = <String, double>{};
              for (final e in list) {
                byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
              }
              final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
              final cs = Theme.of(context).colorScheme;
              return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 96), children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Wadarta', style: Theme.of(context).textTheme.labelMedium),
                      Text(money(total), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      ...cats.map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(expenseCategories[e.key] ?? e.key)),
                                Text(money(e.value)),
                              ]),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(value: e.value / total, minHeight: 6, backgroundColor: cs.surfaceContainerHighest),
                              ),
                            ]),
                          )),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                ...list.map((e) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(_icon(e.category), size: 20)),
                        title: Text(expenseCategories[e.category] ?? e.category),
                        subtitle: Text([e.date, if (e.note != null && e.note!.isNotEmpty) e.note!].join(' · ')),
                        trailing: Text(money(e.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                        onLongPress: () => _delete(e),
                      ),
                    )),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
