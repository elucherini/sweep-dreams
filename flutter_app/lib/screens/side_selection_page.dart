import 'package:flutter/material.dart';

import '../models/schedule_response.dart';
import '../theme/app_theme.dart';
import '../widgets/frosted_card.dart';
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

  /// Get the schedule entry for the effective side
  ScheduleEntry? get _entry {
    final sides = _sides;
    final effectiveSide = _selectedSide ?? (sides.isNotEmpty ? sides.first : null);

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
    final effectiveSide = _selectedSide ?? (sides.isNotEmpty ? sides.first : null);
    final entry = _entry;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.screenPadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppTheme.maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BackButton(onTap: widget.onBack),
                const SizedBox(height: 16),
                if (entry != null)
                  FrostedCard(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.cardPadding),
                      child: ScheduleCard(
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
                              }
                            : null,
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
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: const Row(
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
