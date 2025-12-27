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

  // Multi-step selection state
  String? _selectedCorridor; // Step 1: Selected street name
  String? _selectedBlock; // Step 2: Selected block (limits)
  String? _selectedSide; // Step 3: Selected side

  /// Get unique corridors from schedules, preserving order (closest first from API)
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

  /// Get unique blocks (limits) for the selected corridor, preserving order
  List<String> get _blocksForSelectedCorridor {
    if (_scheduleResponse == null || _selectedCorridor == null) return [];
    final seen = <String>{};
    final blocks = <String>[];
    for (final entry in _scheduleResponse!.schedules) {
      if (entry.corridor == _selectedCorridor && seen.add(entry.limits)) {
        blocks.add(entry.limits);
      }
    }
    return blocks;
  }

  /// Get unique sides for the selected corridor and block
  List<String?> get _sidesForSelectedBlock {
    if (_scheduleResponse == null ||
        _selectedCorridor == null ||
        _selectedBlock == null) {
      return [];
    }
    final sides = <String?>[];
    for (final entry in _scheduleResponse!.schedules) {
      if (entry.corridor == _selectedCorridor &&
          entry.limits == _selectedBlock) {
        if (!sides.contains(entry.blockSide)) {
          sides.add(entry.blockSide);
        }
      }
    }
    return sides;
  }

  /// Get the closest distance for a given corridor (minimum across all its schedules)
  String? _closestDistanceForCorridor(String corridor) {
    if (_scheduleResponse == null) return null;
    String? closestDistance;
    double? closestMeters;
    for (final entry in _scheduleResponse!.schedules) {
      if (entry.corridor == corridor && entry.distance != null) {
        final meters = _parseDistanceToMeters(entry.distance!);
        if (meters != null &&
            (closestMeters == null || meters < closestMeters)) {
          closestMeters = meters;
          closestDistance = entry.distance;
        }
      }
    }
    return closestDistance;
  }

  /// Get the closest distance for a given block within the selected corridor
  String? _closestDistanceForBlock(String block) {
    if (_scheduleResponse == null || _selectedCorridor == null) return null;
    String? closestDistance;
    double? closestMeters;
    for (final entry in _scheduleResponse!.schedules) {
      if (entry.corridor == _selectedCorridor &&
          entry.limits == block &&
          entry.distance != null) {
        final meters = _parseDistanceToMeters(entry.distance!);
        if (meters != null &&
            (closestMeters == null || meters < closestMeters)) {
          closestMeters = meters;
          closestDistance = entry.distance;
        }
      }
    }
    return closestDistance;
  }

  /// Parse a distance string like "50 ft" or "0.3 mi" to meters for comparison
  double? _parseDistanceToMeters(String distance) {
    final parts = distance.split(' ');
    if (parts.length != 2) return null;
    final value = double.tryParse(parts[0]);
    if (value == null) return null;
    final unit = parts[1].toLowerCase();
    if (unit == 'ft') {
      return value * 0.3048; // feet to meters
    } else if (unit == 'mi') {
      return value * 1609.34; // miles to meters
    }
    return null;
  }

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

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

      // Auto-select if only one option available
      String? autoSelectedCorridor;
      String? autoSelectedBlock;

      // Get unique corridors
      final corridorSet = <String>{};
      for (final entry in response.schedules) {
        corridorSet.add(entry.corridor);
      }

      // Auto-select corridor if only one
      if (corridorSet.length == 1) {
        autoSelectedCorridor = corridorSet.first;

        // Get unique blocks for that corridor
        final blockSet = <String>{};
        for (final entry in response.schedules) {
          if (entry.corridor == autoSelectedCorridor) {
            blockSet.add(entry.limits);
          }
        }

        // Auto-select block if only one
        if (blockSet.length == 1) {
          autoSelectedBlock = blockSet.first;
        }
      }

      setState(() {
        _scheduleResponse = response;
        _selectedCorridor = autoSelectedCorridor;
        _selectedBlock = autoSelectedBlock;
        _selectedSide = null;
        _statusMessage = null;
        _statusType = null;
        _isLoading = false;
      });

      // Trigger animation
      _fadeController.forward(from: 0);
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
    return Column(
      children: [
        FrostedCard(
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
                if (_statusType == StatusType.error &&
                    _statusMessage != null) ...[
                  const SizedBox(height: 20),
                  StatusBanner(
                    message: _statusMessage!,
                    type: _statusType!,
                  ),
                ],
                if (_scheduleResponse != null) ...[
                  _buildResultSection(),
                ],
              ],
            ),
          ),
        ),
        // Second frosted card for block and side selection
        if (_scheduleResponse != null && _selectedCorridor != null) ...[
          const SizedBox(height: 16),
          _buildBlockAndSideCard(),
        ],
      ],
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

    // Handle empty schedules
    if (_scheduleResponse!.schedules.isEmpty) {
      return FadeTransition(
        opacity: _fadeAnimation,
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
      );
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          // Step 1: Corridor selection
          _buildCorridorSelectionCard(corridors),
        ],
      ),
    );
  }

  /// Build the second frosted card for block and side selection
  Widget _buildBlockAndSideCard() {
    if (_selectedCorridor == null) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: FrostedCard(
        key: ValueKey('block_side_card_$_selectedCorridor'),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Step 2: Block selection
              _buildBlockSelectionCard(),
              // Step 3: Side selection and schedule card (only shown after block is selected)
              if (_selectedBlock != null) ...[
                const SizedBox(height: 24),
                _buildSideSelectionAndSchedule(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Generic selection section builder for corridors and blocks
  Widget _buildSelectionSection({
    required String title,
    String? subtitle,
    required List<String> options,
    required String? selectedOption,
    required String? Function(String) getDistance,
    required void Function(String) onSelect,
  }) {
    if (options.isEmpty) return const SizedBox.shrink();

    final hasMultipleOptions = options.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textMuted,
                ),
          ),
        ],
        const SizedBox(height: 12),
        ...options.asMap().entries.map((entry) {
          final index = entry.key;
          final option = entry.value;
          final isClosest = index == 0;
          return _buildSelectionOption(
            label: option,
            isSelected: selectedOption == option,
            isClosest: isClosest,
            showBadge: isClosest && hasMultipleOptions,
            distance: getDistance(option),
            onTap: () => onSelect(option),
          );
        }),
      ],
    );
  }

  /// Generic selection option builder
  Widget _buildSelectionOption({
    required String label,
    required bool isSelected,
    required bool isClosest,
    required bool showBadge,
    required String? distance,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryColor
                  : AppTheme.border.withValues(alpha: 0.3),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? AppTheme.primaryColor.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.06),
                blurRadius: isSelected ? 12 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: isClosest ? 12 : 6,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppTheme.textPrimary,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (distance != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      distance,
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.8)
                            : AppTheme.textMuted,
                      ),
                    ),
                  ),
                if (isClosest && showBadge)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.2)
                          : AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'CLOSEST',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color:
                            isSelected ? Colors.white : AppTheme.primaryColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Step 1: Corridor selection
  Widget _buildCorridorSelectionCard(List<String> corridors) {
    return _buildSelectionSection(
      title: 'Which street are you parked on?',
      options: corridors,
      selectedOption: _selectedCorridor,
      getDistance: _closestDistanceForCorridor,
      onSelect: (corridor) {
        // Check if there's only one block for this corridor
        String? autoSelectedBlock;
        final blockSet = <String>{};
        for (final e in _scheduleResponse!.schedules) {
          if (e.corridor == corridor) {
            blockSet.add(e.limits);
          }
        }
        if (blockSet.length == 1) {
          autoSelectedBlock = blockSet.first;
        }

        setState(() {
          _selectedCorridor = corridor;
          _selectedBlock = autoSelectedBlock;
          _selectedSide = null;
        });
      },
    );
  }

  /// Step 2: Block selection
  Widget _buildBlockSelectionCard() {
    return _buildSelectionSection(
      title: 'Which block?',
      subtitle: _selectedCorridor,
      options: _blocksForSelectedCorridor,
      selectedOption: _selectedBlock,
      getDistance: _closestDistanceForBlock,
      onSelect: (block) {
        setState(() {
          _selectedBlock = block;
          _selectedSide = null;
        });
      },
    );
  }

  /// Step 3: Side selection and schedule display
  Widget _buildSideSelectionAndSchedule() {
    final sides = _sidesForSelectedBlock;

    // Auto-select first side if not already selected
    final effectiveSide =
        _selectedSide ?? (sides.isNotEmpty ? sides.first : null);

    // Get the schedule entry for the effective side
    ScheduleEntry? entry;
    if (_scheduleResponse != null &&
        _selectedCorridor != null &&
        _selectedBlock != null) {
      for (final e in _scheduleResponse!.schedules) {
        if (e.corridor == _selectedCorridor && e.limits == _selectedBlock) {
          if (sides.length <= 1) {
            entry = e;
            break;
          } else if (e.blockSide == effectiveSide) {
            entry = e;
            break;
          }
        }
      }
    }

    if (entry == null) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: ScheduleCard(
        key: ValueKey('schedule_${_selectedBlock}_$effectiveSide'),
        scheduleEntry: entry,
        timezone: _scheduleResponse!.timezone,
        requestPoint: _scheduleResponse!.requestPoint,
        sides: sides.length > 1 ? sides : null,
        selectedSide: effectiveSide,
        onSideChanged: sides.length > 1
            ? (side) {
                setState(() {
                  _selectedSide = side;
                });
              }
            : null,
      ),
    );
  }
}
