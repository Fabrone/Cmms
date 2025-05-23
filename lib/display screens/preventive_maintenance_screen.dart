import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';

class PreventiveMaintenanceScreen extends StatefulWidget {
  final String facilityId;

  const PreventiveMaintenanceScreen({super.key, required this.facilityId});

  @override
  State<PreventiveMaintenanceScreen> createState() => _PreventiveMaintenanceScreenState();
}

class _PreventiveMaintenanceScreenState extends State<PreventiveMaintenanceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _taskController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _intervalController = TextEditingController();
  final _equipmentSuppliedController = TextEditingController();
  final _notesController = TextEditingController();
  final Logger _logger = Logger(printer: PrettyPrinter());
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  String _triggerType = 'Time';
  String _statusFilter = 'All';
  String _selectedTab = 'Tasks';
  String? _selectedPredefinedTask;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _logger.i('PreventiveMaintenanceScreen initialized: facilityId=${widget.facilityId}');
    _setupFCM();
    _handleInitialNotification();
  }

  Future<void> _setupFCM() async {
    await _firebaseMessaging.requestPermission();
    String? token = await _firebaseMessaging.getToken();
    if (token != null && FirebaseAuth.instance.currentUser != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
      _logger.i('FCM token saved for user: ${FirebaseAuth.instance.currentUser!.uid}');
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _logger.i('Received foreground notification: ${message.notification?.title}');
      RemoteNotification? notification = message.notification;
      if (notification != null) {
        _flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'maintenance_reminders',
              'Maintenance Reminders',
              channelDescription: 'Notifications for scheduled and preventive maintenance tasks',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
        if (mounted) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text(notification.body ?? 'New notification received', style: GoogleFonts.poppins())),
          );
        }
      }
    });
  }

  Future<void> _handleInitialNotification() async {
    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null && mounted) {
      _handleNotificationTap(initialMessage);
    }
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
  }

  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    if (data['screen'] == 'preventive_maintenance_notifications' && mounted) {
      setState(() {
        _selectedTab = 'Notifications';
      });
    }
  }

  Future<void> _sendPushNotification(String userId, String title, String body, String taskId, String facilityId) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final fcmToken = userDoc.data()?['fcmToken'] as String?;
      if (fcmToken == null) {
        _logger.w('No FCM token found for user: $userId');
        return;
      }

      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('sendMaintenanceNotification');
      final response = await callable.call({
        'token': fcmToken,
        'title': title,
        'body': body,
        'taskId': taskId,
        'facilityId': facilityId,
        'screen': 'preventive_maintenance_notifications',
      });

      if (response.data['result'] == 'Message sent') {
        _logger.i('Push notification sent to user: $userId');
      } else {
        _logger.e('Failed to send push notification: ${response.data}');
      }
    } catch (e) {
      _logger.e('Error sending push notification: $e');
    }
  }

  Future<void> _sendEmailNotification(String userId, String subject, String message) async {
    try {
      final user = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final email = user.data()?['email'] as String?;
      if (email == null) {
        _logger.w('No email found for user: $userId');
        return;
      }
      _logger.i('Email notification queued for $email: $subject');
    } catch (e) {
      _logger.e('Error sending email notification: $e');
    }
  }

  Future<void> _addTask() async {
    if (_formKey.currentState!.validate()) {
      try {
        _logger.i('Adding PM task: name=${_taskController.text}, facilityId=${widget.facilityId}');
        final userId = FirebaseAuth.instance.currentUser!.uid;
        final taskId = const Uuid().v4();
        final interval = int.tryParse(_intervalController.text) ?? (_triggerType == 'Time' ? 30 : 1000);
        final now = DateTime.now();
        final nextDue = _triggerType == 'Time'
            ? Timestamp.fromDate(now.add(Duration(days: interval)))
            : Timestamp.now();

        await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('preventive_maintenance')
            .doc(taskId)
            .set({
          'taskId': taskId,
          'taskName': _taskController.text.trim(),
          'description': _descriptionController.text.trim(),
          'intervalDays': _triggerType == 'Time' ? interval : null,
          'meterReading': _triggerType == 'Meter' ? interval : null,
          'triggerType': _triggerType,
          'equipmentSuppliedId': _equipmentSuppliedController.text.trim(),
          'status': 'Scheduled',
          'notes': _notesController.text.trim(),
          'lastPerformed': null,
          'nextDue': nextDue,
          'createdAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
          'createdBy': userId,
          'history': [
            {
              'action': 'Created',
              'timestamp': Timestamp.now(),
              'notes': _notesController.text.trim(),
            }
          ],
        });

        await FirebaseFirestore.instance.collection('notifications').add({
          'userId': userId,
          'title': 'New PM Task Created',
          'body': 'Task "${_taskController.text}" has been scheduled.',
          'taskId': taskId,
          'facilityId': widget.facilityId,
          'timestamp': Timestamp.now(),
          'read': false,
        });

        await _sendPushNotification(
          userId,
          'CMMS: New PM Task',
          'Task "${_taskController.text}" has been scheduled.',
          taskId,
          widget.facilityId,
        );
        await _sendEmailNotification(
          userId,
          'New PM Task Created',
          'Task "${_taskController.text}" has been scheduled for ${widget.facilityId}.',
        );

        _taskController.clear();
        _descriptionController.clear();
        _intervalController.clear();
        _equipmentSuppliedController.clear();
        _notesController.clear();
        setState(() {
          _selectedPredefinedTask = null;
        });
        if (mounted) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('PM Task added successfully', style: GoogleFonts.poppins())),
          );
        }
      } catch (e) {
        _logger.e('Error adding task: $e');
        if (mounted) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Error adding task: $e', style: GoogleFonts.poppins())),
          );
        }
      }
    }
  }

  Future<void> _completeTask(String docId, String notes) async {
    try {
      _logger.i('Completing task: docId=$docId, facilityId=${widget.facilityId}');
      final now = Timestamp.now();
      final doc = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('preventive_maintenance')
          .doc(docId)
          .get();
      final intervalDays = doc.data()!['intervalDays'] as int? ?? 30;
      final userId = FirebaseAuth.instance.currentUser!.uid;

      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('preventive_maintenance')
          .doc(docId)
          .update({
        'status': 'Completed',
        'lastPerformed': now,
        'nextDue': Timestamp.fromDate(now.toDate().add(Duration(days: intervalDays))),
        'updatedAt': Timestamp.now(),
        'history': FieldValue.arrayUnion([
          {
            'action': 'Completed',
            'timestamp': now,
            'notes': notes,
            'userId': userId,
          }
        ]),
      });

      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': userId,
        'title': 'PM Task Completed',
        'body': 'Task "${doc['taskName']}" has been completed.',
        'taskId': docId,
        'facilityId': widget.facilityId,
        'timestamp': Timestamp.now(),
        'read': false,
      });

      await _sendPushNotification(
        userId,
        'CMMS: PM Task Completed',
        'Task "${doc['taskName']}" has been completed.',
        docId,
        widget.facilityId,
      );
      await _sendEmailNotification(
        userId,
        'PM Task Completed',
        'Task "${doc['taskName']}" has been completed for ${widget.facilityId}.',
      );

      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Task marked as completed', style: GoogleFonts.poppins())),
        );
      }
      _logger.i('Task marked as completed');
    } catch (e) {
      _logger.e('Error completing task: $e');
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error completing task: $e', style: GoogleFonts.poppins())),
        );
      }
    }
  }

  Future<void> _markNotificationAsRead(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({'read': true});
      _logger.i('Marked notification as read: $notificationId');
    } catch (e) {
      _logger.e('Error marking notification as read: $e');
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error updating notification: $e', style: GoogleFonts.poppins())),
        );
      }
    }
  }

  @override
  void dispose() {
    _taskController.dispose();
    _descriptionController.dispose();
    _intervalController.dispose();
    _equipmentSuppliedController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _logger.i('Building PreventiveMaintenanceScreen: facilityId=${widget.facilityId}');
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Preventive Maintenance', style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: Colors.blueGrey,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('notifications')
                        .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                        .where('read', isEqualTo: false)
                        .snapshots(),
                    builder: (context, snapshot) {
                      int unreadCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
                      return Stack(
                        children: [
                          ElevatedButton(
                            onPressed: () => setState(() => _selectedTab = 'Tasks'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _selectedTab == 'Tasks' ? Colors.blueGrey[100] : Colors.white,
                            ),
                            child: Text(
                              'Tasks',
                              style: GoogleFonts.poppins(
                                color: _selectedTab == 'Tasks' ? Colors.blueGrey[800] : Colors.grey,
                              ),
                            ),
                          ),
                          if (unreadCount > 0 && _selectedTab == 'Notifications')
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '$unreadCount',
                                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('notifications')
                        .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                        .where('read', isEqualTo: false)
                        .snapshots(),
                    builder: (context, snapshot) {
                      int unreadCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
                      return Stack(
                        children: [
                          ElevatedButton(
                            onPressed: () => setState(() => _selectedTab = 'Notifications'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _selectedTab == 'Notifications' ? Colors.blueGrey[100] : Colors.white,
                            ),
                            child: Text(
                              'Notifications',
                              style: GoogleFonts.poppins(
                                color: _selectedTab == 'Notifications' ? Colors.blueGrey[800] : Colors.grey,
                              ),
                            ),
                          ),
                          if (unreadCount > 0)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '$unreadCount',
                                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
              Expanded(
                child: _selectedTab == 'Tasks'
                    ? _buildTasksTab()
                    : _buildNotificationsTab(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTasksTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add PM Task',
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('facilities')
                            .doc(widget.facilityId)
                            .collection('predefined_tasks')
                            .orderBy('createdAt', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const CircularProgressIndicator();
                          }
                          if (snapshot.hasError) {
                            _logger.e('Error loading predefined tasks: ${snapshot.error}');
                            return Text('Error: ${snapshot.error}', style: GoogleFonts.poppins());
                          }
                          final tasks = snapshot.data?.docs ?? [];
                          return DropdownButtonFormField<String>(
                            value: _selectedPredefinedTask,
                            decoration: InputDecoration(
                              labelText: 'Select Predefined Task (Optional)',
                              border: const OutlineInputBorder(),
                              labelStyle: GoogleFonts.poppins(),
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text('None'),
                              ),
                              ...tasks.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return DropdownMenuItem<String>(
                                  value: data['title'],
                                  child: Text(data['title'], style: GoogleFonts.poppins()),
                                );
                              }),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedPredefinedTask = value;
                                if (value != null) {
                                  final selectedTask = tasks.firstWhere((doc) => (doc.data() as Map<String, dynamic>)['title'] == value);
                                  _taskController.text = selectedTask['title'];
                                  _descriptionController.text = selectedTask['description'] ?? '';
                                } else {
                                  _taskController.clear();
                                  _descriptionController.clear();
                                }
                              });
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _taskController,
                        decoration: InputDecoration(
                          labelText: 'Task Name',
                          border: const OutlineInputBorder(),
                          labelStyle: GoogleFonts.poppins(),
                        ),
                        style: GoogleFonts.poppins(),
                        validator: (value) => value!.isEmpty ? 'Enter task name' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: InputDecoration(
                          labelText: 'Description',
                          border: const OutlineInputBorder(),
                          labelStyle: GoogleFonts.poppins(),
                        ),
                        style: GoogleFonts.poppins(),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _triggerType,
                        items: ['Time', 'Meter']
                            .map((t) => DropdownMenuItem(value: t, child: Text(t, style: GoogleFonts.poppins())))
                            .toList(),
                        onChanged: (value) => setState(() => _triggerType = value!),
                        decoration: InputDecoration(
                          labelText: 'Trigger Type',
                          border: const OutlineInputBorder(),
                          labelStyle: GoogleFonts.poppins(),
                        ),
                        style: GoogleFonts.poppins(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _intervalController,
                        decoration: InputDecoration(
                          labelText: _triggerType == 'Time' ? 'Interval (days)' : 'Meter Reading',
                          border: const OutlineInputBorder(),
                          labelStyle: GoogleFonts.poppins(),
                        ),
                        style: GoogleFonts.poppins(),
                        keyboardType: TextInputType.number,
                        validator: (value) => value!.isEmpty ? 'Enter interval' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _equipmentSuppliedController,
                        decoration: InputDecoration(
                          labelText: 'Equipment Supplied ID (optional)',
                          border: const OutlineInputBorder(),
                          labelStyle: GoogleFonts.poppins(),
                        ),
                        style: GoogleFonts.poppins(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notesController,
                        decoration: InputDecoration(
                          labelText: 'Notes (optional)',
                          border: const OutlineInputBorder(),
                          labelStyle: GoogleFonts.poppins(),
                        ),
                        style: GoogleFonts.poppins(),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _addTask,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey[800],
                          foregroundColor: Colors.white,
                        ),
                        child: Text('Add PM Task', style: GoogleFonts.poppins()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Scheduled Maintenance Tasks',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: _statusFilter,
              items: ['All', 'Scheduled', 'Completed']
                  .map((status) => DropdownMenuItem(value: status, child: Text(status, style: GoogleFonts.poppins())))
                  .toList(),
              onChanged: (value) => setState(() => _statusFilter = value!),
              style: GoogleFonts.poppins(),
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: _statusFilter == 'All'
                  ? FirebaseFirestore.instance
                      .collection('facilities')
                      .doc(widget.facilityId)
                      .collection('preventive_maintenance')
                      .orderBy('createdAt', descending: true)
                      .snapshots()
                  : FirebaseFirestore.instance
                      .collection('facilities')
                      .doc(widget.facilityId)
                      .collection('preventive_maintenance')
                      .where('status', isEqualTo: _statusFilter)
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  _logger.e('Error loading tasks: ${snapshot.error}');
                  return Text('Error: ${snapshot.error}', style: GoogleFonts.poppins());
                }
                final tasks = snapshot.data?.docs ?? [];
                if (tasks.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('No tasks found', style: GoogleFonts.poppins()),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index].data() as Map<String, dynamic>;
                    final docId = tasks[index].id;
                    final nextDue = (task['nextDue'] as Timestamp?)?.toDate();
                    final status = task['status'] as String? ?? 'Scheduled';
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(task['taskName'] ?? 'Unnamed Task', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(task['description'] ?? 'No description', style: GoogleFonts.poppins()),
                            Text(
                              'Next Due: ${nextDue != null ? DateFormat.yMMMd().format(nextDue) : 'N/A'}',
                              style: GoogleFonts.poppins(),
                            ),
                            Text('Status: $status', style: GoogleFonts.poppins()),
                          ],
                        ),
                        trailing: status == 'Scheduled'
                            ? IconButton(
                                icon: const Icon(Icons.check_circle, color: Colors.green),
                                onPressed: () async {
                                  final notesController = TextEditingController();
                                  final bool? confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text('Complete Task', style: GoogleFonts.poppins()),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('Enter notes for task completion:', style: GoogleFonts.poppins()),
                                          TextField(
                                            controller: notesController,
                                            decoration: InputDecoration(
                                              labelText: 'Notes',
                                              border: const OutlineInputBorder(),
                                              labelStyle: GoogleFonts.poppins(),
                                            ),
                                            style: GoogleFonts.poppins(),
                                            maxLines: 3,
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: Text('Cancel', style: GoogleFonts.poppins()),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: Text('Complete', style: GoogleFonts.poppins()),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    await _completeTask(docId, notesController.text.trim());
                                  }
                                  notesController.dispose();
                                },
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notifications',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                  .where('facilityId', isEqualTo: widget.facilityId)
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  _logger.e('Error loading notifications: ${snapshot.error}');
                  return Text('Error: ${snapshot.error}', style: GoogleFonts.poppins());
                }
                final notifications = snapshot.data?.docs ?? [];
                if (notifications.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('No notifications found', style: GoogleFonts.poppins()),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final notification = notifications[index].data() as Map<String, dynamic>;
                    final notificationId = notifications[index].id;
                    final isRead = notification['read'] as bool? ?? false;
                    final timestamp = (notification['timestamp'] as Timestamp?)?.toDate();
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: isRead ? Colors.white : Colors.blueGrey[50],
                      child: ListTile(
                        title: Text(notification['title'] ?? 'No Title', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(notification['body'] ?? 'No Body', style: GoogleFonts.poppins()),
                            Text(
                              timestamp != null ? DateFormat.yMMMd().add_jm().format(timestamp) : 'N/A',
                              style: GoogleFonts.poppins(fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: !isRead
                            ? IconButton(
                                icon: const Icon(Icons.mark_email_read, color: Colors.green),
                                onPressed: () => _markNotificationAsRead(notificationId),
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}