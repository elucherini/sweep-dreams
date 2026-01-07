import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../models/parking_response.dart';
import '../models/schedule_response.dart';
import '../theme/app_theme.dart';
import '../widgets/parking_regulation_card.dart';

class ParkingRegulationsPage extends StatefulWidget {
  final ParkingResponse parkingResponse;
  final RequestPoint requestPoint;
  final VoidCallback onBack;

  const ParkingRegulationsPage({
    super.key,
    required this.parkingResponse,
    required this.requestPoint,
    required this.onBack,
  });

  @override
  State<ParkingRegulationsPage> createState() => _ParkingRegulationsPageState();
}

class _ParkingRegulationsPageState extends State<ParkingRegulationsPage> {
  int? _selectedIndex;
  MapboxMap? _mapboxMap;
  bool _lineLayerAdded = false;
  bool _mapReady = false;
  bool _userInView = true;
  double _userBearing = 0.0;

  static const _lineLayerId = 'parking-line-layer';
  static const _lineSourceId = 'parking-line';
  static const double _maxZoom = 17.0;

  ParkingRegulation? get _selectedRegulation {
    if (_selectedIndex == null ||
        _selectedIndex! >= widget.parkingResponse.regulations.length) {
      return null;
    }
    return widget.parkingResponse.regulations[_selectedIndex!];
  }

  /// Get all coordinates from the selected regulation's geometry
  List<Position> _getAllLineCoordinates() {
    final reg = _selectedRegulation;
    if (reg == null || reg.line == null) return [];

    final coordinates = <Position>[];
    final geometry = reg.line!;
    final type = geometry['type'] as String?;

    if (type == 'LineString') {
      final coords = geometry['coordinates'] as List;
      for (final coord in coords) {
        coordinates.add(Position(
          (coord[0] as num).toDouble(),
          (coord[1] as num).toDouble(),
        ));
      }
    } else if (type == 'MultiLineString') {
      final lines = geometry['coordinates'] as List;
      for (final line in lines) {
        for (final coord in line) {
          coordinates.add(Position(
            (coord[0] as num).toDouble(),
            (coord[1] as num).toDouble(),
          ));
        }
      }
    }
    return coordinates;
  }

  /// Calculate the center point of all line coordinates
  Position? _getLineCenter() {
    final coordinates = _getAllLineCoordinates();
    if (coordinates.isEmpty) {
      // Fall back to user position
      return Position(
        widget.requestPoint.longitude,
        widget.requestPoint.latitude,
      );
    }

    double sumLng = 0;
    double sumLat = 0;
    for (final coord in coordinates) {
      sumLng += coord.lng.toDouble();
      sumLat += coord.lat.toDouble();
    }
    return Position(sumLng / coordinates.length, sumLat / coordinates.length);
  }

  /// Calculate bounds that contain all line coordinates
  CoordinateBounds? _getLineBounds() {
    final coordinates = _getAllLineCoordinates();
    if (coordinates.isEmpty) return null;

    double minLng = coordinates.first.lng.toDouble();
    double maxLng = coordinates.first.lng.toDouble();
    double minLat = coordinates.first.lat.toDouble();
    double maxLat = coordinates.first.lat.toDouble();

    for (final coord in coordinates) {
      minLng = math.min(minLng, coord.lng.toDouble());
      maxLng = math.max(maxLng, coord.lng.toDouble());
      minLat = math.min(minLat, coord.lat.toDouble());
      maxLat = math.max(maxLat, coord.lat.toDouble());
    }

    return CoordinateBounds(
      southwest: Point(coordinates: Position(minLng, minLat)),
      northeast: Point(coordinates: Position(maxLng, maxLat)),
      infiniteBounds: false,
    );
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    mapboxMap.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
  }

  void _onStyleLoaded(StyleLoadedEventData eventData) async {
    // Select first regulation by default if available
    if (widget.parkingResponse.regulations.isNotEmpty &&
        _selectedIndex == null) {
      setState(() {
        _selectedIndex = 0;
      });
    }

    await _updateLineLayer();
    await _fitCameraToBounds();

    if (mounted) {
      setState(() {
        _mapReady = true;
      });
    }
  }

  Future<void> _fitCameraToBounds() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final bounds = _getLineBounds();
    if (bounds == null) {
      // No geometry, center on user location
      await mapboxMap.setCamera(CameraOptions(
        center: Point(
          coordinates: Position(
            widget.requestPoint.longitude,
            widget.requestPoint.latitude,
          ),
        ),
        zoom: _maxZoom,
      ));
      await _updateUserIndicator();
      return;
    }

    var cameraOptions = await mapboxMap.cameraForCoordinateBounds(
      bounds,
      MbxEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
      null,
      null,
      null,
      null,
    );

    final zoom = cameraOptions.zoom ?? 0;
    if (zoom > _maxZoom) {
      cameraOptions = CameraOptions(
        center: cameraOptions.center,
        zoom: _maxZoom,
        bearing: cameraOptions.bearing,
        pitch: cameraOptions.pitch,
      );
    }

    await mapboxMap.setCamera(cameraOptions);
    await _updateUserIndicator();
  }

  Future<void> _updateUserIndicator() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final userLat = widget.requestPoint.latitude;
    final userLng = widget.requestPoint.longitude;

    final bounds = await mapboxMap.coordinateBoundsForCamera(
      await mapboxMap.getCameraState().then((state) => CameraOptions(
            center: state.center,
            zoom: state.zoom,
            bearing: state.bearing,
            pitch: state.pitch,
          )),
    );

    final swLat = bounds.southwest.coordinates.lat.toDouble();
    final swLng = bounds.southwest.coordinates.lng.toDouble();
    final neLat = bounds.northeast.coordinates.lat.toDouble();
    final neLng = bounds.northeast.coordinates.lng.toDouble();

    final inView = userLat >= swLat &&
        userLat <= neLat &&
        userLng >= swLng &&
        userLng <= neLng;

    await mapboxMap.location.updateSettings(LocationComponentSettings(
      enabled: inView,
      pulsingEnabled: false,
      locationPuck: LocationPuck(
        locationPuck2D: DefaultLocationPuck2D(opacity: 0.5),
      ),
    ));

    if (!inView) {
      final centerLat = (swLat + neLat) / 2;
      final centerLng = (swLng + neLng) / 2;

      final deltaLng = userLng - centerLng;
      final deltaLat = userLat - centerLat;

      final bearing = math.atan2(deltaLng, deltaLat) * 180 / math.pi;

      setState(() {
        _userInView = false;
        _userBearing = bearing;
      });
    } else {
      setState(() {
        _userInView = true;
      });
    }
  }

  Future<void> _updateLineLayer() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final reg = _selectedRegulation;
    if (reg == null || reg.line == null) {
      // Remove layer if no geometry
      if (_lineLayerAdded) {
        try {
          await mapboxMap.style.removeStyleLayer(_lineLayerId);
          await mapboxMap.style.removeStyleSource(_lineSourceId);
          _lineLayerAdded = false;
        } catch (_) {}
      }
      return;
    }

    final geoJson = jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': reg.line,
        }
      ],
    });

    if (_lineLayerAdded) {
      final source = await mapboxMap.style.getSource(_lineSourceId);
      if (source is GeoJsonSource) {
        await source.updateGeoJSON(geoJson);
      }
    } else {
      await mapboxMap.style
          .addSource(GeoJsonSource(id: _lineSourceId, data: geoJson));

      await mapboxMap.style.addLayer(LineLayer(
        id: _lineLayerId,
        sourceId: _lineSourceId,
        lineJoin: LineJoin.MITER,
        lineCap: LineCap.BUTT,
        lineColor: AppTheme.accent.toARGB32(),
        lineWidth: 6.0,
      ));
      _lineLayerAdded = true;
    }
  }

  void _onRegulationTap(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _updateLineLayer();
    _fitCameraToBounds();
  }

  @override
  Widget build(BuildContext context) {
    final regulations = widget.parkingResponse.regulations;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.screenPadding),
        child: Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: AppTheme.maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BackButton(onTap: widget.onBack),
                const SizedBox(height: 16),
                // Map section
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 200,
                    child: Stack(
                      children: [
                        MapWidget(
                          cameraOptions: CameraOptions(
                            center: Point(
                              coordinates: _getLineCenter() ??
                                  Position(
                                    widget.requestPoint.longitude,
                                    widget.requestPoint.latitude,
                                  ),
                            ),
                            zoom: _maxZoom,
                          ),
                          styleUri: MapboxStyles.STANDARD,
                          onMapCreated: _onMapCreated,
                          onStyleLoadedListener: _onStyleLoaded,
                        ),
                        if (!_mapReady)
                          Container(
                            color: Colors.grey[200],
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                        if (_mapReady && !_userInView)
                          _UserDirectionArrow(bearing: _userBearing),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Title
                const Text(
                  'Parking regulations',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${regulations.length} regulation${regulations.length == 1 ? '' : 's'} nearby',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 16),
                // Regulation cards
                ...regulations.asMap().entries.map((entry) {
                  final index = entry.key;
                  final reg = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ParkingRegulationCard(
                      regulation: reg,
                      isSelected: index == _selectedIndex,
                      onTap: () => _onRegulationTap(index),
                      requestPoint: widget.requestPoint,
                      moveDeadlineIso: reg.nextMoveDeadlineIso,
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chevron_left,
              color: AppTheme.primaryColor,
              size: 20,
            ),
            Text(
              'Back',
              style: TextStyle(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Arrow indicator positioned at the edge of the map pointing toward the user's location
class _UserDirectionArrow extends StatelessWidget {
  final double bearing;

  const _UserDirectionArrow({required this.bearing});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final centerX = constraints.maxWidth / 2;
        final centerY = constraints.maxHeight / 2;

        final radians = bearing * math.pi / 180;

        final dirX = math.sin(radians);
        final dirY = -math.cos(radians);

        double scale = double.infinity;

        if (dirX != 0) {
          final edgeX = dirX > 0 ? constraints.maxWidth : 0;
          scale = math.min(scale, (edgeX - centerX) / dirX);
        }
        if (dirY != 0) {
          final edgeY = dirY > 0 ? constraints.maxHeight : 0;
          scale = math.min(scale, (edgeY - centerY) / dirY);
        }

        const padding = 24.0;
        final edgeX = centerX + dirX * (scale - padding / scale.abs());
        final edgeY = centerY + dirY * (scale - padding / scale.abs());

        final clampedX = edgeX.clamp(padding, constraints.maxWidth - padding);
        final clampedY = edgeY.clamp(padding, constraints.maxHeight - padding);

        return Stack(
          children: [
            Positioned(
              left: clampedX - 20,
              top: clampedY - 20,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.person,
                      color: AppTheme.accent.withValues(alpha: 0.5),
                      size: 22,
                    ),
                    Transform.translate(
                      offset: Offset(
                        12 * math.sin(radians),
                        -12 * math.cos(radians),
                      ),
                      child: Transform.rotate(
                        angle: radians,
                        child: Icon(
                          Icons.arrow_drop_up,
                          color: AppTheme.accent.withValues(alpha: 0.5),
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
