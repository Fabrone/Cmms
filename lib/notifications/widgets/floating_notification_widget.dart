import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/notifications/models/notification_model.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:cmms/notifications/screens/notification_detail_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';

class FloatingNotificationWidget extends StatefulWidget {
  const FloatingNotificationWidget({super.key});

  @override
  State<FloatingNotificationWidget> createState() => _FloatingNotificationWidgetState();
}

class _FloatingNotificationWidgetState extends State<FloatingNotificationWidget>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late AnimationController _shakeController;
  
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _shakeAnimation;

  Timer? _dismissTimer;
  Timer? _pulseTimer;
  bool _isDismissed = false;
  bool _isPersistent = false;

  @override
  void initState() {
    super.initState();
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Enhanced slide animation with bounce
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -2.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.elasticOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.elasticOut,
    ));

    // Pulsing animation for urgent notifications
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // Shake animation for critical notifications
    _shakeAnimation = Tween<double>(
      begin: -5.0,
      end: 5.0,
    ).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.elasticInOut,
    ));
  }

  @override
  void dispose() {
    _slideController.dispose();
    _pulseController.dispose();
    _shakeController.dispose();
    _dismissTimer?.cancel();
    _pulseTimer?.cancel();
    super.dispose();
  }

  void _startAnimations(NotificationPriority priority) {
    if (_isDismissed) return;

    _slideController.forward();

    // Start pulsing for urgent notifications
    if (priority == NotificationPriority.urgent || priority == NotificationPriority.critical) {
      _isPersistent = true;
      _pulseController.repeat(reverse: true);
      
      // Shake for critical notifications
      if (priority == NotificationPriority.critical) {
        _shakeController.repeat(reverse: true);
      }
    } else {
      // Auto-dismiss normal notifications after 10 seconds
      _dismissTimer = Timer(const Duration(seconds: 10), () {
        if (!_isDismissed && mounted) {
          _dismissNotification();
        }
      });
    }
  }

  void _dismissNotification() {
    if (_isDismissed) return;
    
    setState(() {
      _isDismissed = true;
    });

    _slideController.reverse().then((_) {
      NotificationService().resetNotificationCount();
    });

    _pulseController.stop();
    _shakeController.stop();
    _dismissTimer?.cancel();
    _pulseTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GroupedNotificationModel>>(
      stream: NotificationService().getActiveNotifications(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty || _isDismissed) {
          return const SizedBox.shrink();
        }

        final notifications = snapshot.data!;
        if (notifications.isEmpty) {
          return const SizedBox.shrink();
        }

        // Get the most recent/urgent notification
        final latestNotification = notifications.first;
        final allItems = latestNotification.allItems;
        final categories = allItems.map((item) => item.category).toSet().toList();
        
        if (categories.isEmpty) {
          return const SizedBox.shrink();
        }

        // Determine priority and notification type
        final hasAlerts = latestNotification.hasAlerts;
        final priority = hasAlerts ? NotificationPriority.urgent : NotificationPriority.normal;
        final isOverdue = DateTime.now().isAfter(latestNotification.notificationDate.add(const Duration(days: 1)));
        final effectivePriority = isOverdue ? NotificationPriority.critical : priority;

        // Start animations when notification appears
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_slideController.isAnimating && !_slideController.isCompleted) {
            _startAnimations(effectivePriority);
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
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: AnimatedBuilder(
                        animation: _shakeAnimation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(_shakeAnimation.value, 0),
                            child: _buildNotificationBanner(
                              latestNotification,
                              categories,
                              effectivePriority,
                              hasAlerts,
                              isOverdue,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotificationBanner(
    GroupedNotificationModel notification,
    List<String> categories,
    NotificationPriority priority,
    bool hasAlerts,
    bool isOverdue,
  ) {
    Color backgroundColor;
    Color accentColor;
    IconData iconData;
    String statusText;
    String emoji;

    if (isOverdue) {
      backgroundColor = Colors.red[700]!;
      accentColor = Colors.red[900]!;
      iconData = Icons.error;
      statusText = 'OVERDUE';
      emoji = '🚨';
    } else if (hasAlerts) {
      backgroundColor = Colors.orange[600]!;
      accentColor = Colors.orange[800]!;
      iconData = Icons.warning;
      statusText = 'ALERT';
      emoji = '⚠️';
    } else {
      backgroundColor = Colors.blueGrey[600]!;
      accentColor = Colors.blueGrey[800]!;
      iconData = Icons.notifications_active;
      statusText = 'REMINDER';
      emoji = '🔧';
    }

    return Material(
      elevation: 16,
      borderRadius: BorderRadius.circular(16),
      shadowColor: Colors.black.withValues(alpha: 0.4),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [backgroundColor, accentColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: backgroundColor.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: InkWell(
          onTap: () => _openNotificationDetails(context, notification),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    // Animated notification icon
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 1200),
                        builder: (context, value, child) {
                          return Transform.rotate(
                            angle: value * 0.1,
                            child: Icon(
                              iconData,
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
                        children: [
                          Row(
                            children: [
                              Text(
                                '$emoji Maintenance $statusText',
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
                                  _isPersistent ? 'URGENT' : 'NOW',
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
                            hasAlerts 
                                ? '${notification.alerts.length} tasks due tomorrow!'
                                : '${notification.notifications.length} tasks due: ${categories.take(2).join(', ')}${categories.length > 2 ? '...' : ''}',
                            style: GoogleFonts.poppins(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
                
                const SizedBox(height: 12),
                
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.touch_app,
                              color: Colors.white.withValues(alpha: 0.8),
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Tap to view details',
                              style: GoogleFonts.poppins(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openNotificationDetails(BuildContext context, GroupedNotificationModel notification) {
    // Reset notification count when opened
    NotificationService().resetNotificationCount();
    
    // Mark as read
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      NotificationService().markNotificationAsReadByUser(notification.id, user.uid);
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NotificationDetailScreen(notification: notification),
      ),
    );

    // Dismiss the floating notification
    _dismissNotification();
  }
}
