import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/status_banner.dart';

class LocationPage extends StatefulWidget {
  final ValueNotifier<bool> isLoading;
  final String? errorMessage;
  final VoidCallback onRequestLocation;

  const LocationPage({
    super.key,
    required this.isLoading,
    this.errorMessage,
    required this.onRequestLocation,
  });

  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.screenPadding),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: AppTheme.maxContentWidth),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(context),
                      const SizedBox(height: 32),
                      _buildMainCard(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SWEEP DREAMS',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Move your car before the next street sweep',
          style: Theme.of(context).textTheme.displayMedium,
        ),
      ],
    );
  }

  Widget _buildMainCard(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: widget.isLoading,
          builder: (context, isLoading, child) {
            return _LocationButton(
              isLoading: isLoading,
              onPressed: isLoading ? null : widget.onRequestLocation,
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Your location is only used to find nearby schedules.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        if (widget.errorMessage != null) ...[
          const SizedBox(height: 20),
          StatusBanner(
            message: widget.errorMessage!,
            type: StatusType.error,
          ),
        ],
      ],
    );
  }
}

class _LocationButton extends StatefulWidget {
  final bool isLoading;
  final VoidCallback? onPressed;

  const _LocationButton({
    required this.isLoading,
    this.onPressed,
  });

  @override
  State<_LocationButton> createState() => _LocationButtonState();
}

class _LocationButtonState extends State<_LocationButton> {
  bool _isPressed = false;

  static const Color _buttonSurface = Color(0xFFFAF9F7);
  static const Color _textColor = Color(0xFF1A1A1A);
  static const Color _iconColor = Color(0xFF4F63F6);

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;

    return GestureDetector(
      onTapDown: isDisabled ? null : (_) => setState(() => _isPressed = true),
      onTapUp: isDisabled ? null : (_) => setState(() => _isPressed = false),
      onTapCancel: isDisabled ? null : () => setState(() => _isPressed = false),
      onTap: widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        transform: Matrix4.translationValues(0, _isPressed ? 1 : 0, 0),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isDisabled
                ? _buttonSurface.withValues(alpha: 0.6)
                : _buttonSurface,
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.06),
              width: 1,
            ),
            boxShadow: _isPressed || isDisabled
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      offset: const Offset(0, 1),
                      blurRadius: 7,
                    ),
                  ],
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.80),
                  width: 1,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.isLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDisabled
                          ? _iconColor.withValues(alpha: 0.5)
                          : _iconColor,
                    ),
                  )
                else
                  Icon(
                    Icons.my_location,
                    color: isDisabled
                        ? _iconColor.withValues(alpha: 0.5)
                        : _iconColor,
                    size: 20,
                  ),
                const SizedBox(width: 8),
                Text(
                  widget.isLoading ? 'Locating...' : 'Use my location',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isDisabled
                        ? _textColor.withValues(alpha: 0.5)
                        : _textColor,
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
