import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

enum ReminderPreset {
  min30,
  hour1,
  hour2,
  nightBefore;

  /// Convert preset to lead time in minutes for the backend
  int get leadMinutes => switch (this) {
        ReminderPreset.min30 => 30,
        ReminderPreset.hour1 => 60,
        ReminderPreset.hour2 => 120,
        ReminderPreset.nightBefore => 720, // 12 hours
      };

  String get label => switch (this) {
        ReminderPreset.min30 => '30 minutes before',
        ReminderPreset.hour1 => '1 hour before',
        ReminderPreset.hour2 => '2 hours before',
        ReminderPreset.nightBefore => 'Night before',
      };
}

/// Shows a reminder picker that adapts to the platform:
/// - iOS/Android: modal bottom sheet with tappable rows
/// - Web/desktop: dialog with tappable rows
Future<ReminderPreset?> showReminderPicker({
  required BuildContext context,
  required String streetName,
  required String scheduleDescription,
  ReminderPreset? selected,
}) async {
  final width = MediaQuery.of(context).size.width;
  final useDialog = kIsWeb || width >= 700;

  if (useDialog) {
    return showDialog<ReminderPreset>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ReminderDialog(
        selected: selected,
        streetName: streetName,
        scheduleDescription: scheduleDescription,
      ),
    );
  } else {
    return showModalBottomSheet<ReminderPreset>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      enableDrag: true,
      builder: (_) => _ReminderBottomSheet(
        selected: selected,
        streetName: streetName,
        scheduleDescription: scheduleDescription,
      ),
    );
  }
}

class _ReminderBottomSheet extends StatelessWidget {
  const _ReminderBottomSheet({
    required this.selected,
    required this.streetName,
    required this.scheduleDescription,
  });

  final ReminderPreset? selected;
  final String streetName;
  final String scheduleDescription;

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
            const SizedBox(height: 16),
            Text(
              'When should we notify you?',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            ...ReminderPreset.values.map(
              (preset) => _OptionRow(
                preset: preset,
                isSelected: preset == selected,
                onTap: () => Navigator.pop(context, preset),
              ),
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
  });

  final ReminderPreset? selected;
  final String streetName;
  final String scheduleDescription;

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
            const SizedBox(height: 16),
            const Text('When should we notify you?'),
            const SizedBox(height: 8),
            ...ReminderPreset.values.map(
              (preset) => _OptionRow(
                preset: preset,
                isSelected: preset == selected,
                onTap: () => Navigator.pop(context, preset),
              ),
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
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  final ReminderPreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
  bool _tapped = false;

  Future<void> _handleTap() async {
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

    final backgroundColor = showSelected
        ? colorScheme.primaryContainer.withValues(alpha: 0.4)
        : isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04);

    final content = Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Text(
        widget.preset.label,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: showSelected ? FontWeight.w500 : FontWeight.normal,
        ),
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
                onTap: _handleTap,
                child: content,
              )
            : Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _handleTap,
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
