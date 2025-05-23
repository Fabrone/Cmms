import 'dart:io';
import 'package:cmms/models/maintenance_task.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ScheduleMaintenanceScreen extends StatefulWidget {
  final String facilityId;

  const ScheduleMaintenanceScreen({super.key, required this.facilityId});

  @override
  ScheduleMaintenanceScreenState createState() => ScheduleMaintenanceScreenState();
}

class ScheduleMaintenanceScreenState extends State<ScheduleMaintenanceScreen> {
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
  double? _uploadProgress;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _categoryController.addListener(_updateCategorySuggestions);
    _setupFCM();
    logger.i('ScheduleMaintenanceScreen initialized with facilityId: ${widget.facilityId}');
  }

  Future<void> _setupFCM() async {
    await _firebaseMessaging.requestPermission();
    String? token = await _firebaseMessaging.getToken();
    if (token != null && FirebaseAuth.instance.currentUser != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
      logger.i('FCM token saved for user: ${FirebaseAuth.instance.currentUser!.uid}');
    }
  }

  Future<void> _sendPushNotification(String userId, String title, String body, String taskId, String facilityId) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final fcmToken = userDoc.data()?['fcmToken'] as String?;
      if (fcmToken == null) {
        logger.w('No FCM token found for user: $userId');
        return;
      }

      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=YOUR_FCM_SERVER_KEY',
        },
        body: jsonEncode({
          'to': fcmToken,
          'notification': {
            'title': title,
            'body': body,
            'icon': 'ic_launcher',
          },
          'data': {
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            'screen': 'preventive_maintenance_notifications',
            'taskId': taskId,
            'facilityId': facilityId,
          },
        }),
      );

      if (response.statusCode == 200) {
        logger.i('Push notification sent to user: $userId for task: $taskId');
      } else {
        logger.e('Failed to send push notification: ${response.body}');
      }
    } catch (e) {
      logger.e('Error sending push notification: $e');
    }
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
        allowedExtensions: ['pdf', 'doc', 'docx', 'pptx', 'txt'],
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

      if (!mounted) {
        logger.w('Widget not mounted, skipping confirmation dialog for $fileName');
        return;
      }
      final bool? confirmUpload = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Confirm Upload', style: GoogleFonts.poppins()),
          content: Text(
            'Do you want to upload the file: $fileName?',
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Upload', style: GoogleFonts.poppins()),
            ),
          ],
        ),
      );

      if (confirmUpload != true) {
        logger.i('User cancelled document upload: $fileName');
        return;
      }

      if (!mounted) {
        logger.w('Widget not mounted, skipping progress dialog for $fileName');
        return;
      }
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text('Uploading $fileName', style: GoogleFonts.poppins()),
            content: StatefulBuilder(
              builder: (context, setDialogState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: _uploadProgress,
                      backgroundColor: Colors.grey[300],
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueGrey),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _uploadProgress != null
                          ? '${(_uploadProgress! * 100).toStringAsFixed(0)}%'
                          : 'Starting upload...',
                      style: GoogleFonts.poppins(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('documents/${user.uid}/${DateTime.now().millisecondsSinceEpoch}_$fileName');
      final uploadTask = storageRef.putFile(file);

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        setState(() {
          _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
        });
      }, onError: (e) {
        logger.e('Upload progress error: $e');
      });

      await uploadTask;
      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('documents').add({
        'userId': user.uid,
        'fileName': fileName,
        'downloadUrl': downloadUrl,
        'uploadedAt': FieldValue.serverTimestamp(),
        'facilityId': widget.facilityId,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Document uploaded successfully', style: GoogleFonts.poppins())),
        );
      }
      logger.i('Uploaded document: $fileName, URL: $downloadUrl, facilityId: ${widget.facilityId}');
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading document: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error uploading document: $e');
    } finally {
      setState(() {
        _uploadProgress = null;
      });
    }
  }

  Future<void> _viewDocument(String url, String fileName) async {
    try {
      if (fileName.toLowerCase().endsWith('.pdf')) {
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$fileName';
        await Dio().download(url, filePath);
        final file = File(filePath);
        if (await file.exists()) {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PDFViewerScreen(filePath: filePath, fileName: fileName),
              ),
            );
          }
        } else {
          throw 'Failed to download PDF';
        }
      } else {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not open document';
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error viewing document: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error viewing document: $e');
    }
  }

  Future<void> _downloadDocument(String url, String fileName) async {
    try {
      bool permissionGranted = await _requestStoragePermission();
      if (!permissionGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Storage permission denied', style: GoogleFonts.poppins())),
          );
        }
        return;
      }

      final downloadsDir = await getExternalStorageDirectory();
      final filePath = '${downloadsDir!.path}/$fileName';
      await Dio().download(url, filePath);

      final file = File(filePath);
      if (await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Document downloaded to $filePath', style: GoogleFonts.poppins()),
              action: SnackBarAction(
                label: 'Open',
                onPressed: () => OpenFile.open(filePath),
              ),
            ),
          );
        }
        logger.i('Downloaded document: $fileName to $filePath');
      } else {
        throw 'Failed to download document';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading document: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error downloading document: $e');
    }
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
        }
      }
      return status.isGranted;
    }
    return true;
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

      final frequencyMonths = int.parse(_frequencyController.text);
      final createdAt = DateTime.now();
      final nextDue = createdAt.add(Duration(days: frequencyMonths * 30));
      final notificationTrigger = nextDue.subtract(const Duration(days: 5));

      final task = MaintenanceTask(
        category: _categoryController.text,
        component: _componentController.text,
        intervention: _interventionController.text,
        frequency: frequencyMonths,
        createdBy: user.uid,
        createdAt: createdAt,
      );

      final docRef = await FirebaseFirestore.instance.collection('maintenance_tasks').add({
        ...task.toJson(),
        'nextDue': Timestamp.fromDate(nextDue),
        'notificationTrigger': Timestamp.fromDate(notificationTrigger),
        'facilityId': widget.facilityId,
      });

      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': user.uid,
        'title': 'Maintenance Task Reminder',
        'body': 'Task "${task.component}" is due in 5 days on ${DateFormat.yMMMd().format(nextDue)}.',
        'taskId': docRef.id,
        'facilityId': widget.facilityId,
        'timestamp': Timestamp.fromDate(notificationTrigger),
        'read': false,
      });

      await _sendPushNotification(
        user.uid,
        'CMMS: Maintenance Task Reminder',
        'Task "${task.component}" is due in 5 days.',
        docRef.id,
        widget.facilityId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Task saved successfully', style: GoogleFonts.poppins())),
        );
      }
      logger.i('Saved task: ${task.toJson()}, ID: ${docRef.id}, facilityId: ${widget.facilityId}');

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

  IconData _getFileIcon(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'pptx':
        return Icons.slideshow;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Colors.red[600]!;
      case 'doc':
      case 'docx':
        return Colors.blue[600]!;
      case 'pptx':
        return Colors.orange[600]!;
      default:
        return Colors.grey[600]!;
    }
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
                    .where('facilityId', isEqualTo: widget.facilityId)
                    .orderBy('uploadedAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  logger.i('StreamBuilder snapshot: connectionState=${snapshot.connectionState}, hasError=${snapshot.hasError}, docCount=${snapshot.data?.docs.length ?? 0}, facilityId=${widget.facilityId}');
                  if (snapshot.hasError) {
                    logger.e('StreamBuilder error: ${snapshot.error}');
                    return Text('Error: ${snapshot.error}', style: GoogleFonts.poppins());
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    logger.w('No documents found for facilityId: ${widget.facilityId}');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text('No documents uploaded yet', style: GoogleFonts.poppins()),
                    );
                  }
                  logger.i('Found ${docs.length} documents: ${docs.map((doc) => doc.data()).toList()}');
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final fileName = doc['fileName'] as String;
                      final downloadUrl = doc['downloadUrl'] as String;
                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          leading: Icon(
                            _getFileIcon(fileName),
                            color: _getFileIconColor(fileName),
                            size: 32,
                          ),
                          title: Text(
                            fileName,
                            style: GoogleFonts.poppins(
                              color: Colors.green[900],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'view') {
                                _viewDocument(downloadUrl, fileName);
                              } else if (value == 'download') {
                                _downloadDocument(downloadUrl, fileName);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'view',
                                child: Row(
                                  children: [
                                    Icon(Icons.visibility, color: Colors.blue[700], size: 20),
                                    const SizedBox(width: 8),
                                    Text('View', style: GoogleFonts.poppins()),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'download',
                                child: Row(
                                  children: [
                                    Icon(Icons.download, color: Colors.green[700], size: 20),
                                    const SizedBox(width: 8),
                                    Text('Download', style: GoogleFonts.poppins()),
                                  ],
                                ),
                              ),
                            ],
                            icon: const Icon(Icons.more_vert, color: Colors.blueGrey),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            const SizedBox(height: 16),
            Text(
              'Schedule Task',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Form(
              key: _formKey,
              child: Column(
                children: [
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

class PDFViewerScreen extends StatelessWidget {
  final String filePath;
  final String fileName;

  const PDFViewerScreen({super.key, required this.filePath, required this.fileName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: Colors.blueGrey,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PDFView(
        filePath: filePath,
        enableSwipe: true,
        swipeHorizontal: false,
        autoSpacing: true,
        pageFling: true,
        onError: (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading PDF: $error', style: GoogleFonts.poppins())),
          );
        },
      ),
    );
  }
}