import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum StatusType { info, success, error }

class StatusBanner extends StatelessWidget {
  final String message;
  final StatusType type;

  const StatusBanner({
    super.key,
    required this.message,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    Color borderColor;
    IconData icon;

    switch (type) {
      case StatusType.success:
        backgroundColor = AppTheme.successBackground;
        textColor = AppTheme.success;
        borderColor = const Color(0xFFC6E8DA);
        icon = Icons.check_circle_outline;
        break;
      case StatusType.error:
        backgroundColor = AppTheme.errorBackground;
        textColor = AppTheme.error;
        borderColor = const Color(0xFFF8C7D0);
        icon = Icons.error_outline;
        break;
      case StatusType.info:
      default:
        backgroundColor = AppTheme.primarySoft;
        textColor = AppTheme.primaryColor;
        borderColor = AppTheme.border;
        icon = Icons.info_outline;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

