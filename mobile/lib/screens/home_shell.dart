import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'dashboard_screen.dart';
import 'more_screen.dart';
import 'products_screen.dart';
import 'sales_screen.dart';

/// Navigation-ka hoose: Dashboard · Iib · AI · Stock · Wax kale
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  // Key-yadan waxay u oggolaanayaan in shaashadaha dib loo cusboonaysiiyo marka tab la beddelo
  final _keys = List.generate(5, (_) => UniqueKey());

  void _go(int i) => setState(() {
        if (i == _index) return;
        _keys[i] = UniqueKey(); // xog cusub soo rar
        _index = i;
      });

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(key: _keys[0], onOpenChat: () => _go(2), onOpenSales: () => _go(1), onOpenStock: () => _go(3)),
      SalesScreen(key: _keys[1]),
      ChatScreen(key: _keys[2]),
      ProductsScreen(key: _keys[3]),
      MoreScreen(key: _keys[4]),
    ];
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Guud'),
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'Iib'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Kaaliye'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Stock'),
          NavigationDestination(icon: Icon(Icons.menu), label: 'Kale'),
        ],
      ),
    );
  }
}
