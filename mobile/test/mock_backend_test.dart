import 'package:flutter_test/flutter_test.dart';
import 'package:ganacsi_ai/services/api.dart';
import 'package:ganacsi_ai/services/mock_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late String token;
  final mock = MockBackend.instance;

  Future<dynamic> call(String method, String path, {Map<String, String> query = const {}, Object? body}) =>
      mock.handle(method, path, query, body, token);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await mock.reset();
    final res = await mock.handle('POST', '/api/auth/login',
        const {}, {'phone': MockBackend.demoPhone, 'password': MockBackend.demoPassword}, null);
    token = res['token'] as String;
  });

  test('login khaldan waa la diidaa', () async {
    expect(
      () => mock.handle('POST', '/api/auth/login', const {}, {'phone': MockBackend.demoPhone, 'password': 'xxx'}, null),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
    );
  });

  test('xogta tijaabada waa diyaar', () async {
    final products = await call('GET', '/api/products') as List;
    expect(products.length, 8);
    final dash = await call('GET', '/api/dashboard', query: {'period': 'week'});
    expect((dash['daily'] as List).length, 7);
    expect(dash['summary']['sales_count'], greaterThan(0));
  });

  test('iib deyn ah: stock way yaraataa, deyntuna way kordhaysaa, tirtirkuna dib ayuu u celiyaa', () async {
    final p = await call('POST', '/api/products', body: {'name': 'Test', 'price': 10, 'cost': 7, 'quantity': 20});
    final c = await call('POST', '/api/customers', body: {'name': 'Macmiil Test'});

    final sale = await call('POST', '/api/sales', body: {
      'items': [
        {'product_id': p['id'], 'quantity': 3}
      ],
      'customer_id': c['id'],
      'paid': 10,
    });
    expect(sale['total'], 30);
    expect((await call('GET', '/api/products/${p['id']}'))['quantity'], 17);
    expect((await call('GET', '/api/customers/${c['id']}'))['balance'], 20);

    await call('DELETE', '/api/sales/${sale['id']}');
    expect((await call('GET', '/api/products/${p['id']}'))['quantity'], 20);
    expect((await call('GET', '/api/customers/${c['id']}'))['balance'], 0);
  });

  test('stock kuma filna waa la diidaa', () async {
    final p = await call('POST', '/api/products', body: {'name': 'Yar', 'price': 1, 'quantity': 1});
    expect(
      () => call('POST', '/api/sales', body: {
        'items': [
          {'product_id': p['id'], 'quantity': 5}
        ]
      }),
      throwsA(isA<ApiException>()),
    );
  });

  test('AI demo wuxuu ka jawaabaa su\'aalaha deynta', () async {
    final r = await call('POST', '/api/ai/chat', body: {'message': 'Yaa deyn igu leh?'});
    expect(r['reply'], contains('deyn'));
    final h = await call('GET', '/api/ai/history') as List;
    expect(h.length, 2);
  });
}
