import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// Minimum lead time in minutes - reminders must be at least this far in the future
const int _minLeadTimeMinutes = 30;

/// Minimum lead time for timing subscriptions (allows "when it starts" = 0)
const int _minLeadTimeMinutesTiming = 0;

enum ReminderPreset {
  hour1,
  hour2,
  nightBefore;

  int leadMinutesFor(String sweepStartIso) {
    final sweepStart = DateTime.parse(sweepStartIso).toLocal();
    return switch (this) {
      ReminderPreset.hour1 => 60,
      ReminderPreset.hour2 => 120,
      ReminderPreset.nightBefore => () {
          // Target: 9pm (21:00) the evening before the sweep
          final notifyAt = DateTime(
            sweepStart.year,
            sweepStart.month,
            sweepStart.day - 1,
            21, // 9pm
          );
          return sweepStart.difference(notifyAt).inMinutes;
        }(),
    };
  }

  /// Returns true if this preset's reminder time would be at least 30 minutes from now
  bool isValidFor(String sweepStartIso) {
    final sweepStart = DateTime.parse(sweepStartIso).toLocal();
    final leadMinutes = leadMinutesFor(sweepStartIso);
    final notifyAt = sweepStart.subtract(Duration(minutes: leadMinutes));
    final now = DateTime.now();
    return notifyAt.difference(now).inMinutes >= _minLeadTimeMinutes;
  }

  String get label => switch (this) {
        ReminderPreset.hour1 => '1 hour before',
        ReminderPreset.hour2 => '2 hours before',
        ReminderPreset.nightBefore => 'Night before at 9pm',
      };
}

/// Presets for timing/parking subscriptions
enum TimingPreset {
  limitEnd,
  minutes15,
  minutes30;

  int get leadMinutes => switch (this) {
        TimingPreset.limitEnd => 0,
        TimingPreset.minutes15 => 15,
        TimingPreset.minutes30 => 30,
      };

  /// Returns true if this preset's reminder time would be valid (notification in the future)
  bool isValidFor(String deadlineIso) {
    final deadline = DateTime.parse(deadlineIso).toLocal();
    final notifyAt = deadline.subtract(Duration(minutes: leadMinutes));
    final now = DateTime.now();
    // For "when it starts" (0 min), just need deadline to be in the future
    // For 30 min, need at least 30 minutes
    return notifyAt.isAfter(now);
  }

  String get label => switch (this) {
        TimingPreset.limitEnd => 'When limit ends',
        TimingPreset.minutes15 => '15 minutes before',
        TimingPreset.minutes30 => '30 minutes before',
      };
}

/// Result of the reminder picker - either a preset or custom lead minutes
sealed class ReminderSelection {
  const ReminderSelection();

  /// Get the lead minutes for this selection
  int leadMinutesFor(String sweepStartIso) => switch (this) {
        PresetSelection(:final preset) => preset.leadMinutesFor(sweepStartIso),
        TimingSelection(:final preset) => preset.leadMinutes,
        CustomSelection(:final leadMinutes) => leadMinutes,
      };
}

class PresetSelection extends ReminderSelection {
  final ReminderPreset preset;
  const PresetSelection(this.preset);
}

class TimingSelection extends ReminderSelection {
  final TimingPreset preset;
  const TimingSelection(this.preset);
}

class CustomSelection extends ReminderSelection {
  final int leadMinutes;
  const CustomSelection(this.leadMinutes);
}

/// Shows a reminder picker that adapts to the platform:
/// - iOS/Android: modal bottom sheet with tappable rows
/// - Web/desktop: dialog with tappable rows
///
/// When [forTiming] is true, shows timing-specific presets:
/// - "When it starts" (0 minutes)
/// - "30 minutes before" (30 minutes)
Future<ReminderSelection?> showReminderPicker({
  required BuildContext context,
  required String streetName,
  required String scheduleDescription,
  required String sweepStartIso,
  ReminderSelection? selected,
  bool forTiming = false,
}) async {
  final width = MediaQuery.of(context).size.width;
  final useDialog = kIsWeb || width >= 700;

  if (useDialog) {
    return showDialog<ReminderSelection>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ReminderDialog(
        selected: selected,
        streetName: streetName,
        scheduleDescription: scheduleDescription,
        sweepStartIso: sweepStartIso,
        forTiming: forTiming,
      ),
    );
  } else {
    return showModalBottomSheet<ReminderSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      enableDrag: true,
      builder: (_) => _ReminderBottomSheet(
        selected: selected,
        streetName: streetName,
        scheduleDescription: scheduleDescription,
        sweepStartIso: sweepStartIso,
        forTiming: forTiming,
      ),
    );
  }
}

/// View mode for the reminder bottom sheet
enum _ReminderView { presets, custom }

class _ReminderBottomSheet extends StatefulWidget {
  const _ReminderBottomSheet({
    required this.selected,
    required this.streetName,
    required this.scheduleDescription,
    required this.sweepStartIso,
    this.forTiming = false,
  });

  final ReminderSelection? selected;
  final String streetName;
  final String scheduleDescription;
  final String sweepStartIso;
  final bool forTiming;

  @override
  State<_ReminderBottomSheet> createState() => _ReminderBottomSheetState();
}

class _ReminderBottomSheetState extends State<_ReminderBottomSheet> {
  _ReminderView _currentView = _ReminderView.presets;
  late int _customLeadMinutes;

  static const int _maxMinutes = 10080; // 1 week

  int get _stepMinutes => widget.forTiming ? 15 : 30;

  int get _minMinutes =>
      widget.forTiming ? _minLeadTimeMinutesTiming : _minLeadTimeMinutes;

  int get _maxAllowedMinutes {
    final sweepStart = DateTime.parse(widget.sweepStartIso).toLocal();
    final now = DateTime.now();
    final minutesUntilSweep = sweepStart.difference(now).inMinutes;
    final maxAllowed = minutesUntilSweep - _minMinutes;
    final rounded = (maxAllowed ~/ _stepMinutes) * _stepMinutes;
    return rounded.clamp(_minMinutes, _maxMinutes);
  }

  @override
  void initState() {
    super.initState();
    final initialMinutes = switch (widget.selected) {
      CustomSelection(:final leadMinutes) => leadMinutes,
      _ => widget.forTiming
          ? 15
          : 90, // Default to 30min for timing, 1hr 30min for sweeping
    };
    _customLeadMinutes = initialMinutes.clamp(_minMinutes, _maxAllowedMinutes);
  }

  ReminderPreset? get _selectedPreset => switch (widget.selected) {
        PresetSelection(:final preset) => preset,
        _ => null,
      };

  TimingPreset? get _selectedTimingPreset => switch (widget.selected) {
        TimingSelection(:final preset) => preset,
        _ => null,
      };

  bool get _isCustomSelected => widget.selected is CustomSelection;

  bool get _isCustomAvailable {
    final sweepStart = DateTime.parse(widget.sweepStartIso).toLocal();
    final now = DateTime.now();
    return sweepStart.difference(now).inMinutes >= _minMinutes * 2;
  }

  void _showCustomView() {
    setState(() => _currentView = _ReminderView.custom);
  }

  void _decrementCustom() {
    if (_customLeadMinutes > _minMinutes) {
      setState(() => _customLeadMinutes -= _stepMinutes);
    }
  }

  void _incrementCustom() {
    if (_customLeadMinutes < _maxAllowedMinutes) {
      setState(() => _customLeadMinutes += _stepMinutes);
    }
  }

  String _getNotifyTimePreview() {
    try {
      final sweepStart = DateTime.parse(widget.sweepStartIso).toLocal();
      final notifyAt =
          sweepStart.subtract(Duration(minutes: _customLeadMinutes));
      final formatter = DateFormat('EEE, MMM d \'at\' h:mma');
      return formatter
          .format(notifyAt)
          .replaceAll('AM', 'am')
          .replaceAll('PM', 'pm');
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              // Determine slide direction based on which view is showing
              final isCustomView = child.key == const ValueKey('custom');
              final slideOffset = isCustomView
                  ? Tween<Offset>(
                      begin: const Offset(1.0, 0.0),
                      end: Offset.zero,
                    )
                  : Tween<Offset>(
                      begin: const Offset(-1.0, 0.0),
                      end: Offset.zero,
                    );

              return SlideTransition(
                position: slideOffset.animate(animation),
                child: FadeTransition(
                  opacity: animation,
                  child: child,
                ),
              );
            },
            child: _currentView == _ReminderView.presets
                ? _buildPresetsView()
                : _buildCustomView(),
          ),
        ),
      ),
    );
  }

  Widget _buildPresetsView() {
    final title =
        widget.forTiming ? 'Parking reminder' : 'Street cleaning reminder';
    final customDisabledReason =
        widget.forTiming ? 'Deadline too soon' : 'Sweep starts too soon';

    return Column(
      key: const ValueKey('presets'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        Text(
          '${widget.streetName}  ·  ${widget.scheduleDescription}',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (widget.forTiming)
          ...TimingPreset.values.map(
            (preset) {
              final isValid = preset.isValidFor(widget.sweepStartIso);
              return _OptionRow(
                label: preset.label,
                isSelected: preset == _selectedTimingPreset,
                isEnabled: isValid,
                disabledReason: isValid ? null : 'Too soon',
                onTap: () => Navigator.pop(context, TimingSelection(preset)),
              );
            },
          )
        else
          ...ReminderPreset.values.map(
            (preset) {
              final isValid = preset.isValidFor(widget.sweepStartIso);
              return _OptionRow(
                label: preset.label,
                isSelected: preset == _selectedPreset,
                isEnabled: isValid,
                disabledReason: isValid ? null : 'Too soon',
                onTap: () => Navigator.pop(context, PresetSelection(preset)),
              );
            },
          ),
        _OptionRow(
          label: 'Custom...',
          isSelected: _isCustomSelected,
          isEnabled: _isCustomAvailable,
          disabledReason: _isCustomAvailable ? null : customDisabledReason,
          onTap: _showCustomView,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCustomView() {
    final theme = Theme.of(context);
    final title =
        widget.forTiming ? 'Custom parking reminder' : 'Custom reminder';

    return Column(
      key: const ValueKey('custom'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        Text(
          '${widget.streetName}  ·  ${widget.scheduleDescription}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.textMuted,
          ),
        ),
        const SizedBox(height: 24),
        // Stepper control
        _TimeStepper(
          value: _customLeadMinutes,
          onDecrement:
              _customLeadMinutes > _minMinutes ? _decrementCustom : null,
          onIncrement:
              _customLeadMinutes < _maxAllowedMinutes ? _incrementCustom : null,
        ),
        const SizedBox(height: 12),
        // Preview of notification time
        Text(
          _getNotifyTimePreview(),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.textMuted,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        // Save button
        ElevatedButton(
          onPressed: () =>
              Navigator.pop(context, CustomSelection(_customLeadMinutes)),
          child: const Text('Save reminder'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({
    required this.selected,
    required this.streetName,
    required this.scheduleDescription,
    required this.sweepStartIso,
    this.forTiming = false,
  });

  final ReminderSelection? selected;
  final String streetName;
  final String scheduleDescription;
  final String sweepStartIso;
  final bool forTiming;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  _ReminderView _currentView = _ReminderView.presets;
  late int _customLeadMinutes;

  static const int _maxMinutes = 10080; // 1 week

  int get _stepMinutes => widget.forTiming ? 15 : 30;

  int get _minMinutes =>
      widget.forTiming ? _minLeadTimeMinutesTiming : _minLeadTimeMinutes;

  int get _maxAllowedMinutes {
    final sweepStart = DateTime.parse(widget.sweepStartIso).toLocal();
    final now = DateTime.now();
    final minutesUntilSweep = sweepStart.difference(now).inMinutes;
    final maxAllowed = minutesUntilSweep - _minMinutes;
    final rounded = (maxAllowed ~/ _stepMinutes) * _stepMinutes;
    return rounded.clamp(_minMinutes, _maxMinutes);
  }

  @override
  void initState() {
    super.initState();
    final initialMinutes = switch (widget.selected) {
      CustomSelection(:final leadMinutes) => leadMinutes,
      _ => widget.forTiming
          ? 15
          : 90, // Default to 30min for timing, 1hr 30min for sweeping
    };
    _customLeadMinutes = initialMinutes.clamp(_minMinutes, _maxAllowedMinutes);
  }

  ReminderPreset? get _selectedPreset => switch (widget.selected) {
        PresetSelection(:final preset) => preset,
        _ => null,
      };

  TimingPreset? get _selectedTimingPreset => switch (widget.selected) {
        TimingSelection(:final preset) => preset,
        _ => null,
      };

  bool get _isCustomSelected => widget.selected is CustomSelection;

  bool get _isCustomAvailable {
    final sweepStart = DateTime.parse(widget.sweepStartIso).toLocal();
    final now = DateTime.now();
    return sweepStart.difference(now).inMinutes >= _minMinutes * 2;
  }

  void _showCustomView() {
    setState(() => _currentView = _ReminderView.custom);
  }

  void _decrementCustom() {
    if (_customLeadMinutes > _minMinutes) {
      setState(() => _customLeadMinutes -= _stepMinutes);
    }
  }

  void _incrementCustom() {
    if (_customLeadMinutes < _maxAllowedMinutes) {
      setState(() => _customLeadMinutes += _stepMinutes);
    }
  }

  String _getNotifyTimePreview() {
    try {
      final sweepStart = DateTime.parse(widget.sweepStartIso).toLocal();
      final notifyAt =
          sweepStart.subtract(Duration(minutes: _customLeadMinutes));
      final formatter = DateFormat('EEE, MMM d \'at\' h:mma');
      return formatter.format(notifyAt).toLowerCase();
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _currentView == _ReminderView.presets
            ? Text(
                widget.forTiming
                    ? 'Parking reminder'
                    : 'Street cleaning reminder',
                key: const ValueKey('presets-title'),
              )
            : Text(
                widget.forTiming
                    ? 'Custom parking reminder'
                    : 'Custom reminder',
                key: const ValueKey('custom-title'),
              ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final isCustomView = child.key == const ValueKey('custom');
              final slideOffset = isCustomView
                  ? Tween<Offset>(
                      begin: const Offset(1.0, 0.0),
                      end: Offset.zero,
                    )
                  : Tween<Offset>(
                      begin: const Offset(-1.0, 0.0),
                      end: Offset.zero,
                    );

              return SlideTransition(
                position: slideOffset.animate(animation),
                child: FadeTransition(
                  opacity: animation,
                  child: child,
                ),
              );
            },
            child: _currentView == _ReminderView.presets
                ? _buildPresetsContent()
                : _buildCustomContent(),
          ),
        ),
      ),
      actions: [
        _currentView == _ReminderView.presets
            ? TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(
                        context, CustomSelection(_customLeadMinutes)),
                    child: const Text('Save reminder'),
                  ),
                ],
              ),
      ],
    );
  }

  Widget _buildPresetsContent() {
    final customDisabledReason =
        widget.forTiming ? 'Deadline too soon' : 'Sweep starts too soon';

    return Column(
      key: const ValueKey('presets'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.streetName}  ·  ${widget.scheduleDescription}',
          style: TextStyle(
            color: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.color
                ?.withValues(alpha: 0.7),
          ),
        ),
        if (widget.forTiming)
          ...TimingPreset.values.map(
            (preset) {
              final isValid = preset.isValidFor(widget.sweepStartIso);
              return _OptionRow(
                label: preset.label,
                isSelected: preset == _selectedTimingPreset,
                isEnabled: isValid,
                disabledReason: isValid ? null : 'Too soon',
                onTap: () => Navigator.pop(context, TimingSelection(preset)),
              );
            },
          )
        else
          ...ReminderPreset.values.map(
            (preset) {
              final isValid = preset.isValidFor(widget.sweepStartIso);
              return _OptionRow(
                label: preset.label,
                isSelected: preset == _selectedPreset,
                isEnabled: isValid,
                disabledReason: isValid ? null : 'Too soon',
                onTap: () => Navigator.pop(context, PresetSelection(preset)),
              );
            },
          ),
        _OptionRow(
          label: 'Custom...',
          isSelected: _isCustomSelected,
          isEnabled: _isCustomAvailable,
          disabledReason: _isCustomAvailable ? null : customDisabledReason,
          onTap: _showCustomView,
        ),
      ],
    );
  }

  Widget _buildCustomContent() {
    final theme = Theme.of(context);

    return Column(
      key: const ValueKey('custom'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.streetName}  ·  ${widget.scheduleDescription}',
          style: TextStyle(
            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 24),
        _TimeStepper(
          value: _customLeadMinutes,
          onDecrement:
              _customLeadMinutes > _minMinutes ? _decrementCustom : null,
          onIncrement:
              _customLeadMinutes < _maxAllowedMinutes ? _incrementCustom : null,
        ),
        const SizedBox(height: 12),
        Text(
          _getNotifyTimePreview(),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.textMuted,
          ),
        ),
      ],
    );
  }
}

class _OptionRow extends StatefulWidget {
  const _OptionRow({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isEnabled = true,
    this.disabledReason,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isEnabled;
  final String? disabledReason;

  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
  bool _tapped = false;

  Future<void> _handleTap() async {
    if (!widget.isEnabled) return;
    setState(() => _tapped = true);
    await Future.delayed(const Duration(milliseconds: 150));
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isIOS = theme.platform == TargetPlatform.iOS;

    final showSelected = widget.isSelected || _tapped;
    final isEnabled = widget.isEnabled;

    final backgroundColor = !isEnabled
        ? (isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.black.withValues(alpha: 0.02))
        : showSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.4)
            : isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04);

    final textColor =
        isEnabled ? null : AppTheme.textMuted.withValues(alpha: 0.5);

    final content = Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: showSelected ? FontWeight.w500 : FontWeight.normal,
              color: textColor,
            ),
          ),
          if (!isEnabled && widget.disabledReason != null) ...[
            const SizedBox(height: 2),
            Text(
              widget.disabledReason!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.textMuted.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: isIOS
            ? _IOSTappableRow(
                onTap: isEnabled ? _handleTap : () {},
                child: content,
              )
            : Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: isEnabled ? _handleTap : null,
                  borderRadius: BorderRadius.circular(12),
                  child: content,
                ),
              ),
      ),
    );
  }
}

class _IOSTappableRow extends StatefulWidget {
  const _IOSTappableRow({
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_IOSTappableRow> createState() => _IOSTappableRowState();
}

class _IOSTappableRowState extends State<_IOSTappableRow> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedOpacity(
        opacity: _isPressed ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}

/// Formats lead minutes as a human-readable string for the stepper.
String _formatLeadMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final mins = minutes % 60;

  if (hours == 0) {
    return '$mins min';
  } else if (mins == 0) {
    return '$hours hr';
  } else {
    return '$hours hr $mins min';
  }
}

/// A stepper widget for selecting reminder time in 15/30-minute increments.
class _TimeStepper extends StatelessWidget {
  const _TimeStepper({
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
  });

  final int value;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Decrement button
          _StepperButton(
            icon: Icons.remove,
            onPressed: onDecrement,
          ),
          // Value display
          Expanded(
            child: Text(
              '${_formatLeadMinutes(value)} before',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          // Increment button
          _StepperButton(
            icon: Icons.add,
            onPressed: onIncrement,
          ),
        ],
      ),
    );
  }
}

/// A button for the time stepper (+ or -)
class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isEnabled
                ? colorScheme.primaryContainer.withValues(alpha: 0.6)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: isEnabled
                ? AppTheme.primaryColor
                : AppTheme.textMuted.withValues(alpha: 0.5),
            size: 24,
          ),
        ),
      ),
    );
  }
}
