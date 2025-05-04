import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';

class ScheduleMaintenanceScreen extends StatefulWidget {
  final String facilityId;
  final String selectedSubSection;

  const ScheduleMaintenanceScreen({
    super.key,
    required this.facilityId,
    required this.selectedSubSection,
  });

  @override
  State<ScheduleMaintenanceScreen> createState() => _ScheduleMaintenanceScreenState();
}

class _ScheduleMaintenanceScreenState extends State<ScheduleMaintenanceScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _taskTitleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _assigneeController = TextEditingController();
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  DateTime? _dueDate;
  String? _priority = 'Medium';
  bool _isUploading = false;
  String? _pdfUrl;

  Future<void> _uploadPdf() async {
    if (_isUploading) return;

    final title = _titleController.text.trim();
    try {
      setState(() => _isUploading = true);
      _logger.i('Initiating PDF upload: title=$title, facilityId=${widget.facilityId}, collection=scheduled_tasks_attachments');

      // Pick a PDF file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        _logger.w('No PDF selected');
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('No PDF selected', style: GoogleFonts.poppins())),
        );
        return;
      }

      final file = result.files.single;
      final fileName = file.name;
      final fileBytes = file.bytes;

      if (fileBytes == null) {
        _logger.w('No file bytes available for $fileName');
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error reading PDF file', style: GoogleFonts.poppins())),
        );
        return;
      }

      // Upload to Firebase Storage
      final storagePath = 'facilities/${widget.facilityId}/scheduled_tasks_attachments/$fileName';
      final storageRef = FirebaseStorage.instance.ref(storagePath);
      final uploadTask = storageRef.putData(fileBytes, SettableMetadata(contentType: 'application/pdf'));
      final snapshot = await uploadTask;
      final fileUrl = await snapshot.ref.getDownloadURL();

      // Save metadata to Firestore (without taskId until task is scheduled)
      final docTitle = title.isNotEmpty ? title : fileName;
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('scheduled_tasks_attachments')
          .add({
        'taskId': null,
        'fileUrl': fileUrl,
        'title': docTitle,
        'uploadedAt': FieldValue.serverTimestamp(),
      });

      setState(() => _pdfUrl = fileUrl);
      _logger.i('PDF uploaded successfully: $fileName, url=$fileUrl');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('PDF uploaded successfully', style: GoogleFonts.poppins())),
      );
      _titleController.clear();
    } catch (e, stackTrace) {
      _logger.e('Error uploading PDF: $e', stackTrace: stackTrace);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error uploading PDF: $e', style: GoogleFonts.poppins())),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _downloadPdf(String url, String title) async {
    try {
      _logger.i('Attempting to download PDF: $url');
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _logger.w('Cannot launch URL: $url');
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Cannot open PDF', style: GoogleFonts.poppins())),
        );
      }
    } catch (e, stackTrace) {
      _logger.e('Error downloading PDF: $e', stackTrace: stackTrace);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error downloading PDF: $e', style: GoogleFonts.poppins())),
      );
    }
  }

  Future<void> _viewPdf(String url, String title) async {
    try {
      _logger.i('Navigating to view PDF: $url');
      await Navigator.pushNamed(
        context,
        '/pdf_viewer',
        arguments: {'url': url, 'title': title},
      );
    } catch (e, stackTrace) {
      _logger.e('Error viewing PDF: $e', stackTrace: stackTrace);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error viewing PDF: $e', style: GoogleFonts.poppins())),
      );
    }
  }

  Future<void> _deletePdf(String? fileUrl, String title, DocumentReference docRef) async {
    if (fileUrl == null || fileUrl.isEmpty) {
      _logger.w('No valid fileUrl for title: $title');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error: No valid PDF URL', style: GoogleFonts.poppins())),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Deletion', style: GoogleFonts.poppins()),
        content: Text('Are you sure you want to delete "$title"?', style: GoogleFonts.poppins()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) {
      _logger.i('Deletion cancelled for: $title');
      return;
    }

    try {
      _logger.i('Deleting PDF: $title, url: $fileUrl');
      await FirebaseStorage.instance.refFromURL(fileUrl).delete();
      await docRef.delete();
      if (_pdfUrl == fileUrl) setState(() => _pdfUrl = null);
      _logger.i('PDF deleted successfully: $title');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('PDF deleted successfully', style: GoogleFonts.poppins())),
      );
    } catch (e, stackTrace) {
      _logger.e('Error deleting PDF: $e', stackTrace: stackTrace);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error deleting PDF: $e', style: GoogleFonts.poppins())),
      );
    }
  }

  Future<void> _scheduleTask() async {
    final title = _taskTitleController.text.trim();
    final description = _descriptionController.text.trim();
    final assignee = _assigneeController.text.trim();

    if (title.isEmpty || _dueDate == null) {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Title and due date are required', style: GoogleFonts.poppins())),
      );
      return;
    }

    try {
      _logger.i('Scheduling task: title=$title, dueDate=$_dueDate');
      // Save to scheduled_tasks
      final taskRef = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('scheduled_tasks')
          .add({
        'title': title,
        'description': description,
        'dueDate': Timestamp.fromDate(_dueDate!),
        'assignee': assignee.isEmpty ? null : assignee,
        'priority': _priority,
        'status': 'Pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Save to predefined_tasks
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('predefined_tasks')
          .add({
        'title': title,
        'description': description,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update PDF metadata with taskId if exists
      if (_pdfUrl != null) {
        final snapshot = await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('scheduled_tasks_attachments')
            .where('fileUrl', isEqualTo: _pdfUrl)
            .get();
        if (snapshot.docs.isNotEmpty) {
          await snapshot.docs.first.reference.update({'taskId': taskRef.id});
        } else {
          await FirebaseFirestore.instance
              .collection('facilities')
              .doc(widget.facilityId)
              .collection('scheduled_tasks_attachments')
              .add({
            'taskId': taskRef.id,
            'fileUrl': _pdfUrl,
            'title': title.isEmpty ? 'TaskAttachment' : title,
            'uploadedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      _logger.i('Task scheduled successfully: $title');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Task scheduled successfully', style: GoogleFonts.poppins())),
      );
      _taskTitleController.clear();
      _descriptionController.clear();
      _assigneeController.clear();
      setState(() {
        _dueDate = null;
        _priority = 'Medium';
        _pdfUrl = null;
      });
    } catch (e, stackTrace) {
      _logger.e('Error scheduling task: $e', stackTrace: stackTrace);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error scheduling task: $e', style: GoogleFonts.poppins())),
      );
    }
  }

  Future<void> _selectDueDate(BuildContext context) async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (selectedDate != null) {
      setState(() {
        _dueDate = selectedDate;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _taskTitleController.dispose();
    _descriptionController.dispose();
    _assigneeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _logger.i('Building ScheduleMaintenanceScreen: facilityId=${widget.facilityId}, subSection=${widget.selectedSubSection}');
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        body: SafeArea(
          child: widget.selectedSubSection == 'schedule_maintenance'
              ? _buildMaintenanceSection(isMobile)
              : _buildOtherSubSection(isMobile),
        ),
      ),
    );
  }

  Widget _buildMaintenanceSection(bool isMobile) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Schedule Maintenance',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: isMobile ? 20 : 24,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Upload PDF (Optional)',
              style: GoogleFonts.poppins(fontSize: isMobile ? 16 : 18),
            ),
            const SizedBox(height: 8),
            isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'PDF Title (Optional)',
                          border: OutlineInputBorder(),
                        ),
                        style: GoogleFonts.poppins(fontSize: 14),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _isUploading ? null : _uploadPdf,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _isUploading
                            ? const CircularProgressIndicator()
                            : Text(
                                'Upload PDF',
                                style: GoogleFonts.poppins(fontSize: 14),
                              ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: 'PDF Title (Optional)',
                            border: OutlineInputBorder(),
                          ),
                          style: GoogleFonts.poppins(fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _isUploading ? null : _uploadPdf,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _isUploading
                            ? const CircularProgressIndicator()
                            : Text(
                                'Upload PDF',
                                style: GoogleFonts.poppins(fontSize: 16),
                              ),
                      ),
                    ],
                  ),
            if (_pdfUrl != null) ...[
              const SizedBox(height: 8),
              Text(
                'Attached: ${_titleController.text.isEmpty ? 'TaskPDF' : _titleController.text}',
                style: GoogleFonts.poppins(fontSize: isMobile ? 12 : 14, color: Colors.green),
              ),
            ],
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('facilities')
                  .doc(widget.facilityId)
                  .collection('scheduled_tasks_attachments')
                  .orderBy('uploadedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  _logger.e('Firestore error: ${snapshot.error}', stackTrace: StackTrace.current);
                  return Center(child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins()));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No PDFs uploaded',
                      style: GoogleFonts.poppins(fontSize: 14),
                    ),
                  );
                }

                final docs = snapshot.data!.docs;
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final docRef = FirebaseFirestore.instance
                        .collection('facilities')
                        .doc(widget.facilityId)
                        .collection('scheduled_tasks_attachments')
                        .doc(doc.id);
                    final data = doc.data() as Map<String, dynamic>;
                    final fileUrl = data['fileUrl'] as String?;
                    final title = data['title'] as String? ?? 'Untitled';
                    final uploadedAt = data['uploadedAt'] != null
                        ? (data['uploadedAt'] as Timestamp).toDate().toString()
                        : 'N/A';
                    final hasValidUrl = fileUrl != null && fileUrl.isNotEmpty;

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: ListTile(
                        leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                        title: Text(
                          title,
                          style: GoogleFonts.poppins(
                            fontSize: isMobile ? 14 : 16,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        subtitle: Text(
                          'Uploaded: $uploadedAt',
                          style: GoogleFonts.poppins(
                            fontSize: isMobile ? 12 : 14,
                            color: Colors.black54,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: hasValidUrl
                                  ? () => _downloadPdf(fileUrl, title)
                                  : null,
                              child: Text(
                                'Download',
                                style: GoogleFonts.poppins(
                                  color: hasValidUrl ? Colors.blue : Colors.grey,
                                  fontSize: isMobile ? 12 : 14,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: hasValidUrl
                                  ? () => _viewPdf(fileUrl, title)
                                  : null,
                              child: Text(
                                'View',
                                style: GoogleFonts.poppins(
                                  color: hasValidUrl ? Colors.green : Colors.grey,
                                  fontSize: isMobile ? 12 : 14,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete,
                                color: hasValidUrl ? Colors.red : Colors.grey,
                                size: isMobile ? 20 : 24,
                              ),
                              onPressed: hasValidUrl
                                  ? () => _deletePdf(fileUrl, title, docRef)
                                  : null,
                              tooltip: hasValidUrl ? 'Delete PDF' : 'No valid PDF URL',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Schedule New Task',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: isMobile ? 18 : 20,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _taskTitleController,
              decoration: const InputDecoration(
                labelText: 'Task Title *',
                border: OutlineInputBorder(),
              ),
              style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _assigneeController,
              decoration: const InputDecoration(
                labelText: 'Assignee (Optional)',
                border: OutlineInputBorder(),
              ),
              style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _dueDate == null
                        ? 'Select Due Date *'
                        : 'Due Date: ${_dueDate!.toLocal().toString().split(' ')[0]}',
                    style: GoogleFonts.poppins(fontSize: isMobile ? 12 : 14),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _selectDueDate(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    'Pick Date',
                    style: GoogleFonts.poppins(fontSize: isMobile ? 12 : 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _priority,
              decoration: const InputDecoration(
                labelText: 'Priority',
                border: OutlineInputBorder(),
              ),
              style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16),
              items: ['Low', 'Medium', 'High'].map((priority) {
                return DropdownMenuItem(
                  value: priority,
                  child: Text(
                    priority,
                    style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _priority = value;
                });
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _scheduleTask,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                'Schedule Task',
                style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtherSubSection(bool isMobile) {
    return Center(
      child: Text(
        'Section: ${widget.selectedSubSection}',
        style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16),
      ),
    );
  }
}