import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'alerts_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  final GlobalKey<AlertsScreenState> _alertsKey =
      GlobalKey<AlertsScreenState>();

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Refresh alerts when switching to the Alerts tab
    if (index == 1) {
      _alertsKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          const HomeScreen(),
          AlertsScreen(key: _alertsKey),
        ],
      ),
      bottomNavigationBar: Container(
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSvgNavItem(
                  index: 0,
                  icon: 'assets/icons/home-20-svgrepo-com.svg',
                  selectedIcon: 'assets/icons/home-20-svgrepo-com-filled.svg',
                  label: 'Home',
                ),
                _buildSvgNavItem(
                  index: 1,
                  icon: 'assets/icons/notification-svgrepo-com.svg',
                  selectedIcon:
                      'assets/icons/notification-svgrepo-com-filled.svg',
                  label: 'Alerts',
                  iconSize: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSvgNavItem({
    required int index,
    required String icon,
    required String selectedIcon,
    required String label,
    double iconSize = 28,
  }) {
    final isSelected = _selectedIndex == index;
    final color = isSelected ? AppTheme.primaryColor : AppTheme.textMuted;

    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 10, bottom: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Center(
                child: SvgPicture.asset(
                  isSelected ? selectedIcon : icon,
                  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                  width: iconSize,
                  height: iconSize,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
