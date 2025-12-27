import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schedule_response.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import '../widgets/frosted_card.dart';
import '../widgets/schedule_card.dart';
import '../widgets/status_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final LocationService _locationService = LocationService();

  ScheduleResponse? _scheduleResponse;
  String? _statusMessage;
  StatusType? _statusType;
  bool _isLoading = false;
  int _selectedCorridorIndex = 0;
  int _selectedSideIndex = 0;

  /// Get unique corridors from schedules, preserving order of first appearance
  List<String> get _corridors {
    if (_scheduleResponse == null) return [];
    final seen = <String>{};
    final corridors = <String>[];
    for (final entry in _scheduleResponse!.schedules) {
      final corridor = entry.corridor;
      if (seen.add(corridor)) {
        corridors.add(corridor);
      }
    }
    return corridors;
  }

  /// Get schedules for the currently selected corridor, sorted alphabetically
  List<ScheduleEntry> get _schedulesForSelectedCorridor {
    if (_scheduleResponse == null || _corridors.isEmpty) return [];
    final selectedCorridor = _corridors[_selectedCorridorIndex];
    final schedules = _scheduleResponse!.schedules
        .where((e) => e.corridor == selectedCorridor)
        .toList();
    schedules.sort((a, b) {
      final aLabel =
          a.blockSide != null ? '${a.limits} (${a.blockSide} Side)' : a.limits;
      final bLabel =
          b.blockSide != null ? '${b.limits} (${b.blockSide} Side)' : b.limits;
      return aLabel.compareTo(bLabel);
    });
    return schedules;
  }

  /// Get the currently selected schedule entry
  ScheduleEntry? get _selectedScheduleEntry {
    final schedules = _schedulesForSelectedCorridor;
    if (schedules.isEmpty) return null;
    return schedules[_selectedSideIndex.clamp(0, schedules.length - 1)];
  }

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Slide animation for result card
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    // Fade animation
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _requestLocation() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _statusType = null;
      _scheduleResponse = null;
    });

    try {
      final position = await _locationService.getCurrentLocation();
      await _lookupSchedule(position.latitude, position.longitude);
    } catch (e) {
      setState(() {
        _statusMessage = e.toString();
        _statusType = StatusType.error;
        _isLoading = false;
      });
    }
  }

  Future<void> _lookupSchedule(double latitude, double longitude) async {
    try {
      final apiService = context.read<ApiService>();
      final response = await apiService.checkLocation(latitude, longitude);

      // Extract unique corridors for debugging
      final corridorSet = <String>{};
      for (final entry in response.schedules) {
        corridorSet.add(entry.corridor);
      }

      setState(() {
        _scheduleResponse = response;
        _selectedCorridorIndex = 0;
        _selectedSideIndex = 0;
        _statusMessage = null;
        _statusType = null;
        _isLoading = false;
      });

      // Trigger animations
      _fadeController.forward(from: 0);
      _slideController.forward(from: 0);
    } catch (e) {
      setState(() {
        _statusMessage = e.toString();
        _statusType = StatusType.error;
        _isLoading = false;
        _scheduleResponse = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SelectionArea(
        child: Container(
          // Ensure gradient fills the entire screen
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height,
          ),
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.7, -0.8),
              radius: 1.2,
              colors: [
                Color(0xFFFEF3C7), // warm streetlight glow
                AppTheme.background,
              ],
            ),
          ),
          child: Stack(
            children: [
              // Subtle ambient glow effect
              Positioned(
                top: -100,
                right: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppTheme.accent.withValues(alpha: 0.1),
                        AppTheme.accent.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.screenPadding),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            maxWidth: AppTheme.maxContentWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(),
                            const SizedBox(height: 32),
                            _buildMainCard(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SWEEP DREAMS',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Move your car before the next street sweep',
          style: Theme.of(context).textTheme.displayMedium,
        ),
      ],
    );
  }

  Widget _buildMainCard() {
    return FrostedCard(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLocationButton(),
            const SizedBox(height: 12),
            Text(
              'Your location is only used to find nearby schedules.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_statusType == StatusType.error && _statusMessage != null) ...[
              const SizedBox(height: 20),
              StatusBanner(
                message: _statusMessage!,
                type: _statusType!,
              ),
            ],
            if (_scheduleResponse != null) ...[
              // const SizedBox(height: 24),
              _buildResultSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocationButton() {
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _requestLocation,
      icon: _isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.my_location),
      label: Text(_isLoading ? 'Locating...' : 'Use my location'),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    );
  }

  Widget _buildResultSection() {
    final corridors = _corridors;
    final schedulesForCorridor = _schedulesForSelectedCorridor;

    // Handle empty schedules
    if (_scheduleResponse!.schedules.isEmpty) {
      return FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Container(
            margin: const EdgeInsets.only(top: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.border.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: AppTheme.primaryColor.withValues(alpha: 0.7),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No sweeping schedules found. This app only works in San Francisco!',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textMuted,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text(
              'Nearby streets',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            // Corridor tabs (shown as prominent pills)
            _buildCorridorTabs(corridors),
            const SizedBox(height: 8),
            // Schedule tabs within selected corridor (if multiple)
            if (schedulesForCorridor.length > 1)
              _buildScheduleTabs(schedulesForCorridor),
            const SizedBox(height: 16),
            _buildScheduleCards(),
          ],
        ),
      ),
    );
  }

  Widget _buildCorridorTabs(List<String> corridors) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(corridors.length, (index) {
        final corridor = corridors[index];
        final isSelected = _selectedCorridorIndex == index;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedCorridorIndex = index;
              _selectedSideIndex =
                  0; // Reset side selection when corridor changes
            });
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isSelected
                    ? [
                        AppTheme.primaryColor,
                        AppTheme.primaryColor.withValues(alpha: 0.85)
                      ]
                    : [
                        AppTheme.primarySoft,
                        AppTheme.primarySoft.withValues(alpha: 0.85)
                      ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? AppTheme.primaryColor
                    : AppTheme.border.withValues(alpha: 0.8),
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? AppTheme.primaryColor.withValues(alpha: 0.5)
                      : AppTheme.primaryColor.withValues(alpha: 0.15),
                  blurRadius: isSelected ? 12 : 6,
                  offset: const Offset(0, 4),
                ),
                // Subtle inner highlight for 3D effect
                BoxShadow(
                  color: Colors.white.withValues(alpha: isSelected ? 0.1 : 0.5),
                  blurRadius: 0,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    color: isSelected ? Colors.white : AppTheme.primaryColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    corridor,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : AppTheme.primaryColor,
                      fontSize: 16,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildScheduleTabs(List<ScheduleEntry> schedules) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(schedules.length, (index) {
        final schedule = schedules[index];
        final isSelected = _selectedSideIndex == index;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedSideIndex = index;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isSelected
                    ? [
                        AppTheme.primaryColor,
                        AppTheme.primaryColor.withValues(alpha: 0.85)
                      ]
                    : [
                        AppTheme.primarySoft,
                        AppTheme.primarySoft.withValues(alpha: 0.85)
                      ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? AppTheme.primaryColor
                    : AppTheme.border.withValues(alpha: 0.8),
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? AppTheme.primaryColor.withValues(alpha: 0.5)
                      : AppTheme.primaryColor.withValues(alpha: 0.15),
                  blurRadius: isSelected ? 10 : 5,
                  offset: const Offset(0, 3),
                ),
                // Subtle inner highlight for 3D effect
                BoxShadow(
                  color: Colors.white.withValues(alpha: isSelected ? 0.1 : 0.5),
                  blurRadius: 0,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                schedule.blockSide != null
                    ? '${schedule.limits} (${schedule.blockSide} Side)'
                    : schedule.limits,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white : AppTheme.primaryColor,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildScheduleCards() {
    final selectedEntry = _selectedScheduleEntry;

    if (selectedEntry == null) {
      return const SizedBox.shrink();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.1, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: ScheduleCard(
        key: ValueKey('${_selectedCorridorIndex}_$_selectedSideIndex'),
        scheduleEntry: selectedEntry,
        timezone: _scheduleResponse!.timezone,
        requestPoint: _scheduleResponse!.requestPoint,
      ),
    );
  }
}
