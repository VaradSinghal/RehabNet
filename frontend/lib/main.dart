/// RehabNet – App Entry Point
/// Sets up Provider, dark theme, navigation, and SocketIO connection.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/socket_service.dart';
import 'services/session_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/ar_exercise_screen.dart';
import 'screens/tremor_monitor_screen.dart';
import 'screens/vr_hand_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
  ));

  // Start SocketIO connection
  SocketService().connect();

  runApp(
    ChangeNotifierProvider(
      create: (_) => SessionService(),
      child: const RehabNetApp(),
    ),
  );
}

class RehabNetApp extends StatelessWidget {
  const RehabNetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RehabNet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C896),
          brightness: Brightness.dark,
          background: const Color(0xFF0A0E1A),
          surface: const Color(0xFF131929),
        ),
        fontFamily: 'Inter',
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1221),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF0D1221),
          selectedItemColor: Color(0xFF00C896),
          unselectedItemColor: Color(0xFF4A5568),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
      ),
      home: const _MainShell(),
    );
  }
}

// ── Main shell with bottom navigation ──────────────────────────────────────
class _MainShell extends StatefulWidget {
  const _MainShell();
  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _idx = 0;

  static const _tabs = [
    _TabItem(icon: Icons.dashboard_rounded,       label: 'Dashboard'),
    _TabItem(icon: Icons.camera_enhance_rounded,  label: 'AR Exercise'),
    _TabItem(icon: Icons.vibration_rounded,        label: 'Tremor'),
    _TabItem(icon: Icons.view_in_ar_rounded,       label: 'VR Mode'),
  ];

  // Use IndexedStack so screens preserve state when switching tabs
  final _screens = const [
    DashboardScreen(),
    _ARWrapper(),
    TremorMonitorScreen(),
    _VRWrapper(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _idx, children: _screens),
      bottomNavigationBar: _buildNav(),
    );
  }

  Widget _buildNav() {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: const Color(0xFF1E2840), width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: _idx,
        onTap: (i) => setState(() => _idx = i),
        items: _tabs.map((t) => BottomNavigationBarItem(
              icon: Icon(t.icon),
              label: t.label,
            )).toList(),
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final String label;
  const _TabItem({required this.icon, required this.label});
}

// AR and VR pushed as full-screen routes from shell buttons
class _ARWrapper extends StatelessWidget {
  const _ARWrapper();
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_enhance_rounded, color: Color(0xFF00C896), size: 72),
              const SizedBox(height: 24),
              const Text('AR Exercise Mode',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
              const SizedBox(height: 8),
              const Text('Arm raise rehabilitation with skeleton tracking',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF8892A4), fontFamily: 'Inter')),
              const SizedBox(height: 36),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const ArExerciseScreen())),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start Exercise', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C896),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      );
}

class _VRWrapper extends StatelessWidget {
  const _VRWrapper();
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.view_in_ar_rounded, color: Color(0xFF4FC3F7), size: 72),
              const SizedBox(height: 24),
              const Text('VR Hand Interaction',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
              const SizedBox(height: 8),
              const Text('Catch the approaching targets in \n3D space using your hand coordinates',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF8892A4), fontFamily: 'Inter')),
              const SizedBox(height: 36),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const VrHandScreen())),
                icon: const Icon(Icons.back_hand_rounded),
                label: const Text('Enter VR Mode', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4FC3F7),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      );
}
