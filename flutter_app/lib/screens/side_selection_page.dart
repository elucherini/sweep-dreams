import 'dart:convert';

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

  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    mapboxMap.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    mapboxMap.location.updateSettings(LocationComponentSettings(
      enabled: true,
      pulsingEnabled: false,
      locationPuck: LocationPuck(
        locationPuck2D: DefaultLocationPuck2D(opacity: 0.5),
      ),
    ));

    await _updateLineLayer();
  }

  static const _lineLayerId = 'side-line-layer';
  static const _lineSourceId = 'side-line';

  Future<void> _updateLineLayer() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final entry = _entry;
    if (entry == null) return;

    // Create a FeatureCollection with all side geometries
    final features = entry.sideGeometries
        .map((geometry) => {
              'type': 'Feature',
              'geometry': geometry,
            })
        .toList();

    final geoJson = jsonEncode({
      'type': 'FeatureCollection',
      'features': features,
    });

    if (_lineLayerAdded) {
      // Update existing source
      final source = await mapboxMap.style.getSource(_lineSourceId);
      if (source is GeoJsonSource) {
        await source.updateGeoJSON(geoJson);
      }
    } else {
      // Add new source and layer
      await mapboxMap.style.addSource(GeoJsonSource(id: _lineSourceId, data: geoJson));
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

  /// Get unique sides for the selected corridor and block
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
                    child: MapWidget(
                      cameraOptions: CameraOptions(
                        center: Point(
                          coordinates: Position(
                            widget.scheduleResponse.requestPoint.longitude,
                            widget.scheduleResponse.requestPoint.latitude,
                          ),
                        ),
                        zoom: 16.0,
                      ),
                      styleUri: MapboxStyles.STANDARD,
                      onMapCreated: _onMapCreated,
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
