import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/notifications/models/notification_model.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:cmms/notifications/screens/notification_detail_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class FloatingNotificationWidget extends StatefulWidget {
  const FloatingNotificationWidget({super.key});

  @override
  State<FloatingNotificationWidget> createState() => _FloatingNotificationWidgetState();
}

class _FloatingNotificationWidgetState extends State<FloatingNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    // WhatsApp-like slide animation from top
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GroupedNotificationModel>>(
      stream: NotificationService().getTodaysTriggeredNotifications(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final notifications = snapshot.data!;
        if (notifications.isEmpty) {
          return const SizedBox.shrink();
        }

        // Only show the latest notification for today
        final latestNotification = notifications.first;
        final categories = <String>{};
        
        for (final notification in latestNotification.notifications) {
          categories.add(notification.category);
        }

        if (categories.isEmpty) {
          return const SizedBox.shrink();
        }

        // Trigger animation when notifications appear
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_animationController.isAnimating && !_animationController.isCompleted) {
            _animationController.forward();
          }
        });

        return Positioned(
          top: kIsWeb ? 20 : MediaQuery.of(context).padding.top + 10,
          left: 16,
          right: 16,
          child: SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Material(
                  elevation: 12,
                  borderRadius: BorderRadius.circular(16),
                  shadowColor: Colors.black.withValues(alpha: 0.3),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.blueGrey[600]!,
                          Colors.blueGrey[800]!,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: InkWell(
                      onTap: () => _openNotificationDetails(context, latestNotification),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // Animated notification icon
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 2,
                                ),
                              ),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 1000),
                                builder: (context, value, child) {
                                  return Transform.scale(
                                    scale: 0.8 + (0.2 * value),
                                    child: const Icon(
                                      Icons.notifications_active,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            
                            // Content
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        '🔧 Maintenance Alert',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          'NOW',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tasks due today: ${categories.join(', ')}',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.touch_app,
                                        color: Colors.white.withValues(alpha: 0.7),
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Tap to view details',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white.withValues(alpha: 0.7),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(width: 8),
                            
                            // Close button
                            GestureDetector(
                              onTap: _dismissNotification,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openNotificationDetails(BuildContext context, GroupedNotificationModel notification) {
    // Reset notification count when opened
    NotificationService().resetNotificationCount();
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NotificationDetailScreen(notification: notification),
      ),
    );
  }

  void _dismissNotification() {
    _animationController.reverse().then((_) {
      // Reset notification count when dismissed
      NotificationService().resetNotificationCount();
    });
  }
}