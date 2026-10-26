double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
int _i(dynamic v) => v == null ? 0 : (v as num).toInt();
DateTime _dt(dynamic v) => v == null ? DateTime.now() : DateTime.parse('${v.toString().replaceFirst(' ', 'T')}Z').toLocal();

class AppUser {
  final int id;
  final String name, phone, businessName, businessType, currency;
  AppUser({required this.id, required this.name, required this.phone, required this.businessName, required this.businessType, required this.currency});
  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: _i(j['id']),
        name: j['name'] ?? '',
        phone: j['phone'] ?? '',
        businessName: j['business_name'] ?? '',
        businessType: j['business_type'] ?? 'general',
        currency: j['currency'] ?? 'USD',
      );
}

class Product {
  final int id;
  final String name;
  final String? sku, category, unit;
  final double price, cost, quantity, lowStockThreshold;
  Product({required this.id, required this.name, this.sku, this.category, this.unit, required this.price, required this.cost, required this.quantity, required this.lowStockThreshold});
  bool get isLow => quantity <= lowStockThreshold;
  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: _i(j['id']),
        name: j['name'] ?? '',
        sku: j['sku'],
        category: j['category'],
        unit: j['unit'],
        price: _d(j['price']),
        cost: _d(j['cost']),
        quantity: _d(j['quantity']),
        lowStockThreshold: _d(j['low_stock_threshold']),
      );
}

class Customer {
  final int id;
  final String name;
  final String? phone, notes;
  final double balance;
  Customer({required this.id, required this.name, this.phone, this.notes, required this.balance});
  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: _i(j['id']),
        name: j['name'] ?? '',
        phone: j['phone'],
        notes: j['notes'],
        balance: _d(j['balance']),
      );
}

class SaleItem {
  final String name;
  final double quantity, price;
  SaleItem({required this.name, required this.quantity, required this.price});
  factory SaleItem.fromJson(Map<String, dynamic> j) => SaleItem(name: j['name'] ?? '', quantity: _d(j['quantity']), price: _d(j['price']));
}

class Sale {
  final int id;
  final double total, paid;
  final String paymentMethod;
  final String? customerName, note;
  final int itemCount;
  final DateTime createdAt;
  final List<SaleItem> items;
  Sale({required this.id, required this.total, required this.paid, required this.paymentMethod, this.customerName, this.note, required this.itemCount, required this.createdAt, this.items = const []});
  double get due => total - paid;
  factory Sale.fromJson(Map<String, dynamic> j) => Sale(
        id: _i(j['id']),
        total: _d(j['total']),
        paid: _d(j['paid']),
        paymentMethod: j['payment_method'] ?? 'cash',
        customerName: j['customer_name'],
        note: j['note'],
        itemCount: _i(j['item_count'] ?? (j['items'] as List?)?.length),
        createdAt: _dt(j['created_at']),
        items: ((j['items'] as List?) ?? []).map((e) => SaleItem.fromJson(e)).toList(),
      );
}

class Expense {
  final int id;
  final String category;
  final double amount;
  final String? note;
  final String date;
  Expense({required this.id, required this.category, required this.amount, this.note, required this.date});
  factory Expense.fromJson(Map<String, dynamic> j) =>
      Expense(id: _i(j['id']), category: j['category'] ?? 'other', amount: _d(j['amount']), note: j['note'], date: j['date'] ?? '');
}

class InvoiceItem {
  final String description;
  final double quantity, price, amount;
  InvoiceItem({required this.description, required this.quantity, required this.price, required this.amount});
  factory InvoiceItem.fromJson(Map<String, dynamic> j) =>
      InvoiceItem(description: j['description'] ?? '', quantity: _d(j['quantity']), price: _d(j['price']), amount: _d(j['amount']));
}

class Invoice {
  final int id;
  final String number, status;
  final double total;
  final String? customerName, customerPhone, dueDate, note;
  final DateTime createdAt;
  final List<InvoiceItem> items;
  Invoice({required this.id, required this.number, required this.status, required this.total, this.customerName, this.customerPhone, this.dueDate, this.note, required this.createdAt, required this.items});
  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: _i(j['id']),
        number: j['number'] ?? '',
        status: j['status'] ?? 'unpaid',
        total: _d(j['total']),
        customerName: j['customer_name'],
        customerPhone: j['customer_phone'],
        dueDate: j['due_date'],
        note: j['note'],
        createdAt: _dt(j['created_at']),
        items: ((j['items'] as List?) ?? []).map((e) => InvoiceItem.fromJson(e)).toList(),
      );
}

class Summary {
  final int salesCount, customersWithDebt, lowStockCount, unpaidInvoicesCount;
  final double revenue, grossProfit, expenses, netProfit, cashReceived, customerDebtTotal, stockValue, unpaidInvoicesTotal;
  Summary.fromJson(Map<String, dynamic> j)
      : salesCount = _i(j['sales_count']),
        customersWithDebt = _i(j['customers_with_debt']),
        lowStockCount = _i(j['low_stock_count']),
        unpaidInvoicesCount = _i(j['unpaid_invoices_count']),
        revenue = _d(j['revenue']),
        grossProfit = _d(j['gross_profit']),
        expenses = _d(j['expenses']),
        netProfit = _d(j['net_profit']),
        cashReceived = _d(j['cash_received']),
        customerDebtTotal = _d(j['customer_debt_total']),
        stockValue = _d(j['stock_value']),
        unpaidInvoicesTotal = _d(j['unpaid_invoices_total']);
}

class DailyPoint {
  final String day;
  final double revenue, expenses;
  DailyPoint({required this.day, required this.revenue, required this.expenses});
  factory DailyPoint.fromJson(Map<String, dynamic> j) => DailyPoint(day: j['day'], revenue: _d(j['revenue']), expenses: _d(j['expenses']));
}

class TopProduct {
  final String name;
  final double quantity, revenue, profit;
  TopProduct.fromJson(Map<String, dynamic> j)
      : name = j['name'] ?? '',
        quantity = _d(j['quantity']),
        revenue = _d(j['revenue']),
        profit = _d(j['profit']);
}

class Insight {
  final String type, text;
  Insight.fromJson(Map<String, dynamic> j)
      : type = j['type'] ?? '',
        text = j['text'] ?? '';
}

class ChatMessage {
  final String role, content;
  final bool isError;
  ChatMessage({required this.role, required this.content, this.isError = false});
  bool get isUser => role == 'user';
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(role: j['role'], content: j['content'] ?? '');
}
