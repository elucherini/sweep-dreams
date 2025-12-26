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
}

/// Shows a reminder picker that adapts to the platform:
/// - iOS/Android: modal bottom sheet with choice chips
/// - Web/desktop: dialog with radio buttons
Future<ReminderPreset?> showReminderPicker({
  required BuildContext context,
  required String streetName,
  required String scheduleDescription,
  ReminderPreset initial = ReminderPreset.hour1,
}) async {
  final width = MediaQuery.of(context).size.width;
  final useDialog = kIsWeb || width >= 700;

  if (useDialog) {
    return showDialog<ReminderPreset>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ReminderDialog(
        initial: initial,
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
      builder: (_) => _ReminderBottomSheet(
        initial: initial,
        streetName: streetName,
        scheduleDescription: scheduleDescription,
      ),
    );
  }
}

class _ReminderBottomSheet extends StatefulWidget {
  const _ReminderBottomSheet({
    required this.initial,
    required this.streetName,
    required this.scheduleDescription,
  });

  final ReminderPreset initial;
  final String streetName;
  final String scheduleDescription;

  @override
  State<_ReminderBottomSheet> createState() => _ReminderBottomSheetState();
}

class _ReminderBottomSheetState extends State<_ReminderBottomSheet> {
  late ReminderPreset selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Street cleaning reminder',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            '${widget.streetName}  ·  ${widget.scheduleDescription}',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          const Text('When should we notify you?'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _choiceChip(ReminderPreset.min30, '30 min before'),
              _choiceChip(ReminderPreset.hour1, '1 hour before'),
              _choiceChip(ReminderPreset.hour2, '2 hours before'),
              _choiceChip(ReminderPreset.nightBefore, 'Night before'),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Save reminder'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _choiceChip(ReminderPreset value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: selected == value,
      onSelected: (_) => setState(() => selected = value),
    );
  }
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({
    required this.initial,
    required this.streetName,
    required this.scheduleDescription,
  });

  final ReminderPreset initial;
  final String streetName;
  final String scheduleDescription;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  late ReminderPreset selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: [
          const Expanded(
            child: Text('Street cleaning reminder'),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.streetName}  ·  ${widget.scheduleDescription}',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            const Text('When should we notify you?'),
            const SizedBox(height: 8),
            _radio(ReminderPreset.min30, '30 minutes before'),
            _radio(ReminderPreset.hour1, '1 hour before'),
            _radio(ReminderPreset.hour2, '2 hours before'),
            _radio(ReminderPreset.nightBefore, 'Night before'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, selected),
          child: const Text('Save reminder'),
        ),
      ],
    );
  }

  Widget _radio(ReminderPreset value, String label) {
    return RadioListTile<ReminderPreset>(
      value: value,
      groupValue: selected,
      onChanged: (v) => setState(() => selected = v!),
      title: Text(label),
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }
}
