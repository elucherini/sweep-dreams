import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// Minimum lead time in minutes - reminders must be at least this far in the future
const int _minLeadTimeMinutes = 30;

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
        ReminderPreset.nightBefore => 'Night before',
      };
}

/// Result of the reminder picker - either a preset or custom lead minutes
sealed class ReminderSelection {
  const ReminderSelection();

  /// Get the lead minutes for this selection
  int leadMinutesFor(String sweepStartIso) => switch (this) {
        PresetSelection(:final preset) => preset.leadMinutesFor(sweepStartIso),
        CustomSelection(:final leadMinutes) => leadMinutes,
      };
}

class PresetSelection extends ReminderSelection {
  final ReminderPreset preset;
  const PresetSelection(this.preset);
}

class CustomSelection extends ReminderSelection {
  final int leadMinutes;
  const CustomSelection(this.leadMinutes);
}

/// Shows a reminder picker that adapts to the platform:
/// - iOS/Android: modal bottom sheet with tappable rows
/// - Web/desktop: dialog with tappable rows
Future<ReminderSelection?> showReminderPicker({
  required BuildContext context,
  required String streetName,
  required String scheduleDescription,
  required String sweepStartIso,
  ReminderSelection? selected,
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
      ),
    );
  }
}

class _ReminderBottomSheet extends StatelessWidget {
  const _ReminderBottomSheet({
    required this.selected,
    required this.streetName,
    required this.scheduleDescription,
    required this.sweepStartIso,
  });

  final ReminderSelection? selected;
  final String streetName;
  final String scheduleDescription;
  final String sweepStartIso;

  ReminderPreset? get _selectedPreset => switch (selected) {
        PresetSelection(:final preset) => preset,
        _ => null,
      };

  bool get _isCustomSelected => selected is CustomSelection;

  /// Returns true if custom reminder is available (sweep is at least 60 min away)
  bool get _isCustomAvailable {
    final sweepStart = DateTime.parse(sweepStartIso).toLocal();
    final now = DateTime.now();
    // Need at least 30 min buffer + 30 min minimum lead time = 60 min total
    return sweepStart.difference(now).inMinutes >= _minLeadTimeMinutes * 2;
  }

  Future<void> _openCustomPicker(BuildContext context) async {
    final initialMinutes = switch (selected) {
      CustomSelection(:final leadMinutes) => leadMinutes,
      _ => 90, // Default to 1hr 30min
    };

    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      enableDrag: true,
      builder: (_) => _CustomReminderPicker(
        streetName: streetName,
        scheduleDescription: scheduleDescription,
        sweepStartIso: sweepStartIso,
        initialMinutes: initialMinutes,
      ),
    );

    if (result != null && context.mounted) {
      Navigator.pop(context, CustomSelection(result));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Street cleaning reminder',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            Text(
              '$streetName  ·  $scheduleDescription',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            ...ReminderPreset.values.map(
              (preset) {
                final isValid = preset.isValidFor(sweepStartIso);
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
              disabledReason:
                  _isCustomAvailable ? null : 'Sweep starts too soon',
              onTap: () => _openCustomPicker(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ReminderDialog extends StatelessWidget {
  const _ReminderDialog({
    required this.selected,
    required this.streetName,
    required this.scheduleDescription,
    required this.sweepStartIso,
  });

  final ReminderSelection? selected;
  final String streetName;
  final String scheduleDescription;
  final String sweepStartIso;

  ReminderPreset? get _selectedPreset => switch (selected) {
        PresetSelection(:final preset) => preset,
        _ => null,
      };

  bool get _isCustomSelected => selected is CustomSelection;

  /// Returns true if custom reminder is available (sweep is at least 60 min away)
  bool get _isCustomAvailable {
    final sweepStart = DateTime.parse(sweepStartIso).toLocal();
    final now = DateTime.now();
    // Need at least 30 min buffer + 30 min minimum lead time = 60 min total
    return sweepStart.difference(now).inMinutes >= _minLeadTimeMinutes * 2;
  }

  Future<void> _openCustomPicker(BuildContext context) async {
    final initialMinutes = switch (selected) {
      CustomSelection(:final leadMinutes) => leadMinutes,
      _ => 90, // Default to 1hr 30min
    };

    final result = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _CustomReminderDialog(
        streetName: streetName,
        scheduleDescription: scheduleDescription,
        sweepStartIso: sweepStartIso,
        initialMinutes: initialMinutes,
      ),
    );

    if (result != null && context.mounted) {
      Navigator.pop(context, CustomSelection(result));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: const Text('Street cleaning reminder'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$streetName  ·  $scheduleDescription',
              style: TextStyle(
                color: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.color
                    ?.withValues(alpha: 0.7),
              ),
            ),
            ...ReminderPreset.values.map(
              (preset) {
                final isValid = preset.isValidFor(sweepStartIso);
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
              disabledReason:
                  _isCustomAvailable ? null : 'Sweep starts too soon',
              onTap: () => _openCustomPicker(context),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
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

// ============================================================================
// Custom Reminder Picker Widgets
// ============================================================================

/// Formats lead minutes as a human-readable string for the stepper.
/// Returns strings like "30 min", "1 hr", "1 hr 30 min", "2 hr".
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

/// Bottom sheet version of the custom reminder picker with stepper
class _CustomReminderPicker extends StatefulWidget {
  const _CustomReminderPicker({
    required this.streetName,
    required this.scheduleDescription,
    required this.sweepStartIso,
    required this.initialMinutes,
  });

  final String streetName;
  final String scheduleDescription;
  final String sweepStartIso;
  final int initialMinutes;

  @override
  State<_CustomReminderPicker> createState() => _CustomReminderPickerState();
}

class _CustomReminderPickerState extends State<_CustomReminderPicker> {
  late int _leadMinutes;

  static const int _stepMinutes = 30;
  static const int _maxMinutes = 10080; // 1 week

  /// Minimum lead time is always 30 minutes
  int get _minMinutes => _minLeadTimeMinutes;

  /// Calculate the maximum lead minutes based on sweep start time.
  /// The notification time must be at least 30 min from now.
  int get _maxAllowedMinutes {
    final sweepStart = DateTime.parse(widget.sweepStartIso).toLocal();
    final now = DateTime.now();
    final minutesUntilSweep = sweepStart.difference(now).inMinutes;
    // Max lead = minutesUntilSweep - 30 (so notification is 30+ min from now)
    final maxAllowed = minutesUntilSweep - _minLeadTimeMinutes;
    // Round down to nearest step
    final rounded = (maxAllowed ~/ _stepMinutes) * _stepMinutes;
    return rounded.clamp(_minMinutes, _maxMinutes);
  }

  @override
  void initState() {
    super.initState();
    // Clamp initial value to valid range
    _leadMinutes = widget.initialMinutes.clamp(_minMinutes, _maxAllowedMinutes);
  }

  void _decrement() {
    if (_leadMinutes > _minMinutes) {
      setState(() => _leadMinutes -= _stepMinutes);
    }
  }

  void _increment() {
    if (_leadMinutes < _maxAllowedMinutes) {
      setState(() => _leadMinutes += _stepMinutes);
    }
  }

  String _getNotifyTimePreview() {
    try {
      final sweepStart = DateTime.parse(widget.sweepStartIso).toLocal();
      final notifyAt = sweepStart.subtract(Duration(minutes: _leadMinutes));
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
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 8,
          bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with title
            Text(
              'Street cleaning reminder',
              style: theme.textTheme.titleLarge,
            ),
            Text(
              '${widget.streetName} - ${widget.scheduleDescription}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 24),
            // Stepper control
            _TimeStepper(
              value: _leadMinutes,
              onDecrement: _leadMinutes > _minMinutes ? _decrement : null,
              onIncrement:
                  _leadMinutes < _maxAllowedMinutes ? _increment : null,
            ),
            const SizedBox(height: 12),

            // Preview of notification time
            Text(
              _getNotifyTimePreview(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 24),

            // Save button
            ElevatedButton(
              onPressed: () => Navigator.pop(context, _leadMinutes),
              child: const Text('Save reminder'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog version of the custom reminder picker with stepper (for web/desktop)
class _CustomReminderDialog extends StatefulWidget {
  const _CustomReminderDialog({
    required this.streetName,
    required this.scheduleDescription,
    required this.sweepStartIso,
    required this.initialMinutes,
  });

  final String streetName;
  final String scheduleDescription;
  final String sweepStartIso;
  final int initialMinutes;

  @override
  State<_CustomReminderDialog> createState() => _CustomReminderDialogState();
}

class _CustomReminderDialogState extends State<_CustomReminderDialog> {
  late int _leadMinutes;

  static const int _stepMinutes = 30;
  static const int _maxMinutes = 10080; // 1 week

  /// Minimum lead time is always 30 minutes
  int get _minMinutes => _minLeadTimeMinutes;

  /// Calculate the maximum lead minutes based on sweep start time.
  /// The notification time must be at least 30 min from now.
  int get _maxAllowedMinutes {
    final sweepStart = DateTime.parse(widget.sweepStartIso).toLocal();
    final now = DateTime.now();
    final minutesUntilSweep = sweepStart.difference(now).inMinutes;
    // Max lead = minutesUntilSweep - 30 (so notification is 30+ min from now)
    final maxAllowed = minutesUntilSweep - _minLeadTimeMinutes;
    // Round down to nearest step
    final rounded = (maxAllowed ~/ _stepMinutes) * _stepMinutes;
    return rounded.clamp(_minMinutes, _maxMinutes);
  }

  @override
  void initState() {
    super.initState();
    // Clamp initial value to valid range
    _leadMinutes = widget.initialMinutes.clamp(_minMinutes, _maxAllowedMinutes);
  }

  void _decrement() {
    if (_leadMinutes > _minMinutes) {
      setState(() => _leadMinutes -= _stepMinutes);
    }
  }

  void _increment() {
    if (_leadMinutes < _maxAllowedMinutes) {
      setState(() => _leadMinutes += _stepMinutes);
    }
  }

  String _getNotifyTimePreview() {
    try {
      final sweepStart = DateTime.parse(widget.sweepStartIso).toLocal();
      final notifyAt = sweepStart.subtract(Duration(minutes: _leadMinutes));
      final formatter = DateFormat('EEE, MMM d \'at\' h:mma');
      return formatter.format(notifyAt).toLowerCase();
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      title: const Text('Street cleaning reminder'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.streetName} - ${widget.scheduleDescription}',
              style: TextStyle(
                color:
                    theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            _TimeStepper(
              value: _leadMinutes,
              onDecrement: _leadMinutes > _minMinutes ? _decrement : null,
              onIncrement:
                  _leadMinutes < _maxAllowedMinutes ? _increment : null,
            ),
            const SizedBox(height: 12),
            Text(
              _getNotifyTimePreview(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context, _leadMinutes),
              child: const Text('Save reminder'),
            ),
          ],
        ),
      ],
    );
  }
}

/// A stepper widget for selecting reminder time in 30-minute increments
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
