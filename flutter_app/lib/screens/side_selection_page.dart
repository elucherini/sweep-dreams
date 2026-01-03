import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../models/schedule_response.dart';
import '../theme/app_theme.dart';
import '../widgets/schedule_card.dart';

class SideSelectionPage extends StatefulWidget {
  final ScheduleResponse scheduleResponse;
  final String selectedCorridor;
  final String selectedBlock;
  final VoidCallback onBack;

  const SideSelectionPage({
    super.key,
    required this.scheduleResponse,
    required this.selectedCorridor,
    required this.selectedBlock,
    required this.onBack,
  });

  @override
  State<SideSelectionPage> createState() => _SideSelectionPageState();
}

class _SideSelectionPageState extends State<SideSelectionPage> {
  String? _selectedSide;
  MapboxMap? _mapboxMap;
  bool _lineLayerAdded = false;
  bool _mapReady = false;
  bool _userInView = true;
  double _userBearing = 0.0; // Angle from map center to user position

  /// Get all coordinates from the geometry for the selected block
  List<Position> _getAllLineCoordinates() {
    final coordinates = <Position>[];
    for (final entry in widget.scheduleResponse.schedules) {
      if (entry.corridor == widget.selectedCorridor &&
          entry.limits == widget.selectedBlock) {
        final geometry = entry.geometry;
        if (geometry['type'] == 'LineString') {
          final coords = geometry['coordinates'] as List;
          for (final coord in coords) {
            coordinates.add(Position(
              (coord[0] as num).toDouble(),
              (coord[1] as num).toDouble(),
            ));
          }
        }
      }
    }
    return coordinates;
  }

  /// Calculate the center point of all line coordinates
  Position? _getLineCenter() {
    final coordinates = _getAllLineCoordinates();
    if (coordinates.isEmpty) return null;

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

  static const double _maxZoom =
      17.0; // Maximum zoom to prevent excessive zoom on short blocks

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    mapboxMap.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
  }

  void _onStyleLoaded(StyleLoadedEventData eventData) async {
    await _updateLineLayer();
    await _fitCameraToBounds();

    // Mark map as ready to show
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
    if (bounds == null) return;

    // Fit camera to the line bounds with padding
    var cameraOptions = await mapboxMap.cameraForCoordinateBounds(
      bounds,
      MbxEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
      null, // bearing
      null, // pitch
      null, // maxZoom
      null, // offset
    );

    // Enforce maximum zoom to prevent excessive zoom on short blocks
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

    // Check if user is in view and update arrow direction
    await _updateUserIndicator();
  }

  Future<void> _updateUserIndicator() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final userLat = widget.scheduleResponse.requestPoint.latitude;
    final userLng = widget.scheduleResponse.requestPoint.longitude;

    // Get visible bounds
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

    // Update location puck visibility based on whether user is in view
    await mapboxMap.location.updateSettings(LocationComponentSettings(
      enabled: inView,
      pulsingEnabled: false,
      locationPuck: LocationPuck(
        locationPuck2D: DefaultLocationPuck2D(opacity: 0.5),
      ),
    ));

    if (!inView) {
      // Calculate bearing from map center to user
      final centerLat = (swLat + neLat) / 2;
      final centerLng = (swLng + neLng) / 2;

      final deltaLng = userLng - centerLng;
      final deltaLat = userLat - centerLat;

      // Bearing in radians, then convert to degrees
      // atan2 gives angle from positive X axis, we want from north (positive Y)
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

  static const _lineLayerId = 'side-line-layer';
  static const _lineSourceId = 'side-line';
  static const double _lineOffset = 5.0; // Pixels to offset from centerline

  /// Get the line offset based on cnn_right_left value.
  /// 'R' = right side of centerline → positive offset (Mapbox shifts right)
  /// 'L' = left side of centerline → negative offset (Mapbox shifts left)
  double _getOffsetForSide(String cnnRightLeft) {
    return cnnRightLeft == 'R' ? _lineOffset : -_lineOffset;
  }

  Future<void> _updateLineLayer() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final entry = _entry;
    if (entry == null) return;

    // Create a FeatureCollection with the centerline geometry
    final geoJson = jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': entry.geometry,
        }
      ],
    });

    if (_lineLayerAdded) {
      // Update existing source
      final source = await mapboxMap.style.getSource(_lineSourceId);
      if (source is GeoJsonSource) {
        await source.updateGeoJSON(geoJson);
      }
      // Update line offset based on selected side (only for single-side blocks)
      if (entry.blockSide != null) {
        await _updateLineOffset(entry.cnnRightLeft);
      }
    } else {
      // Add new source and layer(s)
      await mapboxMap.style
          .addSource(GeoJsonSource(id: _lineSourceId, data: geoJson));

      if (entry.blockSide == null) {
        // Both sides have the same schedule - draw two lines with opposite offsets
        await mapboxMap.style.addLayer(LineLayer(
          id: '$_lineLayerId-left',
          sourceId: _lineSourceId,
          lineJoin: LineJoin.MITER,
          lineCap: LineCap.BUTT,
          lineColor: AppTheme.accent.toARGB32(),
          lineWidth: 6.0,
          lineOffset: -_lineOffset,
        ));
        await mapboxMap.style.addLayer(LineLayer(
          id: '$_lineLayerId-right',
          sourceId: _lineSourceId,
          lineJoin: LineJoin.MITER,
          lineCap: LineCap.BUTT,
          lineColor: AppTheme.accent.toARGB32(),
          lineWidth: 6.0,
          lineOffset: _lineOffset,
        ));
      } else {
        // Single side - draw one line with appropriate offset
        await mapboxMap.style.addLayer(LineLayer(
          id: _lineLayerId,
          sourceId: _lineSourceId,
          lineJoin: LineJoin.MITER,
          lineCap: LineCap.BUTT,
          lineColor: AppTheme.accent.toARGB32(),
          lineWidth: 6.0,
          lineOffset: _getOffsetForSide(entry.cnnRightLeft),
        ));
      }
      _lineLayerAdded = true;
    }
  }

  /// Update the line offset when the selected side changes
  Future<void> _updateLineOffset(String cnnRightLeft) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    // Update the single line layer's offset
    final layer = await mapboxMap.style.getLayer(_lineLayerId);
    if (layer is LineLayer) {
      await mapboxMap.style.setStyleLayerProperty(
        _lineLayerId,
        'line-offset',
        _getOffsetForSide(cnnRightLeft),
      );
    }
  }

  /// Get unique sides for the selected corridor and block, sorted so that
  /// cardinal directions match map orientation (West/North on left, East/South on right)
  List<String?> get _sides {
    final sides = <String?>[];
    for (final entry in widget.scheduleResponse.schedules) {
      if (entry.corridor == widget.selectedCorridor &&
          entry.limits == widget.selectedBlock) {
        if (!sides.contains(entry.blockSide)) {
          sides.add(entry.blockSide);
        }
      }
    }
    // Sort by cardinal direction: West/North first (left button), East/South second (right button)
    // This matches standard map orientation where West is left and East is right
    sides.sort((a, b) {
      final order = {
        'West': 0,
        'NorthWest': 0,
        'North': 1,
        'NorthEast': 2,
        'East': 3,
        'SouthEast': 3,
        'South': 2,
        'SouthWest': 1
      };
      final orderA = order[a] ?? 2;
      final orderB = order[b] ?? 2;
      return orderA.compareTo(orderB);
    });
    return sides;
  }

  /// Get the side where the user is located (isUserSide == true)
  String? get _userSide {
    for (final entry in widget.scheduleResponse.schedules) {
      if (entry.corridor == widget.selectedCorridor &&
          entry.limits == widget.selectedBlock &&
          entry.isUserSide) {
        return entry.blockSide;
      }
    }
    return null;
  }

  /// Get the schedule entry for the effective side
  ScheduleEntry? get _entry {
    final sides = _sides;
    final effectiveSide =
        _selectedSide ?? _userSide ?? (sides.isNotEmpty ? sides.first : null);

    for (final e in widget.scheduleResponse.schedules) {
      if (e.corridor == widget.selectedCorridor &&
          e.limits == widget.selectedBlock) {
        if (sides.length <= 1) {
          return e;
        } else if (e.blockSide == effectiveSide) {
          return e;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sides = _sides;
    final effectiveSide =
        _selectedSide ?? _userSide ?? (sides.isNotEmpty ? sides.first : null);
    final entry = _entry;

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
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 200,
                    child: Stack(
                      children: [
                        // Set initial camera to line center to avoid world view flash
                        MapWidget(
                          cameraOptions: CameraOptions(
                            center: Point(
                                coordinates: _getLineCenter() ??
                                    Position(
                                      widget.scheduleResponse.requestPoint
                                          .longitude,
                                      widget.scheduleResponse.requestPoint
                                          .latitude,
                                    )),
                            zoom: _maxZoom,
                          ),
                          styleUri: MapboxStyles.STANDARD,
                          onMapCreated: _onMapCreated,
                          onStyleLoadedListener: _onStyleLoaded,
                        ),
                        // Show loading overlay until map is fully ready
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
                const SizedBox(height: 16),
                if (entry != null)
                  ScheduleCard(
                    scheduleEntry: entry,
                    timezone: widget.scheduleResponse.timezone,
                    requestPoint: widget.scheduleResponse.requestPoint,
                    sides: sides.length > 1 ? sides : null,
                    selectedSide: effectiveSide,
                    onSideChanged: sides.length > 1
                        ? (side) {
                            setState(() {
                              _selectedSide = side;
                            });
                            _updateLineLayer();
                          }
                        : null,
                  ),
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
  final double bearing; // Degrees from north (0 = up, 90 = right, etc.)

  const _UserDirectionArrow({required this.bearing});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final centerX = constraints.maxWidth / 2;
        final centerY = constraints.maxHeight / 2;

        // Calculate position on edge of container based on bearing
        // bearing: 0 = north (top), 90 = east (right), 180 = south (bottom), -90 = west (left)
        final radians = bearing * math.pi / 180;

        // Unit direction vector (north = positive Y in math coords, but negative Y in screen coords)
        final dirX = math.sin(radians);
        final dirY = -math.cos(radians);

        // Find intersection with container edge
        // We need to scale the direction vector to hit the edge
        double scale = double.infinity;

        if (dirX != 0) {
          final edgeX = dirX > 0 ? constraints.maxWidth : 0;
          scale = math.min(scale, (edgeX - centerX) / dirX);
        }
        if (dirY != 0) {
          final edgeY = dirY > 0 ? constraints.maxHeight : 0;
          scale = math.min(scale, (edgeY - centerY) / dirY);
        }

        // Position on edge, with padding
        const padding = 24.0;
        final edgeX = centerX + dirX * (scale - padding / scale.abs());
        final edgeY = centerY + dirY * (scale - padding / scale.abs());

        // Clamp to ensure we stay within bounds with padding
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
                    // Small directional arrow
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
