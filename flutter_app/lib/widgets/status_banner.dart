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
    Color accentColor;
    Color textColor;
    Color borderColor;
    IconData icon;

    switch (type) {
      case StatusType.success:
        backgroundColor = AppTheme.successBackground;
        accentColor = AppTheme.success;
        textColor = AppTheme.success;
        borderColor = const Color(0xFFE9D5FF); // purple-200
        icon = Icons.check_circle;
      case StatusType.error:
        backgroundColor = AppTheme.errorBackground;
        accentColor = AppTheme.error;
        textColor = AppTheme.error;
        borderColor = const Color(0xFFFECDD3); // rose-200
        icon = Icons.error;
      case StatusType.info:
        backgroundColor = AppTheme.primarySoft;
        accentColor = AppTheme.primaryColor;
        textColor = AppTheme.primaryColor;
        borderColor = AppTheme.border;
        icon = Icons.info;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            backgroundColor,
            backgroundColor.withValues(alpha: 0.7),
          ],
        ),
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: textColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
