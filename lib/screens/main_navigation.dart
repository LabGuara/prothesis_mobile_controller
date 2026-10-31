import 'package:flutter/material.dart';

import '../services/collect_store.dart';
import '../services/mqtt_service.dart';
import 'collects_screen.dart';
import 'home_screen.dart';
import 'sensors_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key, required this.collectStore});

  final CollectStore collectStore;

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  // Commands and collect starts share one connection, which the control screen connects and shows.
  final _mqttService = MqttService(subscribeToPowerFeedback: true);

  @override
  void dispose() {
    _mqttService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      HomeScreen(mqttService: _mqttService, collectStore: widget.collectStore),
      SensorsScreen(isActive: _currentIndex == 1),
      CollectsScreen(mqttService: _mqttService, collectStore: widget.collectStore),
    ];

    const items = <BottomNavigationBarItem>[
      BottomNavigationBarItem(icon: Icon(Icons.directions_walk_rounded), label: 'Control'),
      BottomNavigationBarItem(icon: Icon(Icons.show_chart_rounded), label: 'Sensors'),
      BottomNavigationBarItem(icon: Icon(Icons.assignment_rounded), label: 'Collects'),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFF0F172A),
          selectedItemColor: const Color(0xFF2563EB),
          unselectedItemColor: const Color(0xFF64748B),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          items: items,
        ),
      ),
    );
  }
}
