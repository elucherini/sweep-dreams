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
import '../theme/app_theme.dart';
import '../widgets/parking_regulation_card.dart';
import '../widgets/schedule_card.dart';
import '../widgets/status_banner.dart';
import 'alerts_screen.dart';

class MapHomeScreen extends StatefulWidget {
  const MapHomeScreen({super.key});

  @override
  State<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends State<MapHomeScreen> {
  static const double _defaultZoom = 16.5;
  static const double _minLookupMoveMeters = 20.0;

  static const _lineSourceId = 'puck-line';
  static const _lineLayerId = 'puck-line-layer';
  static const double _lineOffset = 5.0;

  final LocationService _locationService = LocationService();

  MapboxMap? _mapboxMap;
  bool _styleLoaded = false;
  bool _lineLayersReady = false;

  int _lookupSeq = 0;

  bool _locating = true;
  bool _loadingResults = false;
  String? _errorMessage;

  RequestPoint? _lastLookupPoint;
  RequestPoint? _puckPoint;

  ScheduleEntry? _schedule;
  ParkingRegulation? _regulation;
  String _timezone = 'America/Los_Angeles';

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
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

  Map<String, dynamic>? _geometryForLine({
    required ScheduleEntry? scheduleEntry,
    required ParkingRegulation? regulation,
  }) {
    final scheduleGeometry = scheduleEntry?.geometry;
    if (scheduleGeometry != null && scheduleGeometry['type'] != null) {
      return scheduleGeometry;
    }
    final regLine = regulation?.line;
    if (regLine != null && regLine['type'] != null) {
      return regLine;
    }
    return null;
  }

  Future<void> _updateLineLayer({
    required ScheduleEntry? scheduleEntry,
    required ParkingRegulation? regulation,
  }) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null || !_styleLoaded) return;

    await _ensureLineLayers();

    final geometry = _geometryForLine(
      scheduleEntry: scheduleEntry,
      regulation: regulation,
    );

    final geoJson = jsonEncode({
      'type': 'FeatureCollection',
      'features': geometry == null
          ? []
          : [
              {
                'type': 'Feature',
                'geometry': geometry,
              }
            ],
    });

    final source = await mapboxMap.style.getSource(_lineSourceId);
    if (source is GeoJsonSource) {
      await source.updateGeoJSON(geoJson);
    }

    if (geometry == null) {
      await _setLineOpacity(_lineLayerId, 0.0);
      await _setLineOpacity('$_lineLayerId-left', 0.0);
      await _setLineOpacity('$_lineLayerId-right', 0.0);
      return;
    }

    final showBothSides =
        scheduleEntry != null && scheduleEntry.blockSide == null;
    if (showBothSides) {
      await _setLineOpacity(_lineLayerId, 0.0);
      await _setLineOpacity('$_lineLayerId-left', 1.0);
      await _setLineOpacity('$_lineLayerId-right', 1.0);
      return;
    }

    await _setLineOpacity(_lineLayerId, 1.0);
    await _setLineOpacity('$_lineLayerId-left', 0.0);
    await _setLineOpacity('$_lineLayerId-right', 0.0);

    final offset = scheduleEntry?.blockSide != null
        ? _getOffsetForSide(scheduleEntry!.cnnRightLeft)
        : 0.0;
    await _updateLineOffset(offset);
  }

  Future<void> _ensureLineLayers() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null || _lineLayersReady) return;

    const emptyGeoJson = '{"type":"FeatureCollection","features":[]}';
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

  @override
  Widget build(BuildContext context) {
    final defaultCenter =
        RequestPoint(latitude: 37.7749, longitude: -122.4194); // SF fallback
    final requestPoint = _puckPoint ?? defaultCenter;

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
            minChildSize: 0.18,
            initialChildSize: 0.28,
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
              );
            },
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
      floatingActionButton: FloatingActionButton.small(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AlertsScreen()),
          );
        },
        backgroundColor: AppTheme.surface,
        elevation: 3,
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

  const _BottomSheet({
    required this.controller,
    required this.locating,
    required this.loading,
    required this.errorMessage,
    required this.schedule,
    required this.regulation,
    required this.timezone,
    required this.requestPoint,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;

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
