import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/outbox.dart';
import 'profile_screen.dart';
import 'sites_screen.dart';
import 'submissions_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) Outbox.instance.sync();
  }

  @override
  Widget build(BuildContext context) {
    final pending = context.watch<Outbox>().pending.length;
    return Scaffold(
      body: IndexedStack(index: _tab, children: const [SitesScreen(), SubmissionsScreen(), ProfileScreen()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.cell_tower), label: 'My Sites'),
          NavigationDestination(
            icon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(Icons.history)),
            label: 'Submissions',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), label: 'Me'),
        ],
      ),
    );
  }
}
