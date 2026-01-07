import 'package:intl/intl.dart';

/// Formats the time until a sweep starts as a human-readable string.
/// Returns strings like "now", "in 5 minutes", "in 2 hours", "in 3 days".
String formatTimeUntil(String startIso) {
  try {
    final startDateTime = DateTime.parse(startIso).toLocal();
    final now = DateTime.now();
    final difference = startDateTime.difference(now);

    if (difference.isNegative) {
      return 'now';
    }

    final totalHours = difference.inHours;
    final totalMinutes = difference.inMinutes;

    if (totalHours >= 48) {
      // More than 48 hours: show "in x days"
      final days = difference.inDays + 1;
      return 'in $days ${days == 1 ? 'day' : 'days'}';
    } else if (totalHours >= 24) {
      // Between 48 and 24 hours: show "in x days and y hours"
      final days = difference.inDays;
      final hours = totalHours - (days * 24);
      return 'in $days ${days == 1 ? 'day' : 'days'} and $hours ${hours == 1 ? 'hour' : 'hours'}';
    } else if (totalHours >= 6) {
      // Between 24 and 6 hours: show "in x hours"
      return 'in $totalHours ${totalHours == 1 ? 'hour' : 'hours'}';
    } else if (totalHours >= 1) {
      // Between 6 hours and 1 hour: show "in x hours and y minutes"
      final hours = totalHours;
      final minutes = totalMinutes - (hours * 60) + 1;
      return 'in $hours ${hours == 1 ? 'hour' : 'hours'} and $minutes ${minutes == 1 ? 'minute' : 'minutes'}';
    } else {
      // Under 1 hour: show "in x minutes"
      return 'in $totalMinutes ${totalMinutes == 1 ? 'minute' : 'minutes'}';
    }
  } catch (e) {
    return '';
  }
}

/// Formats lead minutes as a human-readable reminder description.
/// Returns strings like "30 minutes before", "2 hours before", "1 day before".
/// If sweepStartIso is provided, detects "night before at 9pm" notifications.
String formatLeadTime(int leadMinutes, {String? sweepStartIso}) {
  // Check if this is a "night before at 9pm" notification
  if (sweepStartIso != null) {
    final sweepStart = DateTime.parse(sweepStartIso).toLocal();
    final notifyAt = sweepStart.subtract(Duration(minutes: leadMinutes));
    final nightBefore9pm = DateTime(
      sweepStart.year,
      sweepStart.month,
      sweepStart.day - 1,
      21, // 9pm
    );
    if (notifyAt == nightBefore9pm) {
      return 'the night before at 9pm';
    }
  }

  if (leadMinutes >= 1440) {
    final days = leadMinutes ~/ 1440;
    final remainingMinutes = leadMinutes % 1440;
    final hours = remainingMinutes ~/ 60;
    final mins = remainingMinutes % 60;
    if (hours == 0 && mins == 0) {
      return '$days ${days == 1 ? 'day' : 'days'} before';
    } else if (hours > 0 && mins > 0) {
      return '$days ${days == 1 ? 'day' : 'days'} $hours ${hours == 1 ? 'hour' : 'hours'} $mins ${mins == 1 ? 'minute' : 'minutes'} before';
    } else if (hours > 0) {
      return '$days ${days == 1 ? 'day' : 'days'} $hours ${hours == 1 ? 'hour' : 'hours'} before';
    } else {
      return '$days ${days == 1 ? 'day' : 'days'} $mins ${mins == 1 ? 'minute' : 'minutes'} before';
    }
  } else if (leadMinutes >= 60) {
    final hours = leadMinutes ~/ 60;
    final mins = leadMinutes % 60;
    if (mins == 0) {
      return '$hours ${hours == 1 ? 'hour' : 'hours'} before';
    } else {
      return '$hours ${hours == 1 ? 'hour' : 'hours'} $mins ${mins == 1 ? 'minute' : 'minutes'} before';
    }
  } else if (leadMinutes == 0) {
    return "when it's time to move your car";
  } else {
    return '$leadMinutes ${leadMinutes == 1 ? 'minute' : 'minutes'} before';
  }
}

/// Formats a sweep window as a human-readable date and time range.
/// Returns strings like "Fri, Dec 5 2am-6am".
String formatSweepWindow(String startIso, String endIso) {
  try {
    final startDateTime = DateTime.parse(startIso);
    final endDateTime = DateTime.parse(endIso);

    final dateFormatter = DateFormat('EEE, MMM d');
    final startTimeFormatter = DateFormat('ha');
    final endTimeFormatter = DateFormat('ha');

    final datePart = dateFormatter.format(startDateTime.toLocal());
    final startTime =
        startTimeFormatter.format(startDateTime.toLocal()).toLowerCase();
    final endTime =
        endTimeFormatter.format(endDateTime.toLocal()).toLowerCase();

    return '$datePart $startTime-$endTime';
  } catch (e) {
    return '$startIso-$endIso';
  }
}
