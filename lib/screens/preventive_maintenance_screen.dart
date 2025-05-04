import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  String _triggerType = 'Time';
  String _statusFilter = 'All';
  String _selectedTab = 'Tasks';
  String? _selectedPredefinedTask;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  @override
  void initState() {
    super.initState();
    _logger.i('PreventiveMaintenanceScreen initialized: facilityId=${widget.facilityId}');
    _setupFCM();
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
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(message.notification?.body ?? 'New notification received')),
      );
    });
  }

  Future<void> _sendPushNotification(String userId, String title, String body) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final fcmToken = userDoc.data()?['fcmToken'] as String?;
      if (fcmToken == null) {
        _logger.w('No FCM token found for user: $userId');
        return;
      }

      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=YOUR_FCM_SERVER_KEY', // Replace with your FCM server key
        },
        body: jsonEncode({
          'to': fcmToken,
          'notification': {
            'title': title,
            'body': body,
          },
          'data': {
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
        }),
      );

      if (response.statusCode == 200) {
        _logger.i('Push notification sent to user: $userId');
      } else {
        _logger.e('Failed to send push notification: ${response.body}');
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
        if (FirebaseAuth.instance.currentUser == null) {
          _logger.e('No user signed in');
          _messengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('Please sign in to add tasks')),
          );
          return;
        }

        final taskId = const Uuid().v4();
        final interval = int.tryParse(_intervalController.text) ?? (_triggerType == 'Time' ? 30 : 1000);
        final nextDue = Timestamp.now();
        final userId = FirebaseAuth.instance.currentUser!.uid;

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

        await FirebaseFirestore.instance
            .collection('notifications')
            .add({
          'userId': userId,
          'title': 'New PM Task Created',
          'body': 'Task "${_taskController.text}" has been scheduled.',
          'timestamp': Timestamp.now(),
          'read': false,
        });

        await _sendPushNotification(
          userId,
          'New PM Task',
          'Task "${_taskController.text}" has been scheduled.',
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
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('PM Task added successfully')),
        );
      } catch (e) {
        _logger.e('Error adding task: $e');
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error adding task: $e')),
        );
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

      await FirebaseFirestore.instance
          .collection('notifications')
          .add({
        'userId': userId,
        'title': 'PM Task Completed',
        'body': 'Task "${doc['taskName']}" has been completed.',
        'timestamp': Timestamp.now(),
        'read': false,
      });

      await _sendPushNotification(
        userId,
        'PM Task Completed',
        'Task "${doc['taskName']}" has been completed.',
      );
      await _sendEmailNotification(
        userId,
        'PM Task Completed',
        'Task "${doc['taskName']}" has been completed for ${widget.facilityId}.',
      );

      _logger.i('Task marked as completed');
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Task marked as completed')),
      );
    } catch (e) {
      _logger.e('Error completing task: $e');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error completing task: $e')),
      );
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
        appBar: AppBar(title: const Text('Preventive Maintenance')),
        body: SafeArea(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () => setState(() => _selectedTab = 'Tasks'),
                    child: Text('Tasks', style: TextStyle(color: _selectedTab == 'Tasks' ? Colors.blue : Colors.grey)),
                  ),
                  ElevatedButton(
                    onPressed: () => setState(() => _selectedTab = 'Notifications'),
                    child: Text('Notifications', style: TextStyle(color: _selectedTab == 'Notifications' ? Colors.blue : Colors.grey)),
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
                      const Text(
                        'Add PM Task',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                            return Text('Error: ${snapshot.error}');
                          }
                          final tasks = snapshot.data?.docs ?? [];
                          return DropdownButtonFormField<String>(
                            value: _selectedPredefinedTask,
                            decoration: const InputDecoration(
                              labelText: 'Select Predefined Task (Optional)',
                              border: OutlineInputBorder(),
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
                                  child: Text(data['title']),
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
                        decoration: const InputDecoration(
                          labelText: 'Task Name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value!.isEmpty ? 'Enter task name' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _triggerType,
                        items: ['Time', 'Meter']
                            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
                        onChanged: (value) => setState(() => _triggerType = value!),
                        decoration: const InputDecoration(
                          labelText: 'Trigger Type',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _intervalController,
                        decoration: InputDecoration(
                          labelText: _triggerType == 'Time' ? 'Interval (days)' : 'Meter Reading',
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) => value!.isEmpty ? 'Enter interval' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _equipmentSuppliedController,
                        decoration: const InputDecoration(
                          labelText: 'Equipment Supplied ID (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _addTask,
                        child: const Text('Add PM Task'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButton<String>(
              value: _statusFilter,
              items: ['All', 'Scheduled', 'Completed', 'Overdue']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (value) => setState(() => _statusFilter = value!),
              underline: Container(),
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: _statusFilter == 'All'
                  ? FirebaseFirestore.instance
                      .collection('facilities')
                      .doc(widget.facilityId)
                      .collection('preventive_maintenance')
                      .orderBy('createdAt', descending: true)
                      .snapshots()
                  : _statusFilter == 'Overdue'
                      ? FirebaseFirestore.instance
                          .collection('facilities')
                          .doc(widget.facilityId)
                          .collection('preventive_maintenance')
                          .where('status', isEqualTo: 'Scheduled')
                          .where('nextDue', isLessThanOrEqualTo: Timestamp.now())
                          .orderBy('nextDue')
                          .snapshots()
                      : FirebaseFirestore.instance
                          .collection('facilities')
                          .doc(widget.facilityId)
                          .collection('preventive_maintenance')
                          .where('status', isEqualTo: _statusFilter)
                          .orderBy('createdAt', descending: true)
                          .snapshots(),
              builder: (context, snapshot) {
                _logger.i('PM Tasks - StreamBuilder: hasData=${snapshot.hasData}, hasError=${snapshot.hasError}');
                if (!snapshot.hasData) {
                  _logger.i('Loading PM tasks...');
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  _logger.e('Firestore error: ${snapshot.error}');
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final docs = snapshot.data!.docs;
                _logger.i('Loaded ${docs.length} PM tasks');
                if (docs.isEmpty) return const Center(child: Text('No tasks found'));
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final nextDue = (doc['nextDue'] as Timestamp?)?.toDate();
                    final isOverdue = nextDue != null && nextDue.isBefore(DateTime.now()) && doc['status'] == 'Scheduled';
                    final history = (doc['history'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
                    return Card(
                      elevation: 1,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: isOverdue ? Colors.red[100] : null,
                      child: ExpansionTile(
                        title: Text(doc['taskName'] ?? 'Unnamed Task'),
                        subtitle: Text(
                          'Status: ${doc['status']} | ${doc['triggerType'] == 'Time' ? 'Interval: ${doc['intervalDays'] ?? 'N/A'} days' : 'Meter: ${doc['meterReading'] ?? 'N/A'} units'}',
                        ),
                        children: [
                          ListTile(
                            title: Text('Description: ${doc['description'] ?? 'N/A'}'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Equipment Supplied ID: ${doc['equipmentSuppliedId'] ?? 'None'}'),
                                Text('Notes: ${doc['notes'] ?? 'N/A'}'),
                                if (nextDue != null)
                                  Text('Next Due: ${DateFormat.yMMMd().format(nextDue)}'),
                                if (isOverdue) const Text('Overdue', style: TextStyle(color: Colors.red)),
                                if (doc['lastPerformed'] != null)
                                  Text(
                                    'Last Performed: ${DateFormat.yMMMd().format((doc['lastPerformed'] as Timestamp).toDate())}',
                                  ),
                                Text('Created: ${DateFormat.yMMMd().format((doc['createdAt'] as Timestamp).toDate())}'),
                              ],
                            ),
                          ),
                          ListTile(
                            title: const Text('History'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: history.isEmpty
                                  ? [const Text('No history available')]
                                  : history
                                      .map((entry) => Text(
                                            '${entry['action']} at ${DateFormat.yMMMd().format((entry['timestamp'] as Timestamp).toDate())}: ${entry['notes'] ?? 'No notes'}',
                                          ))
                                      .toList(),
                            ),
                          ),
                          ListTile(
                            trailing: ElevatedButton(
                              onPressed: doc['status'] == 'Completed'
                                  ? null
                                  : () => showDialog(
                                        context: context,
                                        builder: (context) {
                                          final notesController = TextEditingController();
                                          return AlertDialog(
                                            title: const Text('Complete Task'),
                                            content: TextField(
                                              controller: notesController,
                                              decoration: const InputDecoration(labelText: 'Completion Notes'),
                                              maxLines: 2,
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  _completeTask(doc['taskId'], notesController.text.trim());
                                                  Navigator.pop(context);
                                                },
                                                child: const Text('Complete'),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                              child: const Text('Mark Complete'),
                            ),
                          ),
                        ],
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
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          _logger.e('Notifications error: ${snapshot.error}');
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No notifications found'));
        }

        final notifications = snapshot.data!.docs;
        return ListView.builder(
          itemCount: notifications.length,
          itemBuilder: (context, index) {
            final notification = notifications[index];
            final timestamp = (notification['timestamp'] as Timestamp?)?.toDate();
            return ListTile(
              title: Text(notification['title'] ?? 'Notification'),
              subtitle: Text(notification['body'] ?? 'No details'),
              trailing: timestamp != null
                  ? Text(DateFormat.yMMMd().format(timestamp))
                  : null,
              tileColor: notification['read'] ? null : Colors.blue[50],
              onTap: () async {
                await FirebaseFirestore.instance
                    .collection('notifications')
                    .doc(notification.id)
                    .update({'read': true});
              },
            );
          },
        );
      },
    );
  }
}