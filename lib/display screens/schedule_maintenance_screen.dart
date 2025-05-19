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
  final TextEditingController _pdfTitleController = TextEditingController();
  final TextEditingController _taskTitleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _assigneeController = TextEditingController();
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  DateTime? _dueDate;
  String? _priority = 'Medium';
  bool _isUploading = false;
  String? _uploadedPdfUrl;

  Future<void> _uploadPdf() async {
    if (_isUploading) return;

    final title = _pdfTitleController.text.trim();
    try {
      setState(() => _isUploading = true);
      _logger.i('Starting PDF upload: title=$title, facilityId=${widget.facilityId}');

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
        _logger.w('No file bytes for $fileName');
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error reading PDF', style: GoogleFonts.poppins())),
        );
        return;
      }

      final storagePath = 'facilities/${widget.facilityId}/scheduled_tasks_attachments/$fileName';
      final storageRef = FirebaseStorage.instance.ref(storagePath);
      final uploadTask = storageRef.putData(fileBytes, SettableMetadata(contentType: 'application/pdf'));
      final snapshot = await uploadTask;
      final fileUrl = await snapshot.ref.getDownloadURL();

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

      if (mounted) {
        setState(() => _uploadedPdfUrl = fileUrl);
        _pdfTitleController.clear();
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('PDF uploaded successfully', style: GoogleFonts.poppins())),
        );
        _logger.i('PDF uploaded: $fileName, url=$fileUrl');
      }
    } catch (e) {
      _logger.e('Error uploading PDF: $e');
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error uploading PDF: $e', style: GoogleFonts.poppins())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _downloadPdf(String url, String title) async {
    try {
      _logger.i('Downloading PDF: $url');
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _logger.w('Cannot launch URL: $url');
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Cannot open PDF', style: GoogleFonts.poppins())),
        );
      }
    } catch (e) {
      _logger.e('Error downloading PDF: $e');
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error downloading PDF: $e', style: GoogleFonts.poppins())),
        );
      }
    }
  }

  Future<void> _deletePdf(String? fileUrl, String title, DocumentReference docRef) async {
    if (fileUrl == null || fileUrl.isEmpty) {
      _logger.w('Invalid fileUrl for: $title');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Invalid PDF URL', style: GoogleFonts.poppins())),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Deletion', style: GoogleFonts.poppins()),
        content: Text('Delete "$title"?', style: GoogleFonts.poppins()),
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
      _logger.i('Deletion cancelled: $title');
      return;
    }

    try {
      _logger.i('Deleting PDF: $title, url: $fileUrl');
      await FirebaseStorage.instance.refFromURL(fileUrl).delete();
      await docRef.delete();
      if (_uploadedPdfUrl == fileUrl && mounted) {
        setState(() => _uploadedPdfUrl = null);
      }
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('PDF deleted', style: GoogleFonts.poppins())),
      );
      _logger.i('PDF deleted: $title');
    } catch (e) {
      _logger.e('Error deleting PDF: $e');
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error deleting PDF: $e', style: GoogleFonts.poppins())),
        );
      }
    }
  }

  Future<void> _scheduleTask() async {
    final title = _taskTitleController.text.trim();
    final description = _descriptionController.text.trim();
    final assignee = _assigneeController.text.trim();

    if (title.isEmpty || _dueDate == null) {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Title and due date required', style: GoogleFonts.poppins())),
      );
      return;
    }

    try {
      _logger.i('Scheduling task: title=$title, dueDate=$_dueDate');
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

      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('predefined_tasks')
          .add({
        'title': title,
        'description': description,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (_uploadedPdfUrl != null) {
        final snapshot = await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('scheduled_tasks_attachments')
            .where('fileUrl', isEqualTo: _uploadedPdfUrl)
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
            'fileUrl': _uploadedPdfUrl,
            'title': title.isEmpty ? 'TaskAttachment' : title,
            'uploadedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Task scheduled', style: GoogleFonts.poppins())),
        );
        _taskTitleController.clear();
        _descriptionController.clear();
        _assigneeController.clear();
        setState(() {
          _dueDate = null;
          _priority = 'Medium';
          _uploadedPdfUrl = null;
        });
        _logger.i('Task scheduled: $title');
      }
    } catch (e) {
      _logger.e('Error scheduling task: $e');
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error scheduling task: $e', style: GoogleFonts.poppins())),
        );
      }
    }
  }

  Future<void> _selectDueDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (selectedDate != null && mounted) {
      setState(() {
        _dueDate = selectedDate;
      });
    }
  }

  @override
  void dispose() {
    _pdfTitleController.dispose();
    _taskTitleController.dispose();
    _descriptionController.dispose();
    _assigneeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _logger.i('Building ScheduleMaintenanceScreen: facilityId=${widget.facilityId}');
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Schedule Maintenance',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: isMobile ? 20 : 24,
            ),
          ),
          backgroundColor: Colors.blueGrey,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
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
              'Upload PDF (Optional)',
              style: GoogleFonts.poppins(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey[800],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pdfTitleController,
              decoration: InputDecoration(
                labelText: 'PDF Title',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                labelStyle: GoogleFonts.poppins(),
              ),
              style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isUploading ? null : _uploadPdf,
              icon: _isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.upload_file, color: Colors.white),
              label: Text(
                _isUploading ? 'Uploading...' : 'Upload PDF',
                style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            if (_uploadedPdfUrl != null) ...[
              const SizedBox(height: 12),
              Text(
                'Uploaded: ${_pdfTitleController.text.isEmpty ? 'PDF' : _pdfTitleController.text}',
                style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16, color: Colors.green),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Uploaded PDFs',
              style: GoogleFonts.poppins(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey[800],
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance
                  .collection('facilities')
                  .doc(widget.facilityId)
                  .collection('scheduled_tasks_attachments')
                  .orderBy('uploadedAt', descending: true)
                  .limit(10)
                  .get(),
              builder: (context, snapshot) {
                _logger.i('FutureBuilder state: ${snapshot.connectionState}, hasData: ${snapshot.hasData}');
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.blueGrey));
                }
                if (snapshot.hasError) {
                  _logger.e('Firestore error: ${snapshot.error}');
                  return Center(
                    child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins(color: Colors.red)),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  _logger.i('No PDFs for facility: ${widget.facilityId}');
                  return Center(
                    child: Text('No PDFs uploaded', style: GoogleFonts.poppins(fontSize: 14)),
                  );
                }

                final docs = snapshot.data!.docs;
                _logger.i('Fetched ${docs.length} PDFs');
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
                        ? (data['uploadedAt'] as Timestamp).toDate().toString().split(' ')[0]
                        : 'N/A';
                    final hasValidUrl = fileUrl != null && fileUrl.isNotEmpty;

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: ListTile(
                        leading: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 30),
                        title: Text(
                          title,
                          style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'Uploaded: $uploadedAt',
                          style: GoogleFonts.poppins(fontSize: isMobile ? 12 : 14, color: Colors.grey),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.download, color: Colors.blue),
                              onPressed: hasValidUrl ? () => _downloadPdf(fileUrl, title) : null,
                              tooltip: 'Download PDF',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: hasValidUrl ? () => _deletePdf(fileUrl, title, docRef) : null,
                              tooltip: 'Delete PDF',
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
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey[800],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _taskTitleController,
              decoration: InputDecoration(
                labelText: 'Task Title *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                labelStyle: GoogleFonts.poppins(),
              ),
              style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                labelStyle: GoogleFonts.poppins(),
              ),
              style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _assigneeController,
              decoration: InputDecoration(
                labelText: 'Assignee (Optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                labelStyle: GoogleFonts.poppins(),
              ),
              style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _dueDate == null
                        ? 'Select Due Date *'
                        : 'Due: ${_dueDate!.toLocal().toString().split(' ')[0]}',
                    style: GoogleFonts.poppins(fontSize: isMobile ? 12 : 14),
                  ),
                ),
                ElevatedButton(
                  onPressed: _selectDueDate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    'Pick Date',
                    style: GoogleFonts.poppins(fontSize: isMobile ? 12 : 14, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _priority,
              decoration: InputDecoration(
                labelText: 'Priority',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                labelStyle: GoogleFonts.poppins(),
              ),
              style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16),
              items: ['Low', 'Medium', 'High'].map((priority) {
                return DropdownMenuItem(
                  value: priority,
                  child: Text(priority, style: GoogleFonts.poppins()),
                );
              }).toList(),
              onChanged: (value) {
                if (mounted) {
                  setState(() => _priority = value);
                }
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _scheduleTask,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                'Schedule Task',
                style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16, color: Colors.white),
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