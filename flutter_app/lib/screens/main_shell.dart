import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../widgets/editorial_background.dart';
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
      body: EditorialBackground(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            const HomeScreen(),
            AlertsScreen(key: _alertsKey),
          ],
        ),
      ),
      bottomNavigationBar: Stack(
        clipBehavior: Clip.none,
        children: [
          // Base opaque background (full bar height)
          Container(
            color: AppTheme.surface,
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
                      icon: 'assets/icons/home-alt-svgrepo-com.svg',
                      label: 'Home',
                    ),
                    _buildSvgNavItem(
                      index: 1,
                      icon: 'assets/icons/alarm-svgrepo-com.svg',
                      label: 'Alerts',
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Top gradient overlay extending above the bar
          Positioned(
            top: -64,
            left: 0,
            right: 0,
            height: 64,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.surface.withValues(alpha: 0),
                    AppTheme.surface,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSvgNavItem({
    required int index,
    required String icon,
    required String label,
    double iconSize = 32,
  }) {
    final isSelected = _selectedIndex == index;
    final color =
        isSelected ? Theme.of(context).colorScheme.primary : AppTheme.textMuted;

    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 6, bottom: 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: iconSize,
              height: iconSize,
              child: Stack(
                children: [
                  // Filled icon (bottom layer)
                  SvgPicture.asset(
                    icon,
                    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                    width: iconSize,
                    height: iconSize,
                  ),
                  // Outline only at 100% opacity (top layer)
                  SvgPicture.asset(
                    icon.replaceAll('.svg', '-empty.svg'),
                    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                    width: iconSize,
                    height: iconSize,
                  ),
                ],
              ),
            ),
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
