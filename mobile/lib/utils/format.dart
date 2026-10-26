import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api.dart';

String _currency = 'USD';
void setCurrency(String c) => _currency = c;

String money(num v) {
  final symbol = switch (_currency) { 'USD' => '\$', 'SOS' => 'Sh ', 'KES' => 'KSh ', 'ETB' => 'Br ', 'EUR' => '€', _ => '$_currency ' };
  return NumberFormat.currency(symbol: symbol, decimalDigits: _currency == 'SOS' ? 0 : 2).format(v);
}

String qty(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

String dateTime(DateTime d) => DateFormat('dd MMM, HH:mm').format(d);
String dateOnly(DateTime d) => DateFormat('dd MMM yyyy').format(d);

const paymentMethods = {
  'cash': 'Kaash',
  'evc_plus': 'EVC Plus',
  'zaad': 'Zaad',
  'sahal': 'Sahal',
  'edahab': 'e-Dahab',
  'bank': 'Bangi',
  'credit': 'Deyn',
};

const expenseCategories = {
  'rent': 'Kiro',
  'salary': 'Mushahar',
  'utilities': 'Koronto/Biyo',
  'transport': 'Gaadiid',
  'stock_purchase': 'Iibsi alaab',
  'marketing': 'Xayeysiis',
  'other': 'Kale',
};

const periods = {'today': 'Maanta', 'week': 'Toddobaad', 'month': 'Bil', 'year': 'Sannad'};

void showError(BuildContext context, Object e) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(e is ApiException ? e.message : 'Cillad: $e'),
    backgroundColor: Theme.of(context).colorScheme.error,
  ));
}

void showOk(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool> confirm(BuildContext context, String title, String body) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Maya')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Haa')),
      ],
    ),
  );
  return r ?? false;
}
