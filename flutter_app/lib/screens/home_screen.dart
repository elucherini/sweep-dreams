import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schedule_response.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
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
  String _statusMessage = 'Ready to check your block.';
  StatusType _statusType = StatusType.info;
  bool _isLoading = false;
  int _selectedScheduleIndex = 0;

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
      _statusMessage = 'Requesting your location...';
      _statusType = StatusType.info;
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
    setState(() {
      _statusMessage = 'Looking up your block...';
      _statusType = StatusType.info;
    });

    try {
      final apiService = context.read<ApiService>();
      final response = await apiService.checkLocation(latitude, longitude);
      
      setState(() {
        _scheduleResponse = response;
        _selectedScheduleIndex = 0;
        _statusMessage = 'Found a sweeping schedule for your location.';
        _statusType = StatusType.success;
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

  String _formatCoordinates(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SelectionArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.7, -0.8),
              radius: 1.2,
              colors: [
                const Color(0xFFFEF3C7), // warm streetlight glow
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
                        AppTheme.accent.withOpacity(0.1),
                        AppTheme.accent.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
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
    return Card(
      elevation: 20,
      shadowColor: AppTheme.primaryColor.withValues(alpha: 0.15),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.border.withOpacity(0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withOpacity(0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLocationButton(),
              const SizedBox(height: 12),
              Text(
                'Location stays on this page and is only sent to the backend for the lookup.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              StatusBanner(
                message: _statusMessage,
                type: _statusType,
              ),
              if (_scheduleResponse != null) ...[
                const SizedBox(height: 24),
                _buildResultSection(),
              ],
            ],
          ),
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
    final response = _scheduleResponse!;
    
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 32, thickness: 1),
            Text(
              'Next sweep',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Coordinates: ${_formatCoordinates(
                response.requestPoint.latitude,
                response.requestPoint.longitude,
              )}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 20),
            if (response.schedules.length > 1) _buildScheduleTabs(),
            const SizedBox(height: 16),
            _buildScheduleCards(),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleTabs() {
    final schedules = _scheduleResponse!.schedules;
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(schedules.length, (index) {
        final schedule = schedules[index].schedule;
        final isSelected = _selectedScheduleIndex == index;
        
        return ChoiceChip(
          label: Text(
            schedule.label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : AppTheme.primaryColor,
            ),
          ),
          selected: isSelected,
          showCheckmark: false,
          onSelected: (selected) {
            if (selected) {
              setState(() {
                _selectedScheduleIndex = index;
              });
            }
          },
          selectedColor: AppTheme.primaryColor,
          backgroundColor: AppTheme.primarySoft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isSelected ? AppTheme.primaryColor : AppTheme.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          elevation: isSelected ? 10 : 2,
          shadowColor: AppTheme.primaryColor.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        );
      }),
    );
  }

  Widget _buildScheduleCards() {
    final schedules = _scheduleResponse!.schedules;
    final selectedEntry = schedules[_selectedScheduleIndex];
    
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
        key: ValueKey(_selectedScheduleIndex),
        scheduleEntry: selectedEntry,
        timezone: _scheduleResponse!.timezone,
      ),
    );
  }
}

