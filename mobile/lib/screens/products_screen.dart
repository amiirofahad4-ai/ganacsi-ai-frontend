import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  Future<List<Product>>? _future;
  String _query = '';
  bool _lowOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        _future = Api.instance
            .get('/api/products', {if (_lowOnly) 'low_stock': 'true'})
            .then((l) => (l as List).map((e) => Product.fromJson(e)).toList());
      });

  Future<void> _edit([Product? p]) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ProductFormScreen(product: p)));
    if (ok == true) _load();
  }

  Future<void> _adjust(Product p) async {
    final ctrl = TextEditingController();
    final change = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(p.name),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Stock-ga hadda: ${qty(p.quantity)} ${p.unit ?? ''}'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Tirada', helperText: '+ = la keenay   − = lumay / jabay'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Jooji')),
          FilledButton.tonal(onPressed: () => Navigator.pop(c, -(double.tryParse(ctrl.text) ?? 0).abs()), child: const Text('− Ka jar')),
          FilledButton(onPressed: () => Navigator.pop(c, (double.tryParse(ctrl.text) ?? 0).abs()), child: const Text('+ Ku dar')),
        ],
      ),
    );
    if (change == null || change == 0) return;
    try {
      await Api.instance.post('/api/products/${p.id}/stock', {'change': change});
      if (mounted) showOk(context, 'Stock-ga waa la cusboonaysiiyay');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Stock-ga')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Alaab cusub')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Raadi...', isDense: true),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Dhammaanaya'),
              selected: _lowOnly,
              onSelected: (v) { _lowOnly = v; _load(); },
            ),
          ]),
        ),
        Expanded(
          child: AsyncView<List<Product>>(
            future: _future,
            onRetry: _load,
            builder: (all) {
              final q = _query.toLowerCase();
              final list = all.where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || (p.category ?? '').toLowerCase().contains(q)).toList();
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.inventory_2_outlined,
                  text: _lowOnly ? 'Alaab dhammaanaysa ma jirto 👍' : 'Wali alaab lama darin',
                  actionLabel: _lowOnly ? null : 'Alaab cusub',
                  onAction: () => _edit(),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _load(),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  itemCount: list.length,
                  itemBuilder: (c, i) {
                    final p = list[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => _edit(p),
                        title: Text(p.name),
                        subtitle: Text([money(p.price), if (p.category != null) p.category!].join(' · ')),
                        trailing: InkWell(
                          onTap: () => _adjust(p),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: (p.isLow ? cs.error : cs.primary).withAlpha(28),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('${qty(p.quantity)} ${p.unit ?? ''}',
                                style: TextStyle(fontWeight: FontWeight.w700, color: p.isLow ? cs.error : cs.primary)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class ProductFormScreen extends StatefulWidget {
  final Product? product;
  const ProductFormScreen({super.key, this.product});
  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name);
  late final _category = TextEditingController(text: widget.product?.category);
  late final _price = TextEditingController(text: widget.product == null ? '' : qty(widget.product!.price));
  late final _cost = TextEditingController(text: widget.product == null ? '' : qty(widget.product!.cost));
  late final _quantity = TextEditingController(text: widget.product == null ? '' : qty(widget.product!.quantity));
  late final _low = TextEditingController(text: widget.product == null ? '5' : qty(widget.product!.lowStockThreshold));
  late final _unit = TextEditingController(text: widget.product?.unit ?? 'pcs');
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _category, _price, _cost, _quantity, _low, _unit]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _numV(String? v, {bool required = true}) {
    if ((v ?? '').trim().isEmpty) return required ? 'Waa loo baahan yahay' : null;
    final n = double.tryParse(v!.trim());
    return n == null || n < 0 ? 'Tiro sax ah geli' : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final body = {
      'name': _name.text.trim(),
      'category': _category.text.trim(),
      'price': double.parse(_price.text.trim()),
      'cost': double.tryParse(_cost.text.trim()) ?? 0,
      if (widget.product == null) 'quantity': double.tryParse(_quantity.text.trim()) ?? 0,
      'low_stock_threshold': double.tryParse(_low.text.trim()) ?? 5,
      'unit': _unit.text.trim(),
    };
    try {
      if (widget.product == null) {
        await Api.instance.post('/api/products', body);
      } else {
        await Api.instance.put('/api/products/${widget.product!.id}', body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Tirtir alaabta?', widget.product!.name)) return;
    try {
      await Api.instance.delete('/api/products/${widget.product!.id}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final margin = (double.tryParse(_price.text) ?? 0) - (double.tryParse(_cost.text) ?? 0);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product == null ? 'Alaab cusub' : 'Wax ka beddel'),
        actions: [if (widget.product != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline))],
      ),
      body: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Magaca alaabta'), validator: (v) => (v ?? '').trim().isEmpty ? 'Waa loo baahan yahay' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _category, decoration: const InputDecoration(labelText: 'Category (tusaale: Cunto)')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Qiimaha iibka'), validator: _numV)),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Qiimaha iibsiga (cost)'), validator: (v) => _numV(v, required: false))),
          ]),
          if (margin != 0)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text('Faa\'iido shay kasta: ${money(margin)}', style: TextStyle(color: margin > 0 ? Colors.green : Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _quantity,
                enabled: widget.product == null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Tirada stock-ga', helperText: widget.product != null ? 'Ku beddel liiska (taabo tirada)' : null),
                validator: (v) => _numV(v, required: false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _unit, decoration: const InputDecoration(labelText: 'Unit (pcs, kg, bag)'))),
          ]),
          const SizedBox(height: 12),
          TextFormField(controller: _low, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Digniin marka stock-gu gaaro'), validator: (v) => _numV(v, required: false)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Keydi'),
          ),
        ]),
      ),
    );
  }
}
