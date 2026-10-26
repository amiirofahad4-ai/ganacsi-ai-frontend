import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/auth_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

const _statusLabel = {'unpaid': 'Lama bixin', 'paid': 'La bixiyay', 'cancelled': 'La joojiyay'};

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});
  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  String? _status;
  Future<List<Invoice>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        _future = Api.instance
            .get('/api/invoices', {if (_status != null) 'status': _status})
            .then((l) => (l as List).map((e) => Invoice.fromJson(e)).toList());
      });

  Future<void> _new() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const InvoiceFormScreen()));
    if (ok == true) _load();
  }

  Future<void> _open(Invoice inv) async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoice: inv)));
    if (changed == true) _load();
  }

  Color _statusColor(BuildContext c, String s) => switch (s) {
        'paid' => Colors.green,
        'cancelled' => Theme.of(c).colorScheme.outline,
        _ => Colors.orange,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _new, icon: const Icon(Icons.add), label: const Text('Invoice')),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            for (final s in [null, 'unpaid', 'paid', 'cancelled'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(s == null ? 'Dhammaan' : _statusLabel[s]!),
                  selected: _status == s,
                  onSelected: (_) { _status = s; _load(); },
                ),
              ),
          ]),
        ),
        Expanded(
          child: AsyncView<List<Invoice>>(
            future: _future,
            onRetry: _load,
            builder: (list) {
              if (list.isEmpty) return EmptyState(icon: Icons.description_outlined, text: 'Invoice ma jiro', actionLabel: 'Invoice cusub', onAction: _new);
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                children: list
                    .map((inv) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onTap: () => _open(inv),
                            title: Text('${inv.number} · ${inv.customerName ?? 'Macmiil guud'}'),
                            subtitle: Text([dateOnly(inv.createdAt), if (inv.dueDate != null) 'waqti: ${inv.dueDate}'].join(' · ')),
                            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(money(inv.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(_statusLabel[inv.status] ?? inv.status, style: TextStyle(fontSize: 12, color: _statusColor(context, inv.status))),
                            ]),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _LineCtrl {
  final desc = TextEditingController();
  final qty = TextEditingController(text: '1');
  final price = TextEditingController();
  double get amount => (double.tryParse(qty.text) ?? 0) * (double.tryParse(price.text) ?? 0);
  void dispose() {
    desc.dispose();
    qty.dispose();
    price.dispose();
  }
}

class InvoiceFormScreen extends StatefulWidget {
  const InvoiceFormScreen({super.key});
  @override
  State<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends State<InvoiceFormScreen> {
  final _lines = [_LineCtrl()];
  final _note = TextEditingController();
  List<Customer> _customers = [];
  int? _customerId;
  DateTime? _due;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Api.instance.get('/api/customers').then((l) {
      if (mounted) setState(() => _customers = (l as List).map((e) => Customer.fromJson(e)).toList());
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  double get _total => _lines.fold(0, (s, l) => s + l.amount);

  Future<void> _save() async {
    final items = _lines
        .where((l) => l.desc.text.trim().isNotEmpty)
        .map((l) => {'description': l.desc.text.trim(), 'quantity': double.tryParse(l.qty.text) ?? 0, 'price': double.tryParse(l.price.text) ?? -1})
        .toList();
    if (items.isEmpty) {
      showError(context, 'Ugu yaraan hal shay ku dar');
      return;
    }
    if (items.any((i) => (i['quantity'] as double) <= 0 || (i['price'] as double) < 0)) {
      showError(context, 'Tirada iyo qiimaha si sax ah u geli');
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.instance.post('/api/invoices', {
        'items': items,
        if (_customerId != null) 'customer_id': _customerId,
        if (_due != null) 'due_date': _due!.toIso8601String().substring(0, 10),
        'note': _note.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice cusub')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<int?>(
          initialValue: _customerId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Macmiil'),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Macmiil guud')),
            ..._customers.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name))),
          ],
          onChanged: (v) => setState(() => _customerId = v),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text(_due == null ? 'Waqtiga bixinta (ikhtiyaari)' : 'Waqtiga: ${dateOnly(_due!)}'),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 7)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
            if (d != null) setState(() => _due = d);
          },
        ),
        const SectionTitle('Waxyaabaha'),
        for (var i = 0; i < _lines.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Row(children: [
                  Expanded(child: TextField(controller: _lines[i].desc, decoration: const InputDecoration(labelText: 'Sharaxaad', isDense: true))),
                  if (_lines.length > 1)
                    IconButton(
                      onPressed: () {
                        final removed = _lines.removeAt(i);
                        setState(() {});
                        WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
                      },
                      icon: const Icon(Icons.close),
                    ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: _lines[i].qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Tirada', isDense: true), onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _lines[i].price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Qiimaha', isDense: true), onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 8),
                  SizedBox(width: 80, child: Text(money(_lines[i].amount), textAlign: TextAlign.end)),
                ]),
              ]),
            ),
          ),
        TextButton.icon(onPressed: () => setState(() => _lines.add(_LineCtrl())), icon: const Icon(Icons.add), label: const Text('Shay kale')),
        const SizedBox(height: 8),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'Qoraal (ikhtiyaari)')),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text('Wadarta: ${money(_total)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Samee invoice')),
        ]),
      ]),
    );
  }
}

class InvoiceDetailScreen extends StatefulWidget {
  final Invoice invoice;
  const InvoiceDetailScreen({super.key, required this.invoice});
  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  late Invoice _inv = widget.invoice;
  bool _changed = false;

  Future<void> _setStatus(String s) async {
    try {
      final j = await Api.instance.put('/api/invoices/${_inv.id}/status', {'status': s});
      setState(() {
        _inv = Invoice.fromJson(j);
        _changed = true;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String _text(String business) {
    final b = StringBuffer('*$business — INVOICE ${_inv.number}*\n');
    b.writeln('Taariikh: ${dateOnly(_inv.createdAt)}');
    if (_inv.customerName != null) b.writeln('Macmiil: ${_inv.customerName}');
    if (_inv.dueDate != null) b.writeln('Waqtiga bixinta: ${_inv.dueDate}');
    b.writeln();
    for (final it in _inv.items) {
      b.writeln('${it.description} — ${qty(it.quantity)} × ${money(it.price)} = ${money(it.amount)}');
    }
    b.writeln('\n*Wadarta: ${money(_inv.total)}*');
    if (_inv.note != null && _inv.note!.isNotEmpty) b.writeln('\n${_inv.note}');
    b.writeln('\nMahadsanid!');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final business = context.read<AuthState>().user!.businessName;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_inv.number), actions: [
          IconButton(onPressed: () => Share.share(_text(business)), icon: const Icon(Icons.share_outlined), tooltip: 'U dir'),
        ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(business, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                Text('Invoice ${_inv.number} · ${dateOnly(_inv.createdAt)}'),
                if (_inv.customerName != null) Text('Macmiil: ${_inv.customerName}${_inv.customerPhone != null ? ' (${_inv.customerPhone})' : ''}'),
                if (_inv.dueDate != null) Text('Waqtiga bixinta: ${_inv.dueDate}'),
                const Divider(height: 24),
                ..._inv.items.map((it) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(child: Text('${it.description}\n${qty(it.quantity)} × ${money(it.price)}')),
                        Text(money(it.amount)),
                      ]),
                    )),
                const Divider(height: 24),
                Row(children: [
                  const Expanded(child: Text('Wadarta', style: TextStyle(fontWeight: FontWeight.w700))),
                  Text(money(_inv.total), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ]),
                if (_inv.note != null && _inv.note!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_inv.note!)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Text('Xaaladda: ${_statusLabel[_inv.status]}', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          if (_inv.status == 'unpaid') ...[
            FilledButton.icon(onPressed: () => _setStatus('paid'), icon: const Icon(Icons.check), label: const Text('Calaamadee "La bixiyay"')),
            TextButton(onPressed: () => _setStatus('cancelled'), child: const Text('Jooji invoice-ka')),
          ] else
            OutlinedButton(onPressed: () => _setStatus('unpaid'), child: const Text('Dib ugu celi "Lama bixin"')),
        ]),
      ),
    );
  }
}
