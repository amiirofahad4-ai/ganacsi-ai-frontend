import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../services/auth_state.dart';
import '../services/mock_backend.dart';
import '../utils/format.dart';
import 'customers_screen.dart';
import 'expenses_screen.dart';
import 'invoices_screen.dart';
import 'reports_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  void _push(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute(builder: (_) => w));

  Future<void> _editProfile(BuildContext context) async {
    final auth = context.read<AuthState>();
    final u = auth.user!;
    final name = TextEditingController(text: u.name);
    final business = TextEditingController(text: u.businessName);
    var currency = u.currency;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Profile-ka'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Magacaaga')),
            const SizedBox(height: 10),
            TextField(controller: business, decoration: const InputDecoration(labelText: 'Magaca ganacsiga')),
            const SizedBox(height: 10),
            DropdownButtonFormField(
              initialValue: currency,
              decoration: const InputDecoration(labelText: 'Lacagta'),
              items: const ['USD', 'SOS', 'KES', 'ETB', 'EUR'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => set(() => currency = v!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Jooji')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Keydi')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await auth.updateProfile({'name': name.text.trim(), 'business_name': business.text.trim(), 'currency': currency});
      setCurrency(currency);
      if (context.mounted) showOk(context, 'Waa la keydiyay');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final u = auth.user!;
    return Scaffold(
      appBar: AppBar(title: const Text('Wax kale')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: ListTile(
            leading: CircleAvatar(child: Text(u.businessName.isEmpty ? '?' : u.businessName[0].toUpperCase())),
            title: Text(u.businessName),
            subtitle: Text('${u.name} · ${u.phone}'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editProfile(context),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            ListTile(leading: const Icon(Icons.people_outline), title: const Text('Macaamiisha'), trailing: const Icon(Icons.chevron_right), onTap: () => _push(context, const CustomersScreen())),
            ListTile(leading: const Icon(Icons.account_balance_wallet_outlined), title: const Text('Deynta'), trailing: const Icon(Icons.chevron_right), onTap: () => _push(context, const CustomersScreen(debtOnly: true))),
            ListTile(leading: const Icon(Icons.receipt_long_outlined), title: const Text('Kharashka'), trailing: const Icon(Icons.chevron_right), onTap: () => _push(context, const ExpensesScreen())),
            ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Invoices'), trailing: const Icon(Icons.chevron_right), onTap: () => _push(context, const InvoicesScreen())),
            ListTile(leading: const Icon(Icons.bar_chart_outlined), title: const Text('Warbixinno'), trailing: const Icon(Icons.chevron_right), onTap: () => _push(context, const ReportsScreen())),
          ]),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            if (AppConfig.useMock) ...[
              const ListTile(
                leading: Icon(Icons.science_outlined),
                title: Text('Demo mode'),
                subtitle: Text('Xogtu waxay ku kaydsan tahay telefoonkan oo keliya'),
              ),
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('Dib u deji xogta tijaabada'),
                onTap: () async {
                  if (!await confirm(context, 'Dib u deji?', 'Wixii aad ku dartay waa la tirtiri doonaa, xogta tijaabada ayaana dib loo soo celin doonaa.')) return;
                  await MockBackend.instance.reset();
                  if (context.mounted) showOk(context, 'Xogta tijaabada dib ayaa loo celiyay');
                  if (u.phone != MockBackend.demoPhone) auth.logout();
                },
              ),
            ] else
              const ListTile(leading: Icon(Icons.dns_outlined), title: Text('Server'), subtitle: Text(AppConfig.apiUrl)),
            ListTile(
              leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
              title: Text('Ka bax', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () async {
                if (await confirm(context, 'Ka bax?', 'Mar kale ayaad soo geli kartaa.')) auth.logout();
              },
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Center(child: Text('Ganacsi AI v1.0', style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}
