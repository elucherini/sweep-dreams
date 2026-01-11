import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../models/parking_response.dart';
import '../models/puck_response.dart';
import '../models/schedule_response.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/subscription_state.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import '../widgets/parking_regulation_card.dart';
import '../widgets/schedule_card.dart';
import '../widgets/status_banner.dart';
import '../widgets/time_until_badge.dart';
import 'alerts_screen.dart';

class MapHomeScreen extends StatefulWidget {
  const MapHomeScreen({super.key});

  @override
  State<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends State<MapHomeScreen> {
  static const double _defaultZoom = 16.5;
  static const double _minLookupMoveMeters = 20.0;
  static const double _sheetPeekMinSize = 0.22;
  static const double _sheetPeekInitialSize = 0.24;
  static const double _overlayMargin = 12.0;

  static const _lineSourceId = 'puck-line';
  static const _lineLayerId = 'puck-line-layer';
  static const _regLineSourceId = 'regulation-line';
  static const _regLineLayerId = 'regulation-line-layer';
  static const double _lineOffset = 5.0;

  final LocationService _locationService = LocationService();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  MapboxMap? _mapboxMap;
  bool _styleLoaded = false;
  bool _lineLayersReady = false;

  int _lookupSeq = 0;

  bool _locating = true;
  bool _loadingResults = false;
  String? _errorMessage;

  RequestPoint? _lastLookupPoint;
  RequestPoint? _puckPoint;
  RequestPoint? _userPoint;

  ScheduleEntry? _schedule;
  ParkingRegulation? _regulation;
  String _timezone = 'America/Los_Angeles';

  // Line overlay visibility toggles (controlled by badge taps)
  bool _scheduleLineVisible = true;
  bool _regulationLineVisible = true;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      final position = await _locationService.getCurrentLocation();
      if (!mounted) return;

      final point = RequestPoint(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      setState(() {
        _locating = false;
        _userPoint = point;
        _puckPoint = point;
        _errorMessage = null;
      });

      await _moveCameraTo(point, animated: false);
      await _lookupAt(point);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _recenterToUser() async {
    if (mounted) {
      setState(() {
        _locating = true;
        _errorMessage = null;
      });
    }

    try {
      final position = await _locationService.getCurrentLocation();
      if (!mounted) return;

      final point = RequestPoint(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      setState(() {
        _locating = false;
        _userPoint = point;
        _puckPoint = point;
      });

      await _moveCameraTo(point, animated: true);
      await _lookupAt(point);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _moveCameraTo(RequestPoint point,
      {required bool animated}) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final camera = CameraOptions(
      center: Point(coordinates: Position(point.longitude, point.latitude)),
      zoom: _defaultZoom,
    );

    if (!animated) {
      await mapboxMap.setCamera(camera);
      return;
    }

    await mapboxMap.flyTo(
      camera,
      MapAnimationOptions(duration: 600),
    );
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    mapboxMap.scaleBar.updateSettings(ScaleBarSettings(enabled: false));

    final puck = _puckPoint;
    if (puck != null) {
      _moveCameraTo(puck, animated: false);
    }
  }

  void _onStyleLoaded(StyleLoadedEventData eventData) async {
    _styleLoaded = true;
    _lineLayersReady = false;
    await _ensureLineLayers();
    await _updateLineLayer(scheduleEntry: _schedule, regulation: _regulation);

    final puck = _puckPoint;
    if (puck != null) {
      await _moveCameraTo(puck, animated: false);
    }
  }

  void _onCameraChanged(CameraChangedEventData eventData) {
    // Intentionally no network lookups here. We fetch only once the map is idle.
  }

  Future<void> _onMapIdle(MapIdleEventData eventData) async {
    final center = await _getCameraCenter();
    if (center == null) return;

    final point = RequestPoint(
      latitude: center.lat.toDouble(),
      longitude: center.lng.toDouble(),
    );
    if (!mounted) return;

    setState(() {
      _puckPoint = point;
    });

    await _lookupAt(point);
  }

  Future<Position?> _getCameraCenter() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return null;
    final state = await mapboxMap.getCameraState();
    return state.center.coordinates;
  }

  bool _shouldLookup(RequestPoint next) {
    final prev = _lastLookupPoint;
    if (prev == null) return true;

    final meters = geo.Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      next.latitude,
      next.longitude,
    );
    return meters >= _minLookupMoveMeters;
  }

  Future<void> _lookupAt(RequestPoint point) async {
    if (!_shouldLookup(point)) return;

    final seq = ++_lookupSeq;
    _lastLookupPoint = point;

    if (mounted) {
      setState(() {
        _loadingResults = true;
        _errorMessage = null;
      });
    }

    final api = context.read<ApiService>();

    PuckResponse? puck;
    Object? puckError;
    try {
      puck = await api.checkPuck(point.latitude, point.longitude);
    } catch (e) {
      puckError = e;
    }

    if (!mounted || seq != _lookupSeq) return;

    if (puckError != null || puck == null) {
      setState(() {
        _schedule = null;
        _regulation = null;
        _timezone = 'America/Los_Angeles';
        _loadingResults = false;
        _errorMessage = 'Failed to fetch schedules and parking regulations.';
      });
      await _updateLineLayer(scheduleEntry: null, regulation: null);
      return;
    }

    final response = puck;
    final errors = response.errors;
    final showErrorBanner = response.schedule == null &&
        response.regulation == null &&
        errors?.schedule != null &&
        errors?.regulation != null;

    setState(() {
      _schedule = response.schedule;
      _regulation = response.regulation;
      _timezone = response.timezone;
      _loadingResults = false;
      _errorMessage = showErrorBanner
          ? 'Failed to fetch schedules and parking regulations.'
          : null;
    });

    await _updateLineLayer(
      scheduleEntry: response.schedule,
      regulation: response.regulation,
    );
  }

  double _getOffsetForSide(String cnnRightLeft) {
    return cnnRightLeft == 'R' ? _lineOffset : -_lineOffset;
  }

  void _toggleScheduleLineVisibility() {
    setState(() {
      _scheduleLineVisible = !_scheduleLineVisible;
    });
    _updateLineLayer(scheduleEntry: _schedule, regulation: _regulation);
  }

  void _toggleRegulationLineVisibility() {
    setState(() {
      _regulationLineVisible = !_regulationLineVisible;
    });
    _updateLineLayer(scheduleEntry: _schedule, regulation: _regulation);
  }

  Future<void> _updateLineLayer({
    required ScheduleEntry? scheduleEntry,
    required ParkingRegulation? regulation,
  }) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null || !_styleLoaded) return;

    await _ensureLineLayers();

    // Update schedule line
    final scheduleGeometry = scheduleEntry?.geometry;
    final hasScheduleGeometry =
        scheduleGeometry != null && scheduleGeometry['type'] != null;

    final scheduleGeoJson = jsonEncode({
      'type': 'FeatureCollection',
      'features': hasScheduleGeometry
          ? [
              {'type': 'Feature', 'geometry': scheduleGeometry}
            ]
          : [],
    });

    final scheduleSource = await mapboxMap.style.getSource(_lineSourceId);
    if (scheduleSource is GeoJsonSource) {
      await scheduleSource.updateGeoJSON(scheduleGeoJson);
    }

    // Update regulation line
    final regLine = regulation?.line;
    final hasRegGeometry = regLine != null && regLine['type'] != null;

    final regGeoJson = jsonEncode({
      'type': 'FeatureCollection',
      'features': hasRegGeometry
          ? [
              {'type': 'Feature', 'geometry': regLine}
            ]
          : [],
    });

    final regSource = await mapboxMap.style.getSource(_regLineSourceId);
    if (regSource is GeoJsonSource) {
      await regSource.updateGeoJSON(regGeoJson);
    }

    // Handle schedule line visibility
    // Respect _scheduleLineVisible toggle from badge tap
    const lineOpacity = 0.8;
    if (!hasScheduleGeometry || !_scheduleLineVisible) {
      await _setLineOpacity(_lineLayerId, 0.0);
      await _setLineOpacity('$_lineLayerId-left', 0.0);
      await _setLineOpacity('$_lineLayerId-right', 0.0);
    } else {
      final showBothSides =
          scheduleEntry != null && scheduleEntry.blockSide == null;
      if (showBothSides) {
        await _setLineOpacity(_lineLayerId, 0.0);
        await _setLineOpacity('$_lineLayerId-left', lineOpacity);
        await _setLineOpacity('$_lineLayerId-right', lineOpacity);
      } else {
        await _setLineOpacity(_lineLayerId, lineOpacity);
        await _setLineOpacity('$_lineLayerId-left', 0.0);
        await _setLineOpacity('$_lineLayerId-right', 0.0);

        final offset = scheduleEntry?.blockSide != null
            ? _getOffsetForSide(scheduleEntry!.cnnRightLeft)
            : 0.0;
        await _updateLineOffset(offset);
      }
    }

    // Handle regulation line visibility
    // Respect _regulationLineVisible toggle from badge tap
    final showRegLine = hasRegGeometry && _regulationLineVisible;
    await _setLineOpacity(_regLineLayerId, showRegLine ? lineOpacity : 0.0);
  }

  Future<void> _ensureLineLayers() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null || _lineLayersReady) return;

    const emptyGeoJson = '{"type":"FeatureCollection","features":[]}';

    // Schedule line source and layers
    await mapboxMap.style
        .addSource(GeoJsonSource(id: _lineSourceId, data: emptyGeoJson));

    await mapboxMap.style.addLayer(LineLayer(
      id: _lineLayerId,
      sourceId: _lineSourceId,
      lineJoin: LineJoin.MITER,
      lineCap: LineCap.BUTT,
      lineColor: AppTheme.accent.toARGB32(),
      lineWidth: 6.0,
      lineOffset: 0.0,
      lineOpacity: 0.0,
    ));
    await _disableLineOpacityTransition(_lineLayerId);

    await mapboxMap.style.addLayer(LineLayer(
      id: '$_lineLayerId-left',
      sourceId: _lineSourceId,
      lineJoin: LineJoin.MITER,
      lineCap: LineCap.BUTT,
      lineColor: AppTheme.accent.toARGB32(),
      lineWidth: 6.0,
      lineOffset: -_lineOffset,
      lineOpacity: 0.0,
    ));
    await _disableLineOpacityTransition('$_lineLayerId-left');

    await mapboxMap.style.addLayer(LineLayer(
      id: '$_lineLayerId-right',
      sourceId: _lineSourceId,
      lineJoin: LineJoin.MITER,
      lineCap: LineCap.BUTT,
      lineColor: AppTheme.accent.toARGB32(),
      lineWidth: 6.0,
      lineOffset: _lineOffset,
      lineOpacity: 0.0,
    ));
    await _disableLineOpacityTransition('$_lineLayerId-right');

    // Parking regulation line source and layer (different color)
    await mapboxMap.style
        .addSource(GeoJsonSource(id: _regLineSourceId, data: emptyGeoJson));

    await mapboxMap.style.addLayer(LineLayer(
      id: _regLineLayerId,
      sourceId: _regLineSourceId,
      lineJoin: LineJoin.MITER,
      lineCap: LineCap.BUTT,
      lineColor: AppTheme.accentParking.toARGB32(),
      lineWidth: 6.0,
      lineOffset: 0.0,
      lineOpacity: 0.0,
    ));
    await _disableLineOpacityTransition(_regLineLayerId);

    _lineLayersReady = true;
  }

  Future<void> _setLineOpacity(String layerId, double opacity) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;
    await mapboxMap.style.setStyleLayerProperty(
      layerId,
      'line-opacity',
      opacity,
    );
  }

  Future<void> _updateLineOffset(double offset) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    await mapboxMap.style.setStyleLayerProperty(
      _lineLayerId,
      'line-offset',
      offset,
    );
  }

  Future<void> _disableLineOpacityTransition(String layerId) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    await mapboxMap.style.setStyleLayerProperty(
      layerId,
      'line-opacity-transition',
      {'duration': 0, 'delay': 0},
    );
  }

  @override
  Widget build(BuildContext context) {
    final defaultCenter =
        RequestPoint(latitude: 37.7749, longitude: -122.4194); // SF fallback
    final requestPoint = _puckPoint ?? _userPoint ?? defaultCenter;

    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            cameraOptions: CameraOptions(
              center: Point(
                coordinates:
                    Position(defaultCenter.longitude, defaultCenter.latitude),
              ),
              zoom: _defaultZoom,
            ),
            styleUri: MapboxStyles.STANDARD,
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: _onStyleLoaded,
            onMapIdleListener: _onMapIdle,
            onCameraChangeListener: _onCameraChanged,
          ),
          const IgnorePointer(
            child: Center(child: _CenterPuck()),
          ),
          DraggableScrollableSheet(
            // Ensure the collapsed "peek" comfortably fits the segment title +
            // both badges on common phone sizes.
            controller: _sheetController,
            minChildSize: _sheetPeekMinSize,
            initialChildSize: _sheetPeekInitialSize,
            maxChildSize: 0.98,
            builder: (context, controller) {
              return _BottomSheet(
                controller: controller,
                locating: _locating,
                loading: _loadingResults,
                errorMessage: _errorMessage,
                schedule: _schedule,
                regulation: _regulation,
                timezone: _timezone,
                requestPoint: requestPoint,
                scheduleLineVisible: _scheduleLineVisible,
                regulationLineVisible: _regulationLineVisible,
                onToggleScheduleLine: _toggleScheduleLineVisibility,
                onToggleRegulationLine: _toggleRegulationLineVisibility,
              );
            },
          ),
          AnimatedBuilder(
            animation: _sheetController,
            builder: (context, child) {
              final mediaSize = MediaQuery.sizeOf(context);
              final padding = MediaQuery.paddingOf(context);
              final sheetSize = _sheetController.isAttached
                  ? _sheetController.size
                  : _sheetPeekInitialSize;

              // Keep the button above the sheet, but clamp so it never goes off
              // screen when the sheet is nearly fully expanded.
              final desiredBottom =
                  (mediaSize.height * sheetSize) + _overlayMargin;
              final minBottom = padding.bottom + _overlayMargin;
              final maxBottom =
                  mediaSize.height - (padding.top + _overlayMargin) - 40.0;
              final bottom = desiredBottom.clamp(minBottom, maxBottom);

              return Positioned(
                left: _overlayMargin,
                bottom: bottom,
                child: child!,
              );
            },
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              onPressed: _recenterToUser,
              backgroundColor: AppTheme.surface,
              elevation: 3,
              child: const Icon(
                Icons.my_location,
                color: AppTheme.primaryColor,
                size: 20,
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Selector<
                    SubscriptionState,
                    ({
                      int activeAlertsCount,
                      int subscribedCount,
                      bool notificationsAuthorized
                    })>(
                  selector: (_, state) => (
                    activeAlertsCount: state.activeAlertsCount,
                    subscribedCount: state.subscribedCount,
                    notificationsAuthorized: state.notificationsAuthorized,
                  ),
                  builder: (context, data, _) {
                    final active = data.activeAlertsCount;
                    final subscribed = data.subscribedCount;
                    final authorized = data.notificationsAuthorized;

                    final showCount = authorized && active > 0;
                    final showWarning = !authorized && subscribed > 0;

                    final label = showCount
                        ? 'Alerts ($active active)'
                        : showWarning
                            ? 'Alerts (notifications off)'
                            : 'Alerts';

                    return Semantics(
                      button: true,
                      label: label,
                      child: Material(
                        color: AppTheme.surface,
                        shape: const CircleBorder(),
                        elevation: 3,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AlertsScreen(),
                              ),
                            );
                          },
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: SvgPicture.asset(
                                  'assets/icons/alarm-svgrepo-com.svg',
                                  width: 20,
                                  height: 20,
                                  colorFilter: const ColorFilter.mode(
                                    AppTheme.primaryColor,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                              if (showCount || showWarning)
                                Positioned(
                                  top: -3,
                                  right: -3,
                                  child: IgnorePointer(
                                    child: showCount
                                        ? _AlertCountBadge.count(active)
                                        : const _AlertCountBadge(text: '!'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          if (_locating)
            const SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: _LocatingPill(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomSheet extends StatelessWidget {
  final ScrollController controller;
  final bool locating;
  final bool loading;
  final String? errorMessage;
  final ScheduleEntry? schedule;
  final ParkingRegulation? regulation;
  final String timezone;
  final RequestPoint requestPoint;
  final bool scheduleLineVisible;
  final bool regulationLineVisible;
  final VoidCallback? onToggleScheduleLine;
  final VoidCallback? onToggleRegulationLine;

  const _BottomSheet({
    required this.controller,
    required this.locating,
    required this.loading,
    required this.errorMessage,
    required this.schedule,
    required this.regulation,
    required this.timezone,
    required this.requestPoint,
    required this.scheduleLineVisible,
    required this.regulationLineVisible,
    this.onToggleScheduleLine,
    this.onToggleRegulationLine,
  });

  String? _segmentTitle() {
    final scheduleEntry = schedule;
    if (scheduleEntry != null) {
      return '${scheduleEntry.corridor} between ${scheduleEntry.limits}';
    }

    final reg = regulation;
    if (reg == null) return null;
    if (reg.neighborhood != null && reg.neighborhood!.trim().isNotEmpty) {
      return reg.neighborhood!.trim();
    }
    return reg.regulation;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final segmentTitle = _segmentTitle();
    final now = DateTime.now();

    final badges = <_PeekBadgeItem>[];
    final scheduleEntry = schedule;
    if (scheduleEntry != null) {
      badges.add(
        _PeekBadgeItem(
          urgencySeconds:
              _urgencySecondsForIso(scheduleEntry.nextSweepStart, now),
          isSweeping: true,
          badge: TimeUntilBadge(
            startIso: scheduleEntry.nextSweepStart,
            enabled: scheduleLineVisible,
            onToggle: onToggleScheduleLine,
          ),
        ),
      );
    } else if (!locating && !loading) {
      // Show disabled placeholder badge when no schedule found
      badges.add(
        const _PeekBadgeItem(
          urgencySeconds: 1 << 30, // Low priority (sort to end)
          isSweeping: true,
          badge: _PlaceholderBadge(text: 'no sweeping schedule found'),
        ),
      );
    }

    final reg = regulation;
    if (reg != null) {
      final computed =
          _ParkingInForceComputed.compute(regulation: reg, now: now);
      badges.add(
        _PeekBadgeItem(
          urgencySeconds: computed.urgencySeconds,
          isSweeping: false,
          badge: _ParkingInForceBadge(
            regulation: reg,
            computed: computed,
            enabled: regulationLineVisible,
            onToggle: onToggleRegulationLine,
          ),
        ),
      );
    } else if (!locating && !loading) {
      // Show disabled placeholder badge when no regulation found
      badges.add(
        const _PeekBadgeItem(
          urgencySeconds: 1 << 30, // Low priority (sort to end)
          isSweeping: false,
          badge: _PlaceholderBadge(text: 'no time limit found'),
        ),
      );
    }

    badges.sort((a, b) {
      final urgencyCmp = a.urgencySeconds.compareTo(b.urgencySeconds);
      if (urgencyCmp != 0) return urgencyCmp;

      if (a.isSweeping != b.isSweeping) {
        return a.isSweeping ? -1 : 1;
      }

      return 0;
    });

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: Material(
        color: AppTheme.surface,
        child: SafeArea(
          top: false,
          child: ListView(
            controller: controller,
            padding: EdgeInsets.fromLTRB(16, 10, 16, 24 + bottomPadding),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (errorMessage != null)
                StatusBanner(message: errorMessage!, type: StatusType.error),
              if (locating || loading) ...[
                const SizedBox(height: 8),
                _LoadingRow(
                  text: locating
                      ? 'Detecting your location…'
                      : 'Checking nearby…',
                ),
              ],

              // Collapsed "peek" content: street segment + time-until badges.
              const SizedBox(height: 12),
              if (segmentTitle != null) ...[
                Text(
                  segmentTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final item in badges) item.badge,
                  ],
                ),
              ] else ...[
                Text(
                  locating
                      ? 'Finding your location…'
                      : 'Drag the map to check a street segment.',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],

              const SizedBox(height: 14),
              Divider(
                height: 1,
                thickness: 0.8,
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.28),
              ),

              // Expanded content (details).
              if (schedule != null) ...[
                const SizedBox(height: 12),
                ScheduleCard(
                  scheduleEntry: schedule!,
                  timezone: timezone,
                  requestPoint: requestPoint,
                ),
              ] else if (!locating && !loading) ...[
                const SizedBox(height: 12),
                const StatusBanner(
                  message: 'No street sweeping schedule found here.',
                  type: StatusType.info,
                ),
              ],
              if (regulation != null) ...[
                const SizedBox(height: 12),
                ParkingRegulationCard(
                  regulation: regulation!,
                  isSelected: false,
                  requestPoint: requestPoint,
                  moveDeadlineIso: regulation!.nextMoveDeadlineIso,
                ),
              ] else if (!locating && !loading) ...[
                const SizedBox(height: 12),
                const StatusBanner(
                  message: 'No parking regulation found here.',
                  type: StatusType.info,
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

int _urgencySecondsForIso(String iso, DateTime now) {
  try {
    final start = DateTime.parse(iso).toLocal();
    final diffSeconds = start.difference(now).inSeconds;
    if (diffSeconds <= 0) return 0;
    final ceilMinutes = (diffSeconds + 59) ~/ 60;
    return ceilMinutes * 60;
  } catch (_) {
    return 1 << 30;
  }
}

class _PeekBadgeItem {
  final int urgencySeconds;
  final bool isSweeping;
  final Widget badge;

  const _PeekBadgeItem({
    required this.urgencySeconds,
    required this.isSweeping,
    required this.badge,
  });
}

class _ParkingInForceComputed {
  final String statusText;
  final int urgencySeconds;

  const _ParkingInForceComputed({
    required this.statusText,
    required this.urgencySeconds,
  });

  static _ParkingInForceComputed compute({
    required ParkingRegulation regulation,
    required DateTime now,
  }) {
    final days = regulation.days;
    final fromTime = regulation.fromTime;
    final toTime = regulation.toTime;
    if (days == null || fromTime == null || toTime == null) {
      return const _ParkingInForceComputed(
        statusText: '(incomplete schedule)',
        urgencySeconds: 1 << 30,
      );
    }

    final weekdays = _ParkingInForceBadge._parseWeekdays(days);
    final startMinutes = _ParkingInForceBadge._parseTimeToMinutes(fromTime);
    final endMinutes = _ParkingInForceBadge._parseTimeToMinutes(toTime);
    if (weekdays == null || startMinutes == null || endMinutes == null) {
      return const _ParkingInForceComputed(
        statusText: '(incomplete schedule)',
        urgencySeconds: 1 << 30,
      );
    }

    final inForce = _ParkingInForceBadge._isInForceNow(
      weekdays: weekdays,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      now: now,
    );

    // If a regulation is already in force, treat its urgency as the hour-limit
    // length (e.g., a 2-hour limit "now" ties with sweeping "in 2 hours").
    if (inForce == true) {
      final hours = regulation.hourLimit ?? 0;
      return _ParkingInForceComputed(
        statusText: 'now',
        urgencySeconds: hours * 60 * 60,
      );
    }

    if (inForce == false) {
      final nextStart = _ParkingInForceBadge._nextInForceStart(
        weekdays: weekdays,
        startMinutes: startMinutes,
        now: now,
      );
      if (nextStart == null) {
        return const _ParkingInForceComputed(
          statusText: '(incomplete schedule)',
          urgencySeconds: 1 << 30,
        );
      }

      final urgencySeconds = _urgencySecondsForIso(
        nextStart.toIso8601String(),
        now,
      );
      return _ParkingInForceComputed(
        statusText: formatTimeUntil(nextStart.toIso8601String(), prefix: ''),
        urgencySeconds: urgencySeconds,
      );
    }

    return const _ParkingInForceComputed(
      statusText: '(incomplete schedule)',
      urgencySeconds: 1 << 30,
    );
  }
}

class _ParkingInForceBadge extends StatelessWidget {
  final ParkingRegulation regulation;
  final _ParkingInForceComputed? computed;

  /// Whether the associated line overlay is visible on the map.
  final bool enabled;

  /// Called when the badge is tapped to toggle visibility.
  final VoidCallback? onToggle;

  const _ParkingInForceBadge({
    required this.regulation,
    this.computed,
    this.enabled = true,
    this.onToggle,
  });

  static int? _parseTimeToMinutes(String value) {
    final normalized = value.trim().toLowerCase();

    if (normalized == 'midnight') return 0;
    if (normalized == 'noon') return 12 * 60;

    final match12 =
        RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*([ap]m)$').firstMatch(normalized);
    if (match12 != null) {
      final hour = int.tryParse(match12.group(1)!);
      final minute = int.tryParse(match12.group(2) ?? '0') ?? 0;
      final period = match12.group(3)!;
      if (hour == null || hour < 1 || hour > 12 || minute < 0 || minute > 59) {
        return null;
      }
      var hour24 = hour % 12;
      if (period == 'pm') hour24 += 12;
      return hour24 * 60 + minute;
    }

    final match24 = RegExp(r'^(\d{1,2})(?::(\d{2}))?$').firstMatch(normalized);
    if (match24 != null) {
      final hour = int.tryParse(match24.group(1)!);
      final minute = int.tryParse(match24.group(2) ?? '0') ?? 0;
      if (hour == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        return null;
      }
      return hour * 60 + minute;
    }

    return null;
  }

  static Set<int>? _parseWeekdays(String days) {
    final normalized = days.trim().toLowerCase().replaceAll('.', '');
    final withHyphen = normalized.replaceAll('–', '-').replaceAll('—', '-');

    if (withHyphen == 'daily' ||
        withHyphen == 'every day' ||
        withHyphen == 'everyday') {
      return {1, 2, 3, 4, 5, 6, 7};
    }

    if (withHyphen.contains('weekdays')) return {1, 2, 3, 4, 5};
    if (withHyphen.contains('weekends')) return {6, 7};

    const dayMap = <String, int>{
      'mon': 1,
      'monday': 1,
      'tue': 2,
      'tues': 2,
      'tuesday': 2,
      'wed': 3,
      'weds': 3,
      'wednesday': 3,
      'thu': 4,
      'thur': 4,
      'thurs': 4,
      'thursday': 4,
      'fri': 5,
      'friday': 5,
      'sat': 6,
      'saturday': 6,
      'sun': 7,
      'sunday': 7,
      'm': 1,
      'f': 5,
      'sa': 6,
      'su': 7,
    };

    final matchRange = RegExp(r'^(\w+)\s*-\s*(\w+)$').firstMatch(withHyphen);
    if (matchRange != null) {
      final start = dayMap[matchRange.group(1)!];
      final end = dayMap[matchRange.group(2)!];
      if (start == null || end == null) return null;
      final result = <int>{};
      var current = start;
      for (var i = 0; i < 7; i++) {
        result.add(current);
        if (current == end) break;
        current = current == 7 ? 1 : current + 1;
      }
      return result;
    }

    final tokens = withHyphen
        .split(RegExp(r'[,\s]+'))
        .where((t) => t.trim().isNotEmpty)
        .map((t) => t.trim())
        .toList();
    if (tokens.isEmpty) return null;

    final result = <int>{};
    for (final token in tokens) {
      final day = dayMap[token];
      if (day == null) return null;
      result.add(day);
    }
    return result;
  }

  static bool? _isInForceNow({
    required Set<int> weekdays,
    required int startMinutes,
    required int endMinutes,
    required DateTime now,
  }) {
    final nowMinutes = now.hour * 60 + now.minute;
    final today = now.weekday;

    if (startMinutes == endMinutes) {
      return weekdays.contains(today);
    }

    if (startMinutes < endMinutes) {
      if (!weekdays.contains(today)) return false;
      return nowMinutes >= startMinutes && nowMinutes < endMinutes;
    }

    // Overnight window (e.g., 10pm–6am)
    if (nowMinutes >= startMinutes) {
      return weekdays.contains(today);
    }
    final yesterday = today == 1 ? 7 : today - 1;
    return weekdays.contains(yesterday);
  }

  static DateTime? _nextInForceStart({
    required Set<int> weekdays,
    required int startMinutes,
    required DateTime now,
  }) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    final nowMinutes = now.hour * 60 + now.minute;

    // If the regulation has a non-overnight window, and today's window hasn't
    // started yet, that's the next in-force start.
    if (weekdays.contains(now.weekday) && nowMinutes < startMinutes) {
      return startOfToday.add(Duration(minutes: startMinutes));
    }

    // Otherwise, find the next regulated day and start at startMinutes.
    for (var offsetDays = 1; offsetDays <= 7; offsetDays++) {
      final candidate =
          startOfToday.add(Duration(days: offsetDays, minutes: startMinutes));
      if (weekdays.contains(candidate.weekday)) {
        return candidate;
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final limitLabel = regulation.hourLimit != null
        ? '${regulation.hourLimit}-hour limit'
        : 'Parking limit';

    final resolved = computed ??
        _ParkingInForceComputed.compute(
            regulation: regulation, now: DateTime.now());

    // When disabled, use white/off-white colors instead of the accent
    final accent = enabled ? AppTheme.accentParking : AppTheme.textMuted;
    final backgroundColor = enabled
        ? AppTheme.accentParking.withValues(alpha: 0.12)
        : AppTheme.surface;
    final borderColor = enabled
        ? AppTheme.accentParking.withValues(alpha: 0.25)
        : AppTheme.border;

    final badge = DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (enabled)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.check,
                  color: accent,
                  size: 20,
                ),
              ),
            Flexible(
              child: Text(
                '$limitLabel ${resolved.statusText}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: enabled
                      ? colors.onSecondaryContainer
                      : AppTheme.textMuted,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (onToggle == null) {
      return badge;
    }

    return GestureDetector(
      onTap: onToggle,
      child: badge,
    );
  }
}

class _AlertCountBadge extends StatelessWidget {
  final String text;

  const _AlertCountBadge({required this.text});

  factory _AlertCountBadge.count(int count) {
    return _AlertCountBadge(text: count > 99 ? '99+' : '$count');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.error,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppTheme.surface,
          width: 1.5,
        ),
      ),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  final String text;

  const _LoadingRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _LocatingPill extends StatelessWidget {
  const _LocatingPill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              'Finding you…',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterPuck extends StatelessWidget {
  const _CenterPuck();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: AppTheme.primaryColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

/// A disabled-style badge shown when no schedule or regulation is found.
/// Matches the TimeUntilBadge disabled styling (off-white, no color, not tappable).
class _PlaceholderBadge extends StatelessWidget {
  final String text;

  const _PlaceholderBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 8,
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMuted,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
