import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/auth_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

class CustomersScreen extends StatefulWidget {
  final bool debtOnly;
  const CustomersScreen({super.key, this.debtOnly = false});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  Future<List<Customer>>? _future;
  late bool _debtOnly = widget.debtOnly;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        _future = Api.instance
            .get('/api/customers', {if (_debtOnly) 'with_debt': 'true'})
            .then((l) => (l as List).map((e) => Customer.fromJson(e)).toList());
      });

  Future<void> _addOrEdit([Customer? c]) async {
    final name = TextEditingController(text: c?.name);
    final phone = TextEditingController(text: c?.phone);
    final notes = TextEditingController(text: c?.notes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(c == null ? 'Macmiil cusub' : 'Wax ka beddel'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Magaca')),
          const SizedBox(height: 10),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefoon')),
          const SizedBox(height: 10),
          TextField(controller: notes, decoration: const InputDecoration(labelText: 'Qoraal (ikhtiyaari)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Jooji')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Keydi')),
        ],
      ),
    );
    final body = {'name': name.text.trim(), 'phone': phone.text.trim(), 'notes': notes.text.trim()};
    if (ok != true) return;
    try {
      if (c == null) {
        await Api.instance.post('/api/customers', body);
      } else {
        await Api.instance.put('/api/customers/${c.id}', body);
      }
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _open(Customer c) async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c.id)));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_debtOnly ? 'Deynta macaamiisha' : 'Macaamiisha')),
      floatingActionButton: FloatingActionButton(onPressed: () => _addOrEdit(), child: const Icon(Icons.person_add_alt)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Raadi magac ama telefoon', isDense: true),
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(label: const Text('Deyn'), selected: _debtOnly, onSelected: (v) { _debtOnly = v; _load(); }),
          ]),
        ),
        Expanded(
          child: AsyncView<List<Customer>>(
            future: _future,
            onRetry: _load,
            builder: (all) {
              final list = all.where((c) => _query.isEmpty || c.name.toLowerCase().contains(_query) || (c.phone ?? '').contains(_query)).toList();
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.people_outline,
                  text: _debtOnly ? 'Cidna deyn kuguma leh 👍' : 'Wali macmiil lama darin',
                  actionLabel: _debtOnly ? null : 'Macmiil cusub',
                  onAction: () => _addOrEdit(),
                );
              }
              final totalDebt = list.fold<double>(0, (s, c) => s + c.balance);
              return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
                if (totalDebt > 0)
                  Card(
                    color: cs.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.account_balance_wallet_outlined),
                      title: const Text('Wadarta deynta'),
                      trailing: Text(money(totalDebt), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ...list.map((c) => Card(
                      margin: const EdgeInsets.only(top: 8),
                      child: ListTile(
                        onTap: () => _open(c),
                        onLongPress: () => _addOrEdit(c),
                        leading: CircleAvatar(child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase())),
                        title: Text(c.name),
                        subtitle: c.phone == null || c.phone!.isEmpty ? null : Text(c.phone!),
                        trailing: c.balance > 0
                            ? Text(money(c.balance), style: TextStyle(color: cs.error, fontWeight: FontWeight.w700))
                            : const Icon(Icons.chevron_right),
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

class CustomerDetailScreen extends StatefulWidget {
  final int customerId;
  const CustomerDetailScreen({super.key, required this.customerId});
  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  Future<Map<String, dynamic>>? _future;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        _future = Api.instance.get('/api/customers/${widget.customerId}').then((j) => Map<String, dynamic>.from(j));
      });

  Future<void> _pay(Customer c) async {
    final ctrl = TextEditingController(text: qty(c.balance));
    final amount = await showDialog<double>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Lacag deyn ah ayuu bixiyay'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Xaddiga', helperText: 'Deynta: ${money(c.balance)}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Jooji')),
          FilledButton(onPressed: () => Navigator.pop(d, double.tryParse(ctrl.text.trim())), child: const Text('Keydi')),
        ],
      ),
    );
    if (amount == null || amount <= 0) return;
    try {
      await Api.instance.post('/api/customers/${c.id}/payments', {'amount': amount});
      _changed = true;
      if (mounted) showOk(context, 'Lacag-bixinta waa la diiwaangeliyay');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _remind(Customer c) {
    final business = context.read<AuthState>().user!.businessName;
    Share.share('Asc ${c.name}, waxaan kuu xasuusinaynaa in deyn dhan ${money(c.balance)} lagugu leeyahay $business. '
        'Fadlan nala soo xiriir markaad diyaar tahay. Mahadsanid!');
  }

  Future<void> _delete(Customer c) async {
    if (!await confirm(context, 'Tirtir macmiilka?', c.name)) return;
    try {
      await Api.instance.delete('/api/customers/${c.id}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Macmiil')),
        body: AsyncView<Map<String, dynamic>>(
          future: _future,
          onRetry: _load,
          builder: (j) {
            final c = Customer.fromJson(j);
            final sales = ((j['sales'] as List?) ?? []).map((e) => Sale.fromJson(e)).toList();
            final cs = Theme.of(context).colorScheme;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Center(child: CircleAvatar(radius: 32, child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase(), style: const TextStyle(fontSize: 24)))),
              const SizedBox(height: 10),
              Text(c.name, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              if (c.phone != null && c.phone!.isNotEmpty) Text(c.phone!, textAlign: TextAlign.center),
              if (c.notes != null && c.notes!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c.notes!, textAlign: TextAlign.center)),
              const SizedBox(height: 16),
              Card(
                color: c.balance > 0 ? cs.errorContainer : cs.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    const Text('Deynta'),
                    Text(money(c.balance), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (c.balance > 0) ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: FilledButton.icon(onPressed: () => _pay(c), icon: const Icon(Icons.payments_outlined), label: const Text('Wuu bixiyay'))),
                        const SizedBox(width: 8),
                        Expanded(child: OutlinedButton.icon(onPressed: () => _remind(c), icon: const Icon(Icons.send_outlined), label: const Text('Xasuusi'))),
                      ]),
                    ],
                  ]),
                ),
              ),
              const SectionTitle('Iibkii u dambeeyay'),
              if (sales.isEmpty)
                const Card(child: ListTile(title: Text('Wali iib ma jiro')))
              else
                Card(
                  child: Column(
                    children: sales
                        .map((s) => ListTile(
                              title: Text(money(s.total)),
                              subtitle: Text(dateTime(s.createdAt)),
                              trailing: s.due > 0 ? Text('deyn ${money(s.due)}', style: TextStyle(color: cs.error)) : const Icon(Icons.check, color: Colors.green),
                            ))
                        .toList(),
                  ),
                ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () => _delete(c),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Tirtir macmiilka'),
                style: TextButton.styleFrom(foregroundColor: cs.error),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
