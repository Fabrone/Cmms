import 'dart:io';
import 'package:cmms/models/maintenance_task.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class ScheduleMaintenanceScreen extends StatefulWidget {
  const ScheduleMaintenanceScreen({super.key});

  @override
  ScheduleMaintenanceScreenState createState() => ScheduleMaintenanceScreenState();
}

class ScheduleMaintenanceScreenState extends State<ScheduleMaintenanceScreen> {
  ScheduleMaintenanceScreenState(); // Unnamed constructor
  final logger = Logger(printer: PrettyPrinter());
  final _formKey = GlobalKey<FormState>();
  final _categoryController = TextEditingController();
  final _componentController = TextEditingController();
  final _interventionController = TextEditingController();
  final _frequencyController = TextEditingController();
  final FocusNode _categoryFocus = FocusNode();
  final FocusNode _componentFocus = FocusNode();
  bool _isDocumentSectionExpanded = false;
  List<String> _categorySuggestions = [];
  final List<String> _commonCategories = [
    'Civil',
    'Electrical',
    'Water Sanitation',
    'Cooling',
  ];

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _categoryController.addListener(_updateCategorySuggestions);
  }

  void _updateCategorySuggestions() {
    final query = _categoryController.text.toLowerCase();
    setState(() {
      _categorySuggestions = _commonCategories
          .where((category) => category.toLowerCase().contains(query))
          .toList();
    });
  }

  Future<void> _uploadDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please log in to upload documents', style: GoogleFonts.poppins())),
          );
        }
        return;
      }

      // Upload to Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('documents/${user.uid}/${DateTime.now().millisecondsSinceEpoch}_$fileName');
      final uploadTask = await storageRef.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      // Save metadata to Firestore
      await FirebaseFirestore.instance.collection('documents').add({
        'userId': user.uid,
        'fileName': fileName,
        'downloadUrl': downloadUrl,
        'uploadedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Document uploaded successfully', style: GoogleFonts.poppins())),
        );
      }
      logger.i('Uploaded document: $fileName, URL: $downloadUrl');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading document: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error uploading document: $e');
    }
  }

  Future<void> _openDocument(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open document', style: GoogleFonts.poppins())),
          );
        }
        logger.e('Could not launch URL: $url');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening document: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error opening document: $e');
    }
  }

  Future<void> _scheduleNotification(MaintenanceTask task, String taskId) async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    // Check notification permission
    bool? notificationsEnabled = await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    if (notificationsEnabled != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Notification permission denied', style: GoogleFonts.poppins())),
        );
      }
      logger.w('Notification permission not granted');
      return;
    }

    // Check exact alarm permission (Android 12+)
    bool canScheduleExact = true;
    AndroidScheduleMode scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      canScheduleExact = await androidPlugin.canScheduleExactNotifications() ?? false;
      if (!canScheduleExact) {
        scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Exact alarm permission denied, using inexact scheduling',
                style: GoogleFonts.poppins(),
              ),
            ),
          );
        }
        logger.w('Exact alarm permission not granted, falling back to inexact scheduling');
      }
    }

    const androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'maintenance_channel',
      'Maintenance Reminders',
      channelDescription: 'Notifications for scheduled maintenance tasks',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      enableVibration: true,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('default'),
    );
    const platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    // Calculate reminder date: createdAt + frequency months - 1 week
    final reminderDate = tz.TZDateTime.from(
      task.createdAt.add(Duration(days: (task.frequency * 30) - 7)),
      tz.local,
    );
    final now = tz.TZDateTime.now(tz.local);
    if (reminderDate.isBefore(now)) {
      logger.i('Reminder date is in the past for task: ${task.toJson()}');
      return;
    }

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        taskId.hashCode, // Unique ID based on Firestore document ID
        'Maintenance Task Reminder: ${task.category}',
        'Task: ${task.component}\nIntervention: ${task.intervention}\nDue in 1 week',
        reminderDate,
        platformChannelSpecifics,
        androidScheduleMode: scheduleMode,
        payload: 'maintenance_task:$taskId', // For handling tap
      );
      logger.i('Scheduled notification for task $taskId at $reminderDate with mode $scheduleMode');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scheduling notification: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error scheduling notification: $e');
    }
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please log in to save tasks', style: GoogleFonts.poppins())),
          );
        }
        return;
      }

      final task = MaintenanceTask(
        category: _categoryController.text,
        component: _componentController.text,
        intervention: _interventionController.text,
        frequency: int.parse(_frequencyController.text),
        createdBy: user.uid,
        createdAt: DateTime.now(),
      );

      final docRef = await FirebaseFirestore.instance.collection('maintenance_tasks').add(task.toJson());
      await _scheduleNotification(task, docRef.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Task saved successfully', style: GoogleFonts.poppins())),
        );
      }
      logger.i('Saved task: ${task.toJson()}, ID: ${docRef.id}');

      // Clear form
      _categoryController.clear();
      _componentController.clear();
      _interventionController.clear();
      _frequencyController.clear();
      setState(() {
        _categorySuggestions = [];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving task: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error saving task: $e');
    }
  }

  void _submitCategorySearch() {
    final query = _categoryController.text.trim().toLowerCase();
    if (_categorySuggestions.isNotEmpty && _commonCategories.contains(query)) {
      _categoryController.text = _categorySuggestions[0];
      setState(() {
        _categorySuggestions = [];
      });
      _categoryFocus.unfocus();
      FocusScope.of(context).requestFocus(_componentFocus);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid category. Choose from suggestions.', style: GoogleFonts.poppins())),
        );
      }
    }
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _componentController.dispose();
    _interventionController.dispose();
    _frequencyController.dispose();
    _categoryFocus.dispose();
    _componentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Schedule Maintenance',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.blueGrey,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Document Upload Section
            Text(
              'Upload Document',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _uploadDocument,
              icon: const Icon(Icons.upload_file, color: Colors.white),
              label: Text(
                'Select Document',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey[800],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),

            // Collapsible Document List
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Uploaded Documents',
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: Icon(_isDocumentSectionExpanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () {
                    setState(() {
                      _isDocumentSectionExpanded = !_isDocumentSectionExpanded;
                    });
                  },
                ),
              ],
            ),
            if (_isDocumentSectionExpanded)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('documents')
                    .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                    .orderBy('uploadedAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}', style: GoogleFonts.poppins());
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Text('No documents uploaded', style: GoogleFonts.poppins());
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final fileName = doc['fileName'] as String;
                      final downloadUrl = doc['downloadUrl'] as String;
                      return ListTile(
                        title: Text(fileName, style: GoogleFonts.poppins()),
                        trailing: IconButton(
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => _openDocument(downloadUrl),
                        ),
                      );
                    },
                  );
                },
              ),
            const SizedBox(height: 16),

            // Task Scheduling Form
            Text(
              'Schedule Task',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  // Category Field with Autocomplete
                  TextFormField(
                    controller: _categoryController,
                    focusNode: _categoryFocus,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submitCategorySearch(),
                    decoration: InputDecoration(
                      labelText: 'Category',
                      suffixIcon: _categoryController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.blueGrey),
                              onPressed: () {
                                _categoryController.clear();
                                _updateCategorySuggestions();
                                _categoryFocus.unfocus();
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[400]!, width: 1.0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                    validator: (value) => value!.isEmpty ? 'Category is required' : null,
                  ),
                  if (_categoryController.text.isNotEmpty && _categorySuggestions.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 150),
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.3),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _categorySuggestions.length,
                        itemBuilder: (context, index) {
                          final category = _categorySuggestions[index];
                          return ListTile(
                            title: Text(category, style: GoogleFonts.poppins()),
                            onTap: () {
                              _categoryController.text = category;
                              setState(() {
                                _categorySuggestions = [];
                              });
                              _categoryFocus.unfocus();
                              FocusScope.of(context).requestFocus(_componentFocus);
                            },
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Component Field
                  TextFormField(
                    controller: _componentController,
                    focusNode: _componentFocus,
                    decoration: InputDecoration(
                      labelText: 'Component',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[400]!, width: 1.0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                    validator: (value) => value!.isEmpty ? 'Component is required' : null,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),

                  // Intervention Field
                  TextFormField(
                    controller: _interventionController,
                    decoration: InputDecoration(
                      labelText: 'Intervention',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[400]!, width: 1.0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                    validator: (value) => value!.isEmpty ? 'Intervention is required' : null,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 16),

                  // Frequency Field
                  TextFormField(
                    controller: _frequencyController,
                    decoration: InputDecoration(
                      labelText: 'Frequency (months)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[400]!, width: 1.0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value!.isEmpty) return 'Frequency is required';
                      if (int.tryParse(value) == null || int.parse(value) <= 0) {
                        return 'Enter a valid number of months';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Save Task Button
                  ElevatedButton(
                    onPressed: _saveTask,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey[800],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      'Save Task',
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}