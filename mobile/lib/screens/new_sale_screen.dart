import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

class _CartLine {
  final Product product;
  double quantity;
  _CartLine(this.product, this.quantity);
  double get total => product.price * quantity;
}

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});
  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  Future<List<dynamic>>? _future;
  final Map<int, _CartLine> _cart = {};
  String _query = '';
  Customer? _customer;
  String _method = 'cash';
  final _paid = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  void _load() => setState(() {
        _future = Future.wait([
          Api.instance.get('/api/products').then((l) => (l as List).map((e) => Product.fromJson(e)).toList()),
          Api.instance.get('/api/customers').then((l) => (l as List).map((e) => Customer.fromJson(e)).toList()),
        ]);
      });

  double get _total => _cart.values.fold(0, (s, l) => s + l.total);

  void _add(Product p) {
    final line = _cart[p.id];
    final current = line?.quantity ?? 0;
    if (current + 1 > p.quantity) {
      showError(context, 'Stock kuma filna: ${p.name} (${qty(p.quantity)})');
      return;
    }
    setState(() => _cart[p.id] = _CartLine(p, current + 1));
  }

  void _remove(Product p) {
    final line = _cart[p.id];
    if (line == null) return;
    setState(() {
      if (line.quantity <= 1) {
        _cart.remove(p.id);
      } else {
        line.quantity -= 1;
      }
    });
  }

  Future<void> _submit() async {
    if (_cart.isEmpty) return;
    final paidText = _paid.text.trim();
    final paid = paidText.isEmpty ? _total : double.tryParse(paidText);
    if (paid == null || paid < 0 || paid > _total + 0.0001) {
      showError(context, 'Lacagta la bixiyay sax ma aha');
      return;
    }
    if (paid < _total && _customer == null) {
      showError(context, 'Iib deyn ah: dooro macmiilka');
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.instance.post('/api/sales', {
        'items': _cart.values.map((l) => {'product_id': l.product.id, 'quantity': l.quantity}).toList(),
        if (_customer != null) 'customer_id': _customer!.id,
        'paid': paid,
        'payment_method': paid < _total && paid == 0 ? 'credit' : _method,
      });
      if (!mounted) return;
      showOk(context, 'Iibka waa la keydiyay ✓');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Iib cusub')),
      body: AsyncView<List<dynamic>>(
        future: _future,
        onRetry: _load,
        builder: (data) {
          final products = (data[0] as List<Product>)
              .where((p) => _query.isEmpty || p.name.toLowerCase().contains(_query.toLowerCase()))
              .toList();
          final customers = data[1] as List<Customer>;
          if ((data[0] as List).isEmpty) {
            return const EmptyState(icon: Icons.inventory_2_outlined, text: 'Marka hore alaab ku dar qaybta Stock');
          }
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Raadi alaab...', isDense: true),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: products.length,
                itemBuilder: (c, i) {
                  final p = products[i];
                  final inCart = _cart[p.id]?.quantity ?? 0;
                  return ListTile(
                    title: Text(p.name),
                    subtitle: Text('${money(p.price)} · stock ${qty(p.quantity)}'),
                    onTap: p.quantity > 0 ? () => _add(p) : null,
                    enabled: p.quantity > 0,
                    trailing: inCart == 0
                        ? IconButton.filledTonal(onPressed: p.quantity > 0 ? () => _add(p) : null, icon: const Icon(Icons.add))
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(onPressed: () => _remove(p), icon: const Icon(Icons.remove_circle_outline)),
                            Text(qty(inCart), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            IconButton(onPressed: () => _add(p), icon: const Icon(Icons.add_circle_outline)),
                          ]),
                  );
                },
              ),
            ),
            if (_cart.isNotEmpty) _checkout(context, customers),
          ]);
        },
      ),
    );
  }

  Widget _checkout(BuildContext context, List<Customer> customers) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: cs.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: _customer?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Macmiil (ikhtiyaari)', isDense: true),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Macmiil guud')),
                    ...customers.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (id) => setState(() => _customer = id == null ? null : customers.firstWhere((c) => c.id == id)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _method,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Habka lacagta', isDense: true),
                  items: paymentMethods.entries.where((e) => e.key != 'credit').map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (v) => setState(() => _method = v!),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _paid,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'La bixiyay (ka tag = dhammaan)',
                helperText: _customer != null ? 'Haddii ka yar wadarta, inta harta waa deyn' : null,
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_cart.length} shay', style: Theme.of(context).textTheme.bodySmall),
                  Text(money(_total), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                ]),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                label: const Text('Keydi iibka'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
