import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/format.dart' show money;
import 'api.dart';

/// Backend tijaabo ah oo telefoonka gudihiisa ku shaqeeya (Demo mode, Qaybta 1).
///
/// Wuxuu leeyahay isla endpoints-ka iyo isla qaabka JSON ee backend-ka dhabta ah.
/// Sidaas darteed marka backend-ka la xiro (USE_MOCK=false), screens-ka waxba
/// lagama beddelayo. Xogta waxaa lagu kaydiyaa telefoonka (shared_preferences).
class MockBackend {
  MockBackend._();
  static final MockBackend instance = MockBackend._();

  static const demoPhone = '615000000';
  static const demoPassword = 'demo123';
  static const _prefsKey = 'ganacsi_demo_db_v1';

  Map<String, dynamic>? _db;

  // ---------------------------------------------------------------- storage

  Future<void> _ensure() async {
    if (_db != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        _db = jsonDecode(raw) as Map<String, dynamic>;
        return;
      }
    } catch (_) {
      // xog khaldan: dib u bilow
    }
    _seed();
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_db));
    } catch (_) {}
  }

  /// Dib ugu celi xogta tijaabada sidii ay ahayd.
  Future<void> reset() async {
    _seed();
    await _save();
  }

  Future<dynamic> handle(String method, String path, Map<String, String> query, Object? body, String? token) async {
    await _ensure();
    // Daahid yar si loading-ka loo arko sida server dhab ah
    await Future<void>.delayed(Duration(milliseconds: path == '/api/ai/chat' ? 900 : 200));
    final b = body is Map ? Map<String, dynamic>.from(jsonDecode(jsonEncode(body)) as Map) : <String, dynamic>{};
    final segs = Uri.parse(path).pathSegments.where((s) => s.isNotEmpty).toList();
    final out = _route(method, segs, query, b, token);
    if (method != 'GET') await _save();
    // Koobi qoto dheer: screens-ku ma beddeli karaan xogta kaydsan
    return out == null ? null : jsonDecode(jsonEncode(out));
  }

  // ---------------------------------------------------------------- routing

  dynamic _route(String m, List<String> s, Map<String, String> q, Map<String, dynamic> b, String? token) {
    if (s.length < 2 || s[0] != 'api') throw ApiException(404, 'Lama helin');
    final res = s[1];
    final a = s.length > 2 ? s[2] : null;
    final id = a == null ? null : int.tryParse(a);
    final sub = s.length > 3 ? s[3] : null;

    if (res == 'health') return {'ok': true, 'demo': true};
    if (res == 'auth' && m == 'POST' && a == 'login') return _login(b);
    if (res == 'auth' && m == 'POST' && a == 'register') return _register(b);

    final uid = _uid(token);
    switch (res) {
      case 'me':
        if (m == 'GET') return _publicUser(_user(uid));
        if (m == 'PUT') return _updateProfile(uid, b);
      case 'dashboard':
        if (m == 'GET') return _dashboard(uid, q['period'] ?? 'today');
      case 'reports':
        if (m != 'GET') break;
        switch (a) {
          case 'summary':
            return _summary(uid, q['period'] ?? 'month');
          case 'top-products':
            return _topProducts(uid, q['period'] ?? 'month', int.tryParse(q['limit'] ?? '') ?? 5);
          case 'daily':
            return _daily(uid, int.tryParse(q['days'] ?? '') ?? 7);
          case 'expenses-by-category':
            return _expensesByCategory(uid, q['period'] ?? 'month');
        }
      case 'products':
        if (a == null && m == 'GET') return _listProducts(uid, q: q['q'], low: q['low_stock'] == 'true');
        if (a == null && m == 'POST') return _createProduct(uid, b);
        if (id != null && sub == 'stock' && m == 'POST') return _adjustStock(uid, id, b['change']);
        if (id != null && sub == null) {
          if (m == 'GET') return _product(uid, id);
          if (m == 'PUT') return _updateProduct(uid, id, b);
          if (m == 'DELETE') {
            _product(uid, id);
            _rows('products').removeWhere((p) => p['id'] == id);
            return {'ok': true};
          }
        }
      case 'customers':
        if (a == null && m == 'GET') return _listCustomers(uid, q: q['q'], withDebt: q['with_debt'] == 'true');
        if (a == null && m == 'POST') return _createCustomer(uid, b);
        if (id != null && sub == 'payments' && m == 'POST') return _recordPayment(uid, id, b['amount']);
        if (id != null && sub == null) {
          if (m == 'GET') return _customerDetail(uid, id);
          if (m == 'PUT') return _updateCustomer(uid, id, b);
          if (m == 'DELETE') {
            _customer(uid, id);
            _rows('customers').removeWhere((c) => c['id'] == id);
            for (final s in _rows('sales')) {
              if (s['customer_id'] == id) s['customer_id'] = null;
            }
            return {'ok': true};
          }
        }
      case 'sales':
        if (a == null && m == 'GET') return _listSales(uid, q['period'] ?? 'month', int.tryParse(q['limit'] ?? '') ?? 100);
        if (a == null && m == 'POST') return _saleOut(_createSale(uid, b));
        if (id != null && m == 'GET') return _saleOut(_sale(uid, id));
        if (id != null && m == 'DELETE') return _deleteSale(uid, id);
      case 'expenses':
        if (a == 'categories') return const ['rent', 'salary', 'utilities', 'transport', 'stock_purchase', 'marketing', 'other'];
        if (a == null && m == 'GET') return _listExpenses(uid, q['period'] ?? 'month');
        if (a == null && m == 'POST') return _createExpense(uid, b);
        if (id != null && m == 'DELETE') {
          final e = _mine('expenses', uid).where((x) => x['id'] == id);
          if (e.isEmpty) throw ApiException(404, 'Kharashkan lama helin');
          _rows('expenses').removeWhere((x) => x['id'] == id);
          return {'ok': true};
        }
      case 'invoices':
        if (a == null && m == 'GET') return _listInvoices(uid, q['status']);
        if (a == null && m == 'POST') return _invoiceOut(_createInvoice(uid, b));
        if (id != null && sub == null && m == 'GET') return _invoiceOut(_invoice(uid, id));
        if (id != null && sub == 'status' && m == 'PUT') return _setInvoiceStatus(uid, id, b['status']);
      case 'ai':
        if (a == 'chat' && m == 'POST') return _chat(uid, b);
        if (a == 'history' && m == 'GET') return _history(uid);
        if (a == 'history' && m == 'DELETE') {
          _rows('chat').removeWhere((x) => x['user_id'] == uid);
          return {'ok': true};
        }
        if (a == 'insights' && m == 'GET') return _insights(uid);
    }
    throw ApiException(404, 'Lama helin: $m /${s.join('/')}');
  }

  // ---------------------------------------------------------------- helpers

  List<Map<String, dynamic>> _rows(String table) => (_db![table] as List).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> _mine(String table, int uid) => _rows(table).where((r) => r['user_id'] == uid).toList();

  Map<String, dynamic>? _find(String table, Object? id) {
    for (final r in _rows(table)) {
      if (r['id'] == id) return r;
    }
    return null;
  }

  int _nextId() {
    final n = (_db!['seq'] as num).toInt() + 1;
    _db!['seq'] = n;
    return n;
  }

  double? _optNum(dynamic v, String field, {double min = 0}) {
    if (v == null || (v is String && v.trim().isEmpty)) return null;
    final n = v is num ? v.toDouble() : double.tryParse('$v');
    if (n == null || n.isNaN || n < min) throw ApiException(400, '$field waa inuu noqdaa tiro sax ah');
    return n;
  }

  double _reqNum(dynamic v, String field, {double min = 0}) =>
      _optNum(v, field, min: min) ?? (throw ApiException(400, '$field waa loo baahan yahay'));

  String? _optStr(dynamic v) {
    final s = v == null ? '' : '$v'.trim();
    return s.isEmpty ? null : s;
  }

  String _reqStr(dynamic v, String field) => _optStr(v) ?? (throw ApiException(400, '$field waa loo baahan yahay'));

  int? _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v');

  double _n(dynamic v) => v == null ? 0.0 : (v as num).toDouble();

  double _r2(num v) => (v * 100).round() / 100;

  String _q(dynamic v) {
    final d = _n(v);
    return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(2);
  }

  /// 'YYYY-MM-DD HH:MM:SS' (UTC), sida backend-ka
  String _fmt(DateTime d) => d.toUtc().toIso8601String().substring(0, 19).replaceFirst('T', ' ');
  String _now() => _fmt(DateTime.now());
  String _todayDate() => _now().substring(0, 10);

  ({String from, String to}) _range(String period) {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    DateTime from;
    var to = today.add(const Duration(days: 1));
    switch (period) {
      case 'today':
        from = today;
      case 'yesterday':
        from = today.subtract(const Duration(days: 1));
        to = today;
      case 'week':
        from = today.subtract(const Duration(days: 6));
      case 'month':
        from = today.subtract(const Duration(days: 29));
      case 'year':
        from = today.subtract(const Duration(days: 364));
      case 'all':
        from = DateTime.utc(2000);
      default:
        throw ApiException(400, 'period waa: today, yesterday, week, month, year, all');
    }
    return (from: _fmt(from), to: _fmt(to));
  }

  bool _inRange(dynamic ts, ({String from, String to}) r) {
    final s = '$ts';
    return s.compareTo(r.from) >= 0 && s.compareTo(r.to) < 0;
  }

  bool _dateInRange(dynamic date, ({String from, String to}) r) {
    final s = '$date';
    return s.compareTo(r.from.substring(0, 10)) >= 0 && s.compareTo(r.to.substring(0, 10)) < 0;
  }

  // ---------------------------------------------------------------- auth

  Map<String, dynamic> _user(int uid) => _find('users', uid) ?? (throw ApiException(401, 'Fadlan soo gal (login)'));

  int _uid(String? token) {
    final id = int.tryParse((token ?? '').replaceFirst('demo.', ''));
    if (id == null || _find('users', id) == null) throw ApiException(401, 'Fadlan soo gal (login)');
    return id;
  }

  Map<String, dynamic> _publicUser(Map<String, dynamic> u) => Map<String, dynamic>.of(u)..remove('password');

  Map<String, dynamic> _login(Map<String, dynamic> b) {
    final phone = '${b['phone'] ?? ''}'.replaceAll(RegExp(r'\s+'), '');
    final matches = _rows('users').where((x) => x['phone'] == phone).toList();
    if (matches.isEmpty || matches.first['password'] != '${b['password'] ?? ''}') {
      throw ApiException(401, 'Telefoonka ama password-ka waa khalad');
    }
    final u = matches.first;
    return {'token': 'demo.${u['id']}', 'user': _publicUser(u)};
  }

  Map<String, dynamic> _register(Map<String, dynamic> b) {
    final phone = '${b['phone'] ?? ''}'.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^\+?\d{7,15}$').hasMatch(phone)) throw ApiException(400, 'Lambarka telefoonka sax ma aha');
    if ('${b['password'] ?? ''}'.length < 6) throw ApiException(400, 'Password-ku waa inuu ahaadaa ugu yaraan 6 xaraf');
    final name = _reqStr(b['name'], 'Magacaaga');
    final business = _reqStr(b['business_name'], 'Magaca ganacsiga');
    if (_rows('users').any((x) => x['phone'] == phone)) throw ApiException(409, 'Lambarkan horay ayaa loo diiwaangeliyay');
    final u = <String, dynamic>{
      'id': _nextId(),
      'name': name,
      'phone': phone,
      'password': '${b['password']}',
      'business_name': business,
      'business_type': _optStr(b['business_type']) ?? 'general',
      'currency': _optStr(b['currency']) ?? 'USD',
      'language': _optStr(b['language']) ?? 'so',
      'created_at': _now(),
    };
    _rows('users').add(u);
    return {'token': 'demo.${u['id']}', 'user': _publicUser(u)};
  }

  Map<String, dynamic> _updateProfile(int uid, Map<String, dynamic> b) {
    final u = _user(uid);
    final updates = <String, dynamic>{};
    for (final k in ['name', 'business_name', 'business_type', 'currency', 'language']) {
      if (b.containsKey(k)) updates[k] = _reqStr(b[k], k);
    }
    u.addAll(updates);
    return _publicUser(u);
  }

  // ---------------------------------------------------------------- products

  List<Map<String, dynamic>> _listProducts(int uid, {String? q, bool low = false}) {
    var l = _mine('products', uid);
    if (q != null && q.trim().isNotEmpty) {
      final qq = q.trim().toLowerCase();
      l = l.where((p) => '${p['name']} ${p['sku'] ?? ''} ${p['category'] ?? ''}'.toLowerCase().contains(qq)).toList();
    }
    if (low) l = l.where((p) => _n(p['quantity']) <= _n(p['low_stock_threshold'])).toList();
    l.sort((x, y) => '${x['name']}'.toLowerCase().compareTo('${y['name']}'.toLowerCase()));
    return l;
  }

  Map<String, dynamic> _product(int uid, int? id) {
    final p = _find('products', id);
    if (p == null || p['user_id'] != uid) throw ApiException(404, 'Alaabtan lama helin');
    return p;
  }

  Map<String, dynamic> _createProduct(int uid, Map<String, dynamic> b) {
    final p = <String, dynamic>{
      'name': _reqStr(b['name'], 'name'),
      'sku': _optStr(b['sku']),
      'category': _optStr(b['category']),
      'price': _reqNum(b['price'], 'price'),
      'cost': _optNum(b['cost'], 'cost') ?? 0.0,
      'quantity': _optNum(b['quantity'], 'quantity') ?? 0.0,
      'low_stock_threshold': _optNum(b['low_stock_threshold'], 'low_stock_threshold') ?? 5.0,
      'unit': _optStr(b['unit']) ?? 'pcs',
    };
    p['id'] = _nextId();
    p['user_id'] = uid;
    p['created_at'] = _now();
    _rows('products').add(p);
    return p;
  }

  Map<String, dynamic> _updateProduct(int uid, int id, Map<String, dynamic> b) {
    final p = _product(uid, id);
    final updates = <String, dynamic>{};
    if (b.containsKey('name')) updates['name'] = _reqStr(b['name'], 'name');
    for (final k in ['sku', 'category', 'unit']) {
      if (b.containsKey(k)) updates[k] = _optStr(b[k]);
    }
    for (final k in ['price', 'cost', 'quantity', 'low_stock_threshold']) {
      if (b.containsKey(k)) updates[k] = _reqNum(b[k], k);
    }
    p.addAll(updates);
    return p;
  }

  Map<String, dynamic> _adjustStock(int uid, int id, dynamic change) {
    final p = _product(uid, id);
    final delta = change is num ? change.toDouble() : double.tryParse('$change');
    if (delta == null) throw ApiException(400, 'change waa inuu tiro noqdaa');
    final q = _n(p['quantity']) + delta;
    if (q < 0) throw ApiException(400, 'Stock-gu kama yaraan karo eber');
    p['quantity'] = q;
    return p;
  }

  // ---------------------------------------------------------------- customers

  List<Map<String, dynamic>> _listCustomers(int uid, {String? q, bool withDebt = false}) {
    var l = _mine('customers', uid);
    if (q != null && q.trim().isNotEmpty) {
      final qq = q.trim().toLowerCase();
      l = l.where((c) => '${c['name']} ${c['phone'] ?? ''}'.toLowerCase().contains(qq)).toList();
    }
    if (withDebt) {
      l = l.where((c) => _n(c['balance']) > 0).toList()..sort((x, y) => _n(y['balance']).compareTo(_n(x['balance'])));
    } else {
      l.sort((x, y) => '${x['name']}'.toLowerCase().compareTo('${y['name']}'.toLowerCase()));
    }
    return l;
  }

  Map<String, dynamic> _customer(int uid, int? id) {
    final c = _find('customers', id);
    if (c == null || c['user_id'] != uid) throw ApiException(404, 'Macmiilkan lama helin');
    return c;
  }

  Map<String, dynamic> _customerDetail(int uid, int id) {
    final c = _customer(uid, id);
    final sales = _mine('sales', uid).where((s) => s['customer_id'] == id).toList()
      ..sort((x, y) => '${y['created_at']}'.compareTo('${x['created_at']}'));
    return {...c, 'sales': sales.take(50).map(_saleOut).toList()};
  }

  Map<String, dynamic> _createCustomer(int uid, Map<String, dynamic> b) {
    final c = <String, dynamic>{
      'name': _reqStr(b['name'], 'Magaca'),
      'phone': _optStr(b['phone']),
      'notes': _optStr(b['notes']),
      'balance': _optNum(b['balance'], 'balance') ?? 0.0,
    };
    c['id'] = _nextId();
    c['user_id'] = uid;
    c['created_at'] = _now();
    _rows('customers').add(c);
    return c;
  }

  Map<String, dynamic> _updateCustomer(int uid, int id, Map<String, dynamic> b) {
    final c = _customer(uid, id);
    final updates = <String, dynamic>{};
    if (b.containsKey('name')) updates['name'] = _reqStr(b['name'], 'Magaca');
    for (final k in ['phone', 'notes']) {
      if (b.containsKey(k)) updates[k] = _optStr(b[k]);
    }
    c.addAll(updates);
    return c;
  }

  Map<String, dynamic> _recordPayment(int uid, int id, dynamic amount) {
    final c = _customer(uid, id);
    final a = _reqNum(amount, 'amount', min: 0.01);
    if (a > _n(c['balance']) + 0.0001) {
      throw ApiException(400, 'Lacagta (${money(a)}) way ka badan tahay deynta (${money(_n(c['balance']))})');
    }
    c['balance'] = _r2(_n(c['balance']) - a);
    return c;
  }

  // ---------------------------------------------------------------- sales

  Map<String, dynamic> _sale(int uid, int id) {
    final s = _find('sales', id);
    if (s == null || s['user_id'] != uid) throw ApiException(404, 'Iibkan lama helin');
    return s;
  }

  Map<String, dynamic> _saleOut(Map<String, dynamic> s) {
    final c = s['customer_id'] == null ? null : _find('customers', s['customer_id']);
    return {...s, 'customer_name': c?['name'], 'item_count': (s['items'] as List).length};
  }

  List<Map<String, dynamic>> _listSales(int uid, String period, int limit) {
    final r = _range(period);
    final l = _mine('sales', uid).where((s) => _inRange(s['created_at'], r)).toList()
      ..sort((x, y) => '${y['created_at']}'.compareTo('${x['created_at']}'));
    return l.take(limit.clamp(1, 500).toInt()).map(_saleOut).toList();
  }

  Map<String, dynamic> _createSale(int uid, Map<String, dynamic> b, {String? at}) {
    final items = b['items'];
    if (items is! List || items.isEmpty) throw ApiException(400, 'items waa loo baahan yahay');

    // 1) Hubi wax walba ka hor intaan waxba la beddelin
    final need = <int, double>{};
    final lines = <Map<String, dynamic>>[];
    var total = 0.0;
    var cost = 0.0;
    for (final raw in items) {
      final it = Map<String, dynamic>.from(raw as Map);
      final p = _product(uid, _toInt(it['product_id']));
      final pid = p['id'] as int;
      final qty = _reqNum(it['quantity'], 'quantity', min: 0.001);
      need[pid] = (need[pid] ?? 0.0) + qty;
      if (need[pid]! > _n(p['quantity'])) {
        throw ApiException(400, 'Stock kuma filna: ${p['name']} (waxaa jira ${_q(p['quantity'])})');
      }
      final price = _optNum(it['price'], 'price') ?? _n(p['price']);
      total += qty * price;
      cost += qty * _n(p['cost']);
      lines.add({'product_id': pid, 'name': p['name'], 'quantity': qty, 'price': price, 'cost': _n(p['cost'])});
    }
    total = _r2(total);
    cost = _r2(cost);
    final cid = _toInt(b['customer_id']);
    final customer = cid == null ? null : _customer(uid, cid);
    final paid = _optNum(b['paid'], 'paid') ?? total;
    if (paid > total + 0.0001) throw ApiException(400, 'Lacagta la bixiyay kama badnaan karto wadarta');
    if (paid < total && customer == null) throw ApiException(400, 'Iib deyn ah wuxuu u baahan yahay macmiil');

    // 2) Hadda keydi
    for (final e in need.entries) {
      final p = _find('products', e.key)!;
      p['quantity'] = _n(p['quantity']) - e.value;
    }
    if (customer != null && paid < total) customer['balance'] = _r2(_n(customer['balance']) + (total - paid));
    final sale = <String, dynamic>{
      'id': _nextId(),
      'user_id': uid,
      'customer_id': customer?['id'],
      'total': total,
      'cost_total': cost,
      'paid': _r2(paid),
      'payment_method': _optStr(b['payment_method']) ?? 'cash',
      'note': _optStr(b['note']),
      'created_at': at ?? _now(),
      'items': lines,
    };
    _rows('sales').add(sale);
    return sale;
  }

  Map<String, dynamic> _deleteSale(int uid, int id) {
    final s = _sale(uid, id);
    for (final it in (s['items'] as List).cast<Map<String, dynamic>>()) {
      final p = _find('products', it['product_id']);
      if (p != null) p['quantity'] = _n(p['quantity']) + _n(it['quantity']);
    }
    final c = s['customer_id'] == null ? null : _find('customers', s['customer_id']);
    final due = _n(s['total']) - _n(s['paid']);
    if (c != null && due > 0) {
      final nb = _n(c['balance']) - due;
      c['balance'] = _r2(nb < 0 ? 0 : nb);
    }
    _rows('sales').removeWhere((x) => x['id'] == id);
    return {'ok': true};
  }

  // ---------------------------------------------------------------- expenses

  List<Map<String, dynamic>> _listExpenses(int uid, String period) {
    final r = _range(period);
    return _mine('expenses', uid).where((e) => _dateInRange(e['date'], r)).toList()
      ..sort((x, y) {
        final d = '${y['date']}'.compareTo('${x['date']}');
        return d != 0 ? d : (y['id'] as int).compareTo(x['id'] as int);
      });
  }

  Map<String, dynamic> _createExpense(int uid, Map<String, dynamic> b) {
    final date = _optStr(b['date']) ?? _todayDate();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) throw ApiException(400, 'date waa qaab YYYY-MM-DD');
    final e = <String, dynamic>{
      'category': _reqStr(b['category'], 'category'),
      'amount': _reqNum(b['amount'], 'amount', min: 0.01),
      'note': _optStr(b['note']),
      'date': date,
    };
    e['id'] = _nextId();
    e['user_id'] = uid;
    e['created_at'] = _now();
    _rows('expenses').add(e);
    return e;
  }

  // ---------------------------------------------------------------- invoices

  Map<String, dynamic> _invoice(int uid, int id) {
    final i = _find('invoices', id);
    if (i == null || i['user_id'] != uid) throw ApiException(404, 'Invoice-kan lama helin');
    return i;
  }

  Map<String, dynamic> _invoiceOut(Map<String, dynamic> i) {
    final c = i['customer_id'] == null ? null : _find('customers', i['customer_id']);
    return {...i, 'customer_name': c?['name'], 'customer_phone': c?['phone']};
  }

  List<Map<String, dynamic>> _listInvoices(int uid, String? status) {
    var l = _mine('invoices', uid);
    if (status != null && status.isNotEmpty) l = l.where((i) => i['status'] == status).toList();
    l.sort((x, y) => (y['id'] as int).compareTo(x['id'] as int));
    return l.map(_invoiceOut).toList();
  }

  Map<String, dynamic> _createInvoice(int uid, Map<String, dynamic> b) {
    final raw = b['items'];
    if (raw is! List || raw.isEmpty) throw ApiException(400, 'items waa loo baahan yahay');
    final items = raw.map((x) {
      final it = Map<String, dynamic>.from(x as Map);
      final quantity = _reqNum(it['quantity'], 'quantity', min: 0.001);
      final price = _reqNum(it['price'], 'price');
      return <String, dynamic>{
        'description': _reqStr(it['description'], 'description'),
        'quantity': quantity,
        'price': price,
        'amount': _r2(quantity * price),
      };
    }).toList();
    final total = _r2(items.fold(0.0, (s, it) => s + _n(it['amount'])));
    final cid = _toInt(b['customer_id']);
    final customer = cid == null ? null : _customer(uid, cid);
    final count = _mine('invoices', uid).length;
    final inv = <String, dynamic>{
      'id': _nextId(),
      'user_id': uid,
      'customer_id': customer?['id'],
      'number': 'INV-${(count + 1).toString().padLeft(4, '0')}',
      'items': items,
      'total': total,
      'status': 'unpaid',
      'due_date': _optStr(b['due_date']),
      'note': _optStr(b['note']),
      'created_at': _now(),
    };
    _rows('invoices').add(inv);
    return inv;
  }

  Map<String, dynamic> _setInvoiceStatus(int uid, int id, dynamic status) {
    if (!['unpaid', 'paid', 'cancelled'].contains(status)) throw ApiException(400, 'status waa: unpaid, paid, cancelled');
    final i = _invoice(uid, id);
    i['status'] = status;
    return _invoiceOut(i);
  }

  // ---------------------------------------------------------------- reports

  Map<String, dynamic> _summary(int uid, String period) {
    final r = _range(period);
    final sales = _mine('sales', uid).where((s) => _inRange(s['created_at'], r)).toList();
    final expenses = _mine('expenses', uid).where((e) => _dateInRange(e['date'], r)).toList();
    double sum(List<Map<String, dynamic>> l, String k) => l.fold(0.0, (a, x) => a + _n(x[k]));

    final revenue = sum(sales, 'total');
    final cogs = sum(sales, 'cost_total');
    final exp = sum(expenses, 'amount');
    final debtors = _mine('customers', uid).where((c) => _n(c['balance']) > 0).toList();
    final products = _mine('products', uid);
    final unpaid = _mine('invoices', uid).where((i) => i['status'] == 'unpaid').toList();
    return {
      'period': period,
      'sales_count': sales.length,
      'revenue': _r2(revenue),
      'cost_of_goods': _r2(cogs),
      'gross_profit': _r2(revenue - cogs),
      'expenses': _r2(exp),
      'net_profit': _r2(revenue - cogs - exp),
      'cash_received': _r2(sum(sales, 'paid')),
      'customer_debt_total': _r2(sum(debtors, 'balance')),
      'customers_with_debt': debtors.length,
      'low_stock_count': products.where((p) => _n(p['quantity']) <= _n(p['low_stock_threshold'])).length,
      'stock_value': _r2(products.fold(0.0, (a, p) => a + _n(p['quantity']) * _n(p['cost']))),
      'unpaid_invoices_total': _r2(sum(unpaid, 'total')),
      'unpaid_invoices_count': unpaid.length,
    };
  }

  List<Map<String, dynamic>> _topProducts(int uid, String period, int limit) {
    final r = _range(period);
    final agg = <String, Map<String, double>>{};
    for (final s in _mine('sales', uid).where((s) => _inRange(s['created_at'], r))) {
      for (final it in (s['items'] as List).cast<Map<String, dynamic>>()) {
        final a = agg.putIfAbsent('${it['name']}', () => {'quantity': 0.0, 'revenue': 0.0, 'profit': 0.0});
        final q = _n(it['quantity']);
        a['quantity'] = a['quantity']! + q;
        a['revenue'] = a['revenue']! + q * _n(it['price']);
        a['profit'] = a['profit']! + q * (_n(it['price']) - _n(it['cost']));
      }
    }
    final list = agg.entries
        .map((e) => <String, dynamic>{
              'name': e.key,
              'quantity': e.value['quantity'],
              'revenue': _r2(e.value['revenue']!),
              'profit': _r2(e.value['profit']!),
            })
        .toList()
      ..sort((x, y) => _n(y['revenue']).compareTo(_n(x['revenue'])));
    return list.take(limit.clamp(1, 50).toInt()).toList();
  }

  List<Map<String, dynamic>> _expensesByCategory(int uid, String period) {
    final r = _range(period);
    final agg = <String, ({double total, int count})>{};
    for (final e in _mine('expenses', uid).where((e) => _dateInRange(e['date'], r))) {
      final k = '${e['category']}';
      final cur = agg[k] ?? (total: 0.0, count: 0);
      agg[k] = (total: cur.total + _n(e['amount']), count: cur.count + 1);
    }
    final list = agg.entries
        .map((e) => <String, dynamic>{'category': e.key, 'total': _r2(e.value.total), 'count': e.value.count})
        .toList()
      ..sort((x, y) => _n(y['total']).compareTo(_n(x['total'])));
    return list;
  }

  List<Map<String, dynamic>> _daily(int uid, int days) {
    final n = days.clamp(1, 90).toInt();
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final sales = _mine('sales', uid);
    final expenses = _mine('expenses', uid);
    final out = <Map<String, dynamic>>[];
    for (var i = n - 1; i >= 0; i--) {
      final day = _fmt(today.subtract(Duration(days: i))).substring(0, 10);
      final s = sales.where((x) => '${x['created_at']}'.startsWith(day)).toList();
      final e = expenses.where((x) => x['date'] == day);
      out.add({
        'day': day,
        'revenue': _r2(s.fold(0.0, (a, x) => a + _n(x['total']))),
        'count': s.length,
        'expenses': _r2(e.fold(0.0, (a, x) => a + _n(x['amount']))),
      });
    }
    return out;
  }

  List<Map<String, dynamic>> _insights(int uid) {
    final tips = <Map<String, dynamic>>[];
    final low = _listProducts(uid, low: true);
    if (low.isNotEmpty) {
      final names = low.take(3).map((p) => p['name']).join(', ');
      tips.add({'type': 'stock', 'text': '${low.length} alaab ayaa dhammaanaya: $names${low.length > 3 ? '...' : ''}'});
    }
    final debtors = _listCustomers(uid, withDebt: true);
    if (debtors.isNotEmpty) {
      final total = debtors.fold(0.0, (a, c) => a + _n(c['balance']));
      tips.add({'type': 'debt', 'text': '${debtors.length} macmiil ayaa deyn kugu leh, wadar ${money(total)}'});
    }
    final week = _summary(uid, 'week');
    if ((week['sales_count'] as int) > 0 && _n(week['expenses']) > _n(week['gross_profit'])) {
      tips.add({'type': 'warning', 'text': 'Toddobaadkan kharashku wuu ka badan yahay faa\'iidada guud'});
    }
    final today = _todayDate();
    final overdue = _mine('invoices', uid)
        .where((i) => i['status'] == 'unpaid' && i['due_date'] != null && '${i['due_date']}'.compareTo(today) < 0)
        .length;
    if (overdue > 0) tips.add({'type': 'invoice', 'text': '$overdue invoice ayaa waqtigoodii dhaafay oo aan la bixin'});
    return tips;
  }

  Map<String, dynamic> _dashboard(int uid, String period) => {
        'summary': _summary(uid, period),
        'daily': _daily(uid, 7),
        'top_products': _topProducts(uid, 'month', 5),
        'low_stock': _listProducts(uid, low: true).take(10).toList(),
        'recent_sales': _listSales(uid, 'week', 5),
        'insights': _insights(uid),
      };

  // ---------------------------------------------------------------- AI (demo)

  List<Map<String, dynamic>> _history(int uid) {
    final l = _mine('chat', uid)..sort((x, y) => (x['id'] as int).compareTo(y['id'] as int));
    return l.length > 50 ? l.sublist(l.length - 50) : l;
  }

  Map<String, dynamic> _chat(int uid, Map<String, dynamic> b) {
    final text = _reqStr(b['message'], 'message');
    if (text.length > 4000) throw ApiException(400, 'Fariinta aad bay u dheer tahay');
    final reply = _demoReply(uid, text);
    _rows('chat').add({'id': _nextId(), 'user_id': uid, 'role': 'user', 'content': text, 'created_at': _now()});
    _rows('chat').add({'id': _nextId(), 'user_id': uid, 'role': 'assistant', 'content': reply, 'created_at': _now()});
    return {'reply': reply, 'actions': <dynamic>[]};
  }

  /// Jawaabo la sii diyaariyay oo ku salaysan xogta dhabta ah ee demo-ga.
  /// Qaybta AI-ga (backend + Claude) ayaa beddeli doonta tan.
  String _demoReply(int uid, String text) {
    final t = text.toLowerCase();
    bool has(List<String> keys) => keys.any(t.contains);
    final u = _user(uid);

    if (has(['stock', 'dhammaan', 'alaab', 'inventory'])) {
      final low = _listProducts(uid, low: true);
      if (low.isEmpty) return 'Hadda ma jiraan alaab dhammaanaysa. Stock-gaagu wuu fiican yahay 👍';
      final lines = low.map((p) => '- ${p['name']}: **${_q(p['quantity'])} ${p['unit'] ?? ''}** ayaa haray').join('\n');
      return '**${low.length} alaab ayaa dhammaanaysa:**\n$lines\n\nTalo: dib u dalbo kuwan ka hor intaanay gebi ahaanba dhammaan.';
    }

    if (has(['deyn', 'debt', 'igu leh', 'lagu leeyahay', 'owe'])) {
      final d = _listCustomers(uid, withDebt: true);
      if (d.isEmpty) return 'Cidna deyn kuguma leh hadda 👍';
      final total = d.fold(0.0, (a, c) => a + _n(c['balance']));
      final lines = d.take(5).map((c) => '- ${c['name']}: **${money(_n(c['balance']))}**').join('\n');
      return '**${d.length} macmiil** ayaa deyn kugu leh, wadar **${money(total)}**:\n$lines\n\n'
          'Talo: qaybta Macaamiisha ka fur macmiilka, kadib riix "Xasuusi" si aad fariin WhatsApp ugu dirto.';
    }

    if (has(['faa\'iido', 'faaiido', 'faiido', 'profit', 'khasaare'])) {
      final s = _summary(uid, 'month');
      final net = _n(s['net_profit']);
      return '**30-ka maalmood ee u dambeeyay:**\n'
          '- Dakhliga: ${money(_n(s['revenue']))}\n'
          '- Faa\'iido guud: ${money(_n(s['gross_profit']))}\n'
          '- Kharashka: ${money(_n(s['expenses']))}\n'
          '- **Faa\'iido saafi ah: ${money(net)}**\n\n'
          '${net >= 0 ? 'Ganacsigu wuu faa\'iideysanayaa. Si aad u kordhiso, diiradda saar alaabta faa\'iidada badan leh.' : 'Kharashku wuu ka badan yahay faa\'iidada. Dib u eeg kharashka ugu weyn ee qaybta Kharashka.'}';
    }

    if (has(['iib', 'sales', 'dakhli', 'revenue', 'sold'])) {
      final w = _summary(uid, 'week');
      final d = _summary(uid, 'today');
      final top = _topProducts(uid, 'week', 3);
      final topLines = top.isEmpty ? '' : '\n\n**Alaabta ugu iibka badan:**\n${top.map((p) => '- ${p['name']} (${_q(p['quantity'])})').join('\n')}';
      return '**Maanta:** ${d['sales_count']} iib · ${money(_n(d['revenue']))}\n'
          '**Toddobaadkan:** ${w['sales_count']} iib · ${money(_n(w['revenue']))}$topLines';
    }

    if (has(['whatsapp', 'xayeysiis', 'fariin', 'promo', 'marketing', 'advert'])) {
      final top = _topProducts(uid, 'month', 2).map((p) => p['name']).toList();
      final items = top.isEmpty ? 'alaabteena' : top.join(' iyo ');
      return 'Waa kan qoraal WhatsApp ah oo aad isticmaali karto:\n\n'
          '🛒 *${u['business_name']}*\n'
          'Asc macaamiil qaali ah! Toddobaadkan waxaan haynaa $items oo tayo sare leh, qiime jaban.\n'
          '✅ Waxaan aqbalnaa EVC Plus, Zaad iyo kaash\n'
          '📞 Nala soo xiriir: ${u['phone']}\n'
          'Ku soo dhowow! 🙏';
    }

    if (has(['kordhin', 'kordhiyo', 'talo', 'increase', 'grow', 'advice', 'horumar'])) {
      final tips = <String>[];
      final low = _listProducts(uid, low: true);
      if (low.isNotEmpty) tips.add('Dib u dalbo ${low.first['name']}: alaab dhammaatay iib kuma keento.');
      final top = _topProducts(uid, 'month', 1);
      if (top.isNotEmpty) tips.add('${top.first['name']} ayaa ugu iibka badan. Had iyo jeer stock ku filan ka hay, oo isku day inaad la iibiso alaab kale (bundle).');
      final debt = _listCustomers(uid, withDebt: true);
      if (debt.isNotEmpty) tips.add('Soo ururi deynta: ${money(debt.fold(0.0, (a, c) => a + _n(c['balance'])))} ayaa macaamiisha kugu maqan.');
      tips.add('U dir macaamiishaada fariin WhatsApp toddobaadkii hal mar oo ku saabsan alaab cusub ama qiime dhimis.');
      return '**Talooyin ku salaysan xogtaada:**\n${tips.map((x) => '- $x').join('\n')}';
    }

    if (has(['salaan', 'asc', 'hello', 'hi', 'iska warran', 'nabad'])) {
      return 'Wcs ${'${u['name']}'.split(' ').first}! Sideen kuu caawin karaa maanta? '
          'Wax iga weydii iibka, stock-ga, deynta ama faa\'iidada.';
    }

    return 'Waan ku caawin karaa arrimahan:\n'
        '- **Iibka**: "Sidee buu ahaa iibka toddobaadkan?"\n'
        '- **Stock**: "Alaabtee ayaa dhammaanaysa?"\n'
        '- **Deynta**: "Yaa deyn igu leh?"\n'
        '- **Faa\'iidada**: "Faa\'iidadayda bishan waa imisa?"\n'
        '- **Suuq-geyn**: "Ii qor fariin WhatsApp"\n\n'
        '(Demo mode: su\'aalaha kale waxaa ka jawaabi doona AI-ga dhabta ah marka backend-ka la xiro.)';
  }

  // ---------------------------------------------------------------- seed

  void _seed() {
    _db = <String, dynamic>{
      'seq': 0,
      'users': <dynamic>[],
      'products': <dynamic>[],
      'customers': <dynamic>[],
      'sales': <dynamic>[],
      'expenses': <dynamic>[],
      'invoices': <dynamic>[],
      'chat': <dynamic>[],
    };
    final uid = _nextId();
    _rows('users').add(<String, dynamic>{
      'id': uid,
      'name': 'Axmed Cali',
      'phone': demoPhone,
      'password': demoPassword,
      'business_name': 'Dukaanka Barwaaqo',
      'business_type': 'retail',
      'currency': 'USD',
      'language': 'so',
      'created_at': _now(),
    });

    const products = [
      ('Bariis 25kg', 'Cunto', 28.0, 22.0, 40.0, 10.0, 'bag'),
      ('Sonkor 50kg', 'Cunto', 45.0, 38.0, 15.0, 5.0, 'bag'),
      ('Saliid 3L', 'Cunto', 7.5, 5.8, 60.0, 15.0, 'pcs'),
      ('Baasto 500g', 'Cunto', 0.8, 0.5, 200.0, 30.0, 'pcs'),
      ('Caano boore 2.5kg', 'Cunto', 18.0, 14.0, 3.0, 5.0, 'pcs'),
      ('Shaah 500g', 'Cabitaan', 3.5, 2.4, 50.0, 10.0, 'pcs'),
      ('Biyo 1.5L (kartoon)', 'Cabitaan', 4.0, 2.8, 4.0, 10.0, 'box'),
      ('Saabuun', 'Nadaafad', 0.6, 0.35, 120.0, 20.0, 'pcs'),
    ];
    final pids = <int>[];
    for (final (name, category, price, cost, quantity, low, unit) in products) {
      final p = _createProduct(uid, {
        'name': name,
        'category': category,
        'price': price,
        'cost': cost,
        'quantity': quantity,
        'low_stock_threshold': low,
        'unit': unit,
      });
      pids.add(p['id'] as int);
    }

    const customers = [
      ('Faadumo Xasan', '615111111'),
      ('Maxamed Nuur', '615222222'),
      ('Hooyo Caasha', '615333333'),
      ('Hotel Jazeera', '615444444'),
    ];
    final cids = <int>[];
    for (final (name, phone) in customers) {
      cids.add(_createCustomer(uid, {'name': name, 'phone': phone})['id'] as int);
    }

    // Iib 14 maalmood ah
    const methods = ['cash', 'evc_plus', 'zaad', 'evc_plus'];
    final now = DateTime.now();
    for (var d = 13; d >= 0; d--) {
      final perDay = 2 + d % 4;
      for (var k = 0; k < perDay; k++) {
        final credit = (d + k) % 5 == 0;
        try {
          _createSale(
            uid,
            {
              'items': [
                {'product_id': pids[(d + k) % 4], 'quantity': 1 + (d + k) % 3},
                {'product_id': pids[3 + (k + d) % 5], 'quantity': 1 + k % 2},
              ],
              if (credit) 'customer_id': cids[(d + k) % cids.length],
              if (credit) 'paid': 0,
              'payment_method': methods[k % 4],
            },
            at: _fmt(now.subtract(Duration(days: d, minutes: 35 * k))),
          );
        } on ApiException {
          // stock dhammaaday: iska dhaaf
        }
      }
    }

    String daysAgo(int d) => _fmt(now.subtract(Duration(days: d))).substring(0, 10);
    const expenses = [
      ('rent', 300.0, 'Kirada dukaanka', 12),
      ('salary', 250.0, 'Mushaharka shaqaalaha', 10),
      ('utilities', 45.0, 'Koronto', 6),
      ('transport', 30.0, 'Gaadiid alaab', 3),
      ('transport', 20.0, 'Gaadiid', 1),
      ('other', 15.0, 'Kharash yar', 0),
    ];
    for (final (category, amount, note, d) in expenses) {
      _createExpense(uid, {'category': category, 'amount': amount, 'note': note, 'date': daysAgo(d)});
    }

    _createInvoice(uid, {
      'customer_id': cids[3],
      'items': [
        {'description': 'Bariis 25kg', 'quantity': 5, 'price': 27},
        {'description': 'Saliid 3L', 'quantity': 10, 'price': 7},
      ],
      'due_date': daysAgo(-7),
    });
    _createInvoice(uid, {
      'customer_id': cids[0],
      'items': [
        {'description': 'Sonkor 50kg', 'quantity': 1, 'price': 45},
      ],
      'due_date': daysAgo(2),
    });
  }
}
