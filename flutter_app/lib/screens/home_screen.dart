import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schedule_response.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import 'location_page.dart';
import 'street_selection_page.dart';
import 'block_selection_page.dart';
import 'side_selection_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LocationService _locationService = LocationService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  ScheduleResponse? _scheduleResponse;
  String? _errorMessage;
  bool _isLoading = false;

  // Selection state
  String? _selectedCorridor;
  String? _selectedBlock;

  Future<void> _requestLocation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _scheduleResponse = null;
      _selectedCorridor = null;
      _selectedBlock = null;
    });

    try {
      final position = await _locationService.getCurrentLocation();
      await _lookupSchedule(position.latitude, position.longitude);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _lookupSchedule(double latitude, double longitude) async {
    try {
      final apiService = context.read<ApiService>();
      final response = await apiService.checkLocation(latitude, longitude);

      setState(() {
        _scheduleResponse = response;
        _errorMessage = null;
        _isLoading = false;
      });

      // Navigate to street selection if we have schedules
      if (response.schedules.isNotEmpty) {
        // Check if there's only one corridor
        final corridorSet = <String>{};
        for (final entry in response.schedules) {
          corridorSet.add(entry.corridor);
        }

        if (corridorSet.length == 1) {
          // Auto-select the single corridor
          final corridor = corridorSet.first;
          _selectedCorridor = corridor;

          // Check if there's only one block
          final blockSet = <String>{};
          for (final entry in response.schedules) {
            if (entry.corridor == corridor) {
              blockSet.add(entry.limits);
            }
          }

          if (blockSet.length == 1) {
            // Auto-select the single block and go directly to side selection
            _selectedBlock = blockSet.first;
            _navigatorKey.currentState?.pushNamed('/side');
          } else {
            // Multiple blocks, go to block selection
            _navigatorKey.currentState?.pushNamed('/block');
          }
        } else {
          // Multiple corridors, go to street selection
          _navigatorKey.currentState?.pushNamed('/street');
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
        _scheduleResponse = null;
      });
    }
  }

  void _onCorridorSelected(String corridor) {
    setState(() {
      _selectedCorridor = corridor;
      _selectedBlock = null;
    });

    // Check if there's only one block for this corridor
    final blockSet = <String>{};
    for (final entry in _scheduleResponse!.schedules) {
      if (entry.corridor == corridor) {
        blockSet.add(entry.limits);
      }
    }

    if (blockSet.length == 1) {
      // Auto-select the single block and go to side selection
      setState(() {
        _selectedBlock = blockSet.first;
      });
      _navigatorKey.currentState?.pushNamed('/side');
    } else {
      // Multiple blocks, go to block selection
      _navigatorKey.currentState?.pushNamed('/block');
    }
  }

  void _onBlockSelected(String block) {
    setState(() {
      _selectedBlock = block;
    });
    _navigatorKey.currentState?.pushNamed('/side');
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: SafeArea(
        child: Navigator(
          key: _navigatorKey,
          initialRoute: '/',
          onGenerateRoute: (settings) {
            Widget page;
            switch (settings.name) {
              case '/':
                page = LocationPage(
                  isLoading: _isLoading,
                  errorMessage: _errorMessage,
                  onRequestLocation: _requestLocation,
                );
                break;
              case '/street':
                page = StreetSelectionPage(
                  scheduleResponse: _scheduleResponse!,
                  onCorridorSelected: _onCorridorSelected,
                  onBack: () => _navigatorKey.currentState?.pop(),
                );
                break;
              case '/block':
                page = BlockSelectionPage(
                  scheduleResponse: _scheduleResponse!,
                  selectedCorridor: _selectedCorridor!,
                  onBlockSelected: _onBlockSelected,
                  onBack: () => _navigatorKey.currentState?.pop(),
                );
                break;
              case '/side':
                page = SideSelectionPage(
                  scheduleResponse: _scheduleResponse!,
                  selectedCorridor: _selectedCorridor!,
                  selectedBlock: _selectedBlock!,
                  onBack: () => _navigatorKey.currentState?.pop(),
                );
                break;
              default:
                page = LocationPage(
                  isLoading: _isLoading,
                  errorMessage: _errorMessage,
                  onRequestLocation: _requestLocation,
                );
            }
            return PageRouteBuilder(
              settings: settings,
              pageBuilder: (context, animation, secondaryAnimation) => page,
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                const curve = Curves.easeInOut;

                // Incoming page slides in from right
                final incomingTween = Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
                    .chain(CurveTween(curve: curve));

                // Outgoing page slides out to left
                final outgoingTween = Tween(begin: Offset.zero, end: const Offset(-1.0, 0.0))
                    .chain(CurveTween(curve: curve));

                return SlideTransition(
                  position: secondaryAnimation.drive(outgoingTween),
                  child: SlideTransition(
                    position: animation.drive(incomingTween),
                    child: child,
                  ),
                );
              },
              transitionDuration: const Duration(milliseconds: 250),
            );
          },
        ),
      ),
    );
  }
}
