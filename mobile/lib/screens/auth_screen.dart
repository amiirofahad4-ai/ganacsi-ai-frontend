import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../services/auth_state.dart';
import '../services/mock_backend.dart';
import '../utils/format.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  bool _register = false;
  bool _busy = false;
  bool _hide = true;
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _business = TextEditingController();
  String _type = 'retail';
  String _currency = 'USD';

  static const _types = {
    'retail': 'Dukaan / tafaariiq',
    'wholesale': 'Jumlo',
    'restaurant': 'Maqaayad',
    'service': 'Adeeg (salon, garaash...)',
    'online': 'Online seller',
    'general': 'Kale',
  };

  @override
  void dispose() {
    for (final c in [_phone, _password, _name, _business]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final auth = context.read<AuthState>();
    try {
      if (_register) {
        await auth.register(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          password: _password.text,
          businessName: _business.text.trim(),
          businessType: _type,
          currency: _currency,
        );
      } else {
        await auth.login(_phone.text.trim(), _password.text);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Icon(Icons.auto_awesome, size: 56, color: cs.primary),
                  const SizedBox(height: 12),
                  Text('Ganacsi AI', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Kaaliyaha ganacsigaaga', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 32),
                  if (_register) ...[
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Magacaaga', prefixIcon: Icon(Icons.person_outline)),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Geli magacaaga' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _business,
                      decoration: const InputDecoration(labelText: 'Magaca ganacsiga', prefixIcon: Icon(Icons.store_outlined)),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Geli magaca ganacsiga' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField(
                      initialValue: _type,
                      decoration: const InputDecoration(labelText: 'Nooca ganacsiga', prefixIcon: Icon(Icons.category_outlined)),
                      items: _types.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) => setState(() => _type = v!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField(
                      initialValue: _currency,
                      decoration: const InputDecoration(labelText: 'Lacagta', prefixIcon: Icon(Icons.payments_outlined)),
                      items: const ['USD', 'SOS', 'KES', 'ETB', 'EUR']
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _currency = v!),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Lambarka telefoonka', prefixIcon: Icon(Icons.phone_outlined)),
                    validator: (v) => RegExp(r'^\+?\d{7,15}$').hasMatch((v ?? '').replaceAll(' ', '')) ? null : 'Lambar sax ah geli',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: _hide,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hide = !_hide)),
                    ),
                    validator: (v) => (v ?? '').length < 6 ? 'Ugu yaraan 6 xaraf' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _busy
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_register ? 'Is-diiwaangeli' : 'Soo gal'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _register = !_register),
                    child: Text(_register ? 'Akoon ma leedahay? Soo gal' : 'Akoon ma lihid? Is-diiwaangeli'),
                  ),
                  if (AppConfig.useMock) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          const Text('Demo mode', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          const Text(
                            'Xog tijaabo ah ayaa ku jirta. Telefoon: ${MockBackend.demoPhone} · Password: ${MockBackend.demoPassword}',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed: _busy
                                ? null
                                : () {
                                    setState(() => _register = false);
                                    _phone.text = MockBackend.demoPhone;
                                    _password.text = MockBackend.demoPassword;
                                    _submit();
                                  },
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Gal demo-ga'),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
