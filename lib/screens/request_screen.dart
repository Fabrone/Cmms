import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/models/request.dart';
import 'dart:io';

class RequestScreen extends StatefulWidget {
  final String facilityId;

  const RequestScreen({super.key, required this.facilityId});

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _commentController = TextEditingController();
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  String _selectedStatus = 'All';
  String _priority = 'Medium';
  final List<Map<String, String>> _attachmentUrls = [];
  bool _showForm = false;

  @override
  void initState() {
    super.initState();
    _logger.i('RequestScreen initialized: facilityId=${widget.facilityId}');
  }

  Future<void> _submitRequest() async {
    if (_formKey.currentState!.validate()) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _logger.e('No user signed in');
        _showSnackBar('Please sign in to submit requests');
        return;
      }
      try {
        _logger.i('Submitting request: title=${_titleController.text}, facilityId=${widget.facilityId}');
        final requestId = const Uuid().v4();
        
        final request = Request(
          id: requestId,
          requestId: requestId,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          status: 'Open',
          priority: _priority,
          createdAt: DateTime.now(),
          createdBy: user.uid,
          createdByEmail: user.email,
          attachments: _attachmentUrls,
          comments: _commentController.text.isNotEmpty
              ? [
                  {
                    'text': _commentController.text.trim(),
                    'by': user.email ?? 'Unknown',
                    'timestamp': Timestamp.now(),
                  }
                ]
              : [],
          workOrderIds: [],
          clientStatus: 'Pending',
        );

        await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('requests')
            .doc(requestId)
            .set(request.toMap());

        _titleController.clear();
        _descriptionController.clear();
        _commentController.clear();
        setState(() {
          _attachmentUrls.clear();
          _showForm = false;
        });
        _showSnackBar('Request submitted successfully');
      } catch (e) {
        _logger.e('Error submitting request: $e');
        _showSnackBar('Error submitting request: $e');
      }
    }
  }

  Future<void> _uploadAttachment() async {
    try {
      _logger.i('Picking attachment file, platform: ${kIsWeb ? "web" : "non-web"}');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'png', 'docx'],
      );
      if (result == null || result.files.isEmpty) {
        _logger.w('No file selected');
        _showSnackBar('No file selected');
        return;
      }

      final file = result.files.first;
      _logger.i('Uploading attachment: ${file.name}, bytes: ${file.bytes != null}');
      final fileName = '${const Uuid().v4()}_${file.name}';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('requests/${widget.facilityId}/$fileName');

      String url;
      if (kIsWeb) {
        if (file.bytes == null) {
          _logger.e('No bytes available for web upload');
          _showSnackBar('File data unavailable');
          return;
        }
        final uploadTask = await storageRef.putData(file.bytes!);
        url = await uploadTask.ref.getDownloadURL();
      } else {
        if (file.path == null) {
          _logger.e('No path available for non-web upload');
          _showSnackBar('File path unavailable');
          return;
        }
        final uploadTask = await storageRef.putFile(File(file.path!));
        url = await uploadTask.ref.getDownloadURL();
      }

      _logger.i('Attachment uploaded successfully: $url');
      setState(() {
        _attachmentUrls.add({'name': file.name, 'url': url});
      });
      _showSnackBar('Attachment uploaded');
    } catch (e) {
      _logger.e('Error uploading attachment: $e');
      _showSnackBar('Error uploading attachment: $e');
    }
  }

  Future<void> _updateRequest(String docId, String newStatus, String comment) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _logger.e('No user signed in');
      _showSnackBar('Please sign in to update requests');
      return;
    }
    try {
      _logger.i('Updating request: docId=$docId, newStatus=$newStatus, facilityId=${widget.facilityId}');
      final updates = {
        'status': newStatus,
        'updatedAt': Timestamp.now(),
      };
      if (comment.isNotEmpty) {
        updates['comments'] = FieldValue.arrayUnion([
          {
            'text': comment.trim(),
            'by': user.email ?? 'Unknown',
            'timestamp': Timestamp.now(),
          }
        ]);
      }
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('requests')
          .doc(docId)
          .update(updates);
      _logger.i('Request status updated successfully');
      _showSnackBar('Request status updated to $newStatus');
    } catch (e) {
      _logger.e('Error updating request: $e');
      _showSnackBar('Error updating request: $e');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins())),
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    final fontSizeTitle = isMobile ? 20.0 : 24.0;

    return PopScope(
      canPop: true,
      child: ScaffoldMessenger(
        key: _messengerKey,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              'Maintenance Requests',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: fontSizeTitle,
              ),
            ),
            backgroundColor: Colors.blueGrey[800],
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            elevation: 0,
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Filter Section
                Container(
                  padding: const EdgeInsets.all(16.0),
                  color: Colors.grey[100],
                  child: Row(
                    children: [
                      Text(
                        'Filter by Status:',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                          color: Colors.blueGrey[800],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedStatus,
                          items: ['All', 'Open', 'In Progress', 'Closed']
                              .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s, style: GoogleFonts.poppins(color: Colors.blueGrey[800], fontWeight: FontWeight.w500)),
                                  ))
                              .toList(),
                          onChanged: (value) => setState(() => _selectedStatus = value!),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.blueGrey[300]!),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          style: GoogleFonts.poppins(color: Colors.blueGrey[800], fontWeight: FontWeight.w500),
                          dropdownColor: Colors.white,
                          icon: Icon(Icons.arrow_drop_down, color: Colors.blueGrey[800]),
                        ),
                      ),
                    ],
                  ),
                ),
                // Requests List
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _selectedStatus == 'All'
                        ? FirebaseFirestore.instance
                            .collection('facilities')
                            .doc(widget.facilityId)
                            .collection('requests')
                            .orderBy('createdAt', descending: true)
                            .snapshots()
                        : FirebaseFirestore.instance
                            .collection('facilities')
                            .doc(widget.facilityId)
                            .collection('requests')
                            .where('status', isEqualTo: _selectedStatus)
                            .orderBy('createdAt', descending: true)
                            .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        _logger.e('Firestore error: ${snapshot.error}');
                        return Center(
                          child: Text(
                            'Error: ${snapshot.error}',
                            style: GoogleFonts.poppins(),
                          ),
                        );
                      }
                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.request_page_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No requests found',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (_selectedStatus != 'All')
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    'Try changing the filter option',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(top: 16.0),
                                child: Text(
                                  'Create a new request using the button below',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Colors.blueGrey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final request = Request.fromSnapshot(docs[index]);
                          
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                backgroundColor: _getStatusColor(request.status),
                                child: Icon(
                                  _getStatusIcon(request.status),
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                request.title,
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blueGrey[900],
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Status: ${request.status} | Priority: ${request.priority}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  Text(
                                    'Created: ${request.createdAt != null ? DateFormat.yMMMd().format(request.createdAt!) : 'Unknown date'}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildDetailRow('Description', request.description),
                                      _buildDetailRow('Created By', request.createdByEmail ?? 'Unknown'),
                                      if (request.attachments.isNotEmpty)
                                        _buildAttachmentsSection(request.attachments),
                                      if (request.comments.isNotEmpty) 
                                        _buildCommentsSection(request.comments),
                                      if (request.workOrderIds.isNotEmpty) 
                                        _buildWorkOrdersSection(request.workOrderIds),
                                      const SizedBox(height: 12),
                                      _buildActionButtons(request),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => setState(() => _showForm = !_showForm),
            backgroundColor: Colors.blueGrey[800],
            icon: Icon(_showForm ? Icons.close : Icons.add, color: Colors.white),
            label: Text(
              _showForm ? 'Cancel' : 'New Request',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
          bottomSheet: _showForm ? _buildRequestForm() : null,
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                color: Colors.blueGrey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsSection(List<Map<String, String>> attachments) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attachments:',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
              color: Colors.blueGrey[700],
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: attachments
                .map((attachment) => Chip(
                      label: Text(
                        attachment['name'] ?? 'Unknown',
                        style: GoogleFonts.poppins(fontSize: 12),
                      ),
                      backgroundColor: Colors.blue[50],
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsSection(List<Map<String, dynamic>> comments) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Comments:',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
              color: Colors.blueGrey[700],
            ),
          ),
          const SizedBox(height: 4),
          ...comments.map((comment) => Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment['text'] ?? '',
                      style: GoogleFonts.poppins(fontSize: 12),
                    ),
                    Text(
                      'by ${comment['by'] ?? 'Unknown'} at ${comment['timestamp'] != null ? DateFormat.yMMMd().format((comment['timestamp'] as Timestamp).toDate()) : 'Unknown date'}',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildWorkOrdersSection(List<String> workOrderIds) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Work Orders:',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
              color: Colors.blueGrey[700],
            ),
          ),
          const SizedBox(height: 4),
          ...workOrderIds.map((workOrderId) => StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('facilities')
                    .doc(widget.facilityId)
                    .collection('work_orders')
                    .doc(workOrderId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final workOrder = snapshot.data!;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${workOrder['title'] ?? 'Untitled'} - Status: ${workOrder['clientStatus'] ?? 'Unknown'}',
                      style: GoogleFonts.poppins(fontSize: 12),
                    ),
                  );
                },
              )),
        ],
      ),
    );
  }

  Widget _buildActionButtons(Request request) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: () => _showUpdateStatusDialog(request),
          icon: const Icon(Icons.edit, size: 16),
          label: Text('Update Status', style: GoogleFonts.poppins()),
          style: TextButton.styleFrom(
            foregroundColor: Colors.blueGrey[700],
          ),
        ),
      ],
    );
  }

  void _showUpdateStatusDialog(Request request) {
    final commentController = TextEditingController();
    String selectedStatus = request.status;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Request Status', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: selectedStatus,
              items: ['Open', 'In Progress', 'Closed']
                  .map((status) => DropdownMenuItem(
                        value: status,
                        child: Text(status, style: GoogleFonts.poppins()),
                      ))
                  .toList(),
              onChanged: (value) => selectedStatus = value!,
              decoration: InputDecoration(
                labelText: 'Status',
                border: const OutlineInputBorder(),
                labelStyle: GoogleFonts.poppins(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: commentController,
              decoration: InputDecoration(
                labelText: 'Comment (optional)',
                border: const OutlineInputBorder(),
                labelStyle: GoogleFonts.poppins(),
              ),
              style: GoogleFonts.poppins(),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () {
              _updateRequest(request.id, selectedStatus, commentController.text);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800]),
            child: Text('Update', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestForm() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Submit New Request',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[900],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                  ),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
                validator: (value) => value!.isEmpty ? 'Enter a title' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                  ),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
                maxLines: 3,
                validator: (value) => value!.isEmpty ? 'Enter a description' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _priority,
                items: ['Low', 'Medium', 'High']
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p, style: GoogleFonts.poppins()),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _priority = value!),
                decoration: InputDecoration(
                  labelText: 'Priority',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                  ),
                  labelStyle: GoogleFonts.poppins(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _commentController,
                decoration: InputDecoration(
                  labelText: 'Comment (optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                  ),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _uploadAttachment,
                      icon: const Icon(Icons.attach_file, color: Colors.white),
                      label: Text('Add Attachment', style: GoogleFonts.poppins(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey[600],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              if (_attachmentUrls.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: _attachmentUrls
                      .map((attachment) => Chip(
                            label: Text(attachment['name']!, style: GoogleFonts.poppins(fontSize: 12)),
                            backgroundColor: Colors.blue[50],
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey[800],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    'Submit Request',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Colors.blue;
      case 'in progress':
        return Colors.orange;
      case 'closed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Icons.radio_button_unchecked;
      case 'in progress':
        return Icons.hourglass_empty;
      case 'closed':
        return Icons.check_circle;
      default:
        return Icons.help;
    }
  }
}
