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
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
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
  final Logger _logger = Logger(printer: PrettyPrinter());
  String _selectedStatus = 'All';
  String _priority = 'Medium';
  final List<Map<String, String>> _attachmentUrls = [];
  bool _showForm = false;
  String _currentRole = 'User';
  String _organization = '-';

  @override
  void initState() {
    super.initState();
    _getCurrentUserRole();
    _logger.i('RequestScreen initialized: facilityId=${widget.facilityId}');
  }

  Future<void> _getCurrentUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final adminDoc = await FirebaseFirestore.instance.collection('Admins').doc(user.uid).get();
      final developerDoc = await FirebaseFirestore.instance.collection('Developers').doc(user.uid).get();
      final technicianDoc = await FirebaseFirestore.instance.collection('Technicians').doc(user.uid).get();
      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();

      String newRole = 'User';
      String newOrg = '-';

      if (adminDoc.exists) {
        newRole = 'Admin';
        newOrg = adminDoc.data()?['organization'] ?? '-';
      } else if (developerDoc.exists) {
        newRole = 'Technician';
        newOrg = 'JV Almacis';
      } else if (technicianDoc.exists) {
        newRole = 'Technician';
        newOrg = technicianDoc.data()?['organization'] ?? '-';
      } else if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData != null && userData['role'] == 'Technician') {
          newRole = 'Technician';
          newOrg = '-';
        } else {
          newRole = 'User';
          newOrg = '-';
        }
      }

      if (mounted) {
        setState(() {
          _currentRole = newRole;
          _organization = newOrg;
        });
      }
    } catch (e) {
      _logger.e('Error getting user role: $e');
    }
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _logger.e('No user signed in');
      if (mounted) _showSnackBar('Please sign in to submit requests');
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

      if (mounted) {
        _titleController.clear();
        _descriptionController.clear();
        _commentController.clear();
        setState(() {
          _attachmentUrls.clear();
          _showForm = false;
        });
        _showSnackBar('Request submitted successfully');
      }
    } catch (e) {
      _logger.e('Error submitting request: $e');
      if (mounted) _showSnackBar('Error submitting request: $e');
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
        if (mounted) _showSnackBar('No file selected');
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
          if (mounted) _showSnackBar('File data unavailable');
          return;
        }
        final uploadTask = await storageRef.putData(file.bytes!);
        url = await uploadTask.ref.getDownloadURL();
      } else {
        if (file.path == null) {
          _logger.e('No path available for non-web upload');
          if (mounted) _showSnackBar('File path unavailable');
          return;
        }
        final uploadTask = await storageRef.putFile(File(file.path!));
        url = await uploadTask.ref.getDownloadURL();
      }

      _logger.i('Attachment uploaded successfully: $url');
      if (mounted) {
        setState(() {
          _attachmentUrls.add({'name': file.name, 'url': url});
        });
        _showSnackBar('Attachment uploaded');
      }
    } catch (e) {
      _logger.e('Error uploading attachment: $e');
      if (mounted) _showSnackBar('Error uploading attachment: $e');
    }
  }

  Future<void> _updateRequest(String docId, String newStatus, String comment) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _logger.e('No user signed in');
      if (mounted) _showSnackBar('Please sign in to update requests');
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
      if (mounted) _showSnackBar('Request status updated to $newStatus');
    } catch (e) {
      _logger.e('Error updating request: $e');
      if (mounted) _showSnackBar('Error updating request: $e');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
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
    return ResponsiveScreenWrapper(
      title: 'Work on Request',
      facilityId: widget.facilityId,
      currentRole: _currentRole,
      organization: _organization,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _showForm = !_showForm),
        backgroundColor: Colors.blueGrey[800],
        icon: Icon(_showForm ? Icons.close : Icons.add, color: Colors.white),
        label: Text(
          _showForm ? 'Cancel' : 'New Request',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    final padding = isMobile ? 16.0 : screenWidth <= 900 ? 24.0 : 32.0;
    final fontSizeTitle = isMobile ? 20.0 : screenWidth <= 900 ? 24.0 : 28.0;
    final fontSizeSubtitle = isMobile ? 14.0 : screenWidth <= 900 ? 16.0 : 18.0;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(padding),
          color: Colors.grey[100],
          child: Row(
            children: [
              Text(
                'Filter by Status:',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w500,
                  color: Colors.blueGrey[800],
                  fontSize: fontSizeSubtitle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedStatus,
                  items: ['All', 'Open', 'In Progress', 'Closed']
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s, style: GoogleFonts.poppins(color: Colors.blueGrey[900])),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() => _selectedStatus = value!),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey[400]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    filled: true,
                    fillColor: Colors.white,
                    labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
                  ),
                  style: GoogleFonts.poppins(color: Colors.blueGrey[900]),
                ),
              ),
            ],
          ),
        ),
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
                          fontSize: fontSizeSubtitle,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: EdgeInsets.all(padding),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final request = Request.fromSnapshot(docs[index]);
                  return Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: _getStatusColor(request.status),
                                child: Icon(
                                  _getStatusIcon(request.status),
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  request.title,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blueGrey[900],
                                    fontSize: fontSizeSubtitle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Status: ${request.status} | Priority: ${request.priority}',
                            style: GoogleFonts.poppins(
                              fontSize: isMobile ? 12 : 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            'Created: ${request.createdAt != null ? DateFormat.yMMMd().format(request.createdAt!) : 'Unknown date'}',
                            style: GoogleFonts.poppins(
                              fontSize: isMobile ? 12 : 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow('Description', request.description, fontSizeSubtitle),
                          _buildDetailRow('Created By', request.createdByEmail ?? 'Unknown', fontSizeSubtitle),
                          if (request.attachments.isNotEmpty)
                            _buildAttachmentsSection(request.attachments, fontSizeSubtitle),
                          if (request.comments.isNotEmpty)
                            _buildCommentsSection(request.comments, fontSizeSubtitle),
                          if (request.workOrderIds.isNotEmpty)
                            _buildWorkOrdersSection(request.workOrderIds, fontSizeSubtitle),
                          const SizedBox(height: 12),
                          _buildActionButtons(request, fontSizeSubtitle),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (_showForm) _buildRequestForm(padding, fontSizeTitle, fontSizeSubtitle),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, double fontSize) {
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
                fontSize: fontSize,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(color: Colors.grey[800], fontSize: fontSize),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsSection(List<Map<String, String>> attachments, double fontSize) {
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
              fontSize: fontSize,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: attachments
                .map((attachment) => Chip(
                      label: Text(
                        attachment['name'] ?? 'Unknown',
                        style: GoogleFonts.poppins(fontSize: fontSize - 2),
                      ),
                      backgroundColor: Colors.blue[50],
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsSection(List<Map<String, dynamic>> comments, double fontSize) {
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
              fontSize: fontSize,
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
                      style: GoogleFonts.poppins(fontSize: fontSize - 2),
                    ),
                    Text(
                      'by ${comment['by'] ?? 'Unknown'} at ${comment['timestamp'] != null ? DateFormat.yMMMd().format((comment['timestamp'] as Timestamp).toDate()) : 'Unknown date'}',
                      style: GoogleFonts.poppins(
                        fontSize: fontSize - 4,
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

  Widget _buildWorkOrdersSection(List<String> workOrderIds, double fontSize) {
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
              fontSize: fontSize,
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
                      style: GoogleFonts.poppins(fontSize: fontSize - 2),
                    ),
                  );
                },
              )),
        ],
      ),
    );
  }

  Widget _buildActionButtons(Request request, double fontSize) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: () => _showUpdateStatusDialog(request, fontSize),
          icon: const Icon(Icons.edit, size: 16),
          label: Text('Update Status', style: GoogleFonts.poppins(fontSize: fontSize)),
          style: TextButton.styleFrom(
            foregroundColor: Colors.blueGrey[700],
          ),
        ),
      ],
    );
  }

  void _showUpdateStatusDialog(Request request, double fontSize) {
    final commentController = TextEditingController();
    String selectedStatus = request.status;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Request Status', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: fontSize)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: selectedStatus,
              items: ['Open', 'In Progress', 'Closed']
                  .map((status) => DropdownMenuItem(
                        value: status,
                        child: Text(status, style: GoogleFonts.poppins(color: Colors.blueGrey[900])),
                      ))
                  .toList(),
              onChanged: (value) => selectedStatus = value!,
              decoration: InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[400]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
                labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
              ),
              style: GoogleFonts.poppins(color: Colors.blueGrey[900]),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: commentController,
              decoration: InputDecoration(
                labelText: 'Comment (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[400]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[100],
                labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
              ),
              style: GoogleFonts.poppins(fontSize: fontSize),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(fontSize: fontSize)),
          ),
          ElevatedButton(
            onPressed: () {
              _updateRequest(request.id, selectedStatus, commentController.text);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey[800],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Update', style: GoogleFonts.poppins(color: Colors.white, fontSize: fontSize)),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestForm(double padding, double fontSizeTitle, double fontSizeSubtitle) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.all(padding),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Submit New Request',
                    style: GoogleFonts.poppins(
                      fontSize: fontSizeTitle,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[900],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.blueGrey),
                    onPressed: () => setState(() => _showForm = false),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              isMobile
                  ? Column(
                      children: [
                        _buildTextField(_titleController, 'Title', fontSizeSubtitle, validator: (value) => value!.isEmpty ? 'Enter a title' : null),
                        const SizedBox(height: 16),
                        _buildTextField(_descriptionController, 'Description', fontSizeSubtitle, maxLines: 3, validator: (value) => value!.isEmpty ? 'Enter a description' : null),
                        const SizedBox(height: 16),
                        _buildDropdown('Priority', _priority, ['Low', 'Medium', 'High'], (value) => setState(() => _priority = value!), fontSizeSubtitle),
                        const SizedBox(height: 16),
                        _buildTextField(_commentController, 'Comment (optional)', fontSizeSubtitle, maxLines: 2),
                      ],
                    )
                  : Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildTextField(_titleController, 'Title', fontSizeSubtitle, validator: (value) => value!.isEmpty ? 'Enter a title' : null)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildTextField(_descriptionController, 'Description', fontSizeSubtitle, maxLines: 3, validator: (value) => value!.isEmpty ? 'Enter a description' : null)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildDropdown('Priority', _priority, ['Low', 'Medium', 'High'], (value) => setState(() => _priority = value!), fontSizeSubtitle)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildTextField(_commentController, 'Comment (optional)', fontSizeSubtitle, maxLines: 2)),
                          ],
                        ),
                      ],
                    ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _uploadAttachment,
                      icon: const Icon(Icons.attach_file, color: Colors.white),
                      label: Text('Add Attachment', style: GoogleFonts.poppins(color: Colors.white, fontSize: fontSizeSubtitle)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey[600],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 4,
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
                            label: Text(attachment['name']!, style: GoogleFonts.poppins(fontSize: fontSizeSubtitle - 2)),
                            backgroundColor: Colors.blue[50],
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => setState(() => _showForm = false),
                      child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.blueGrey[800], fontSize: fontSizeSubtitle)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submitRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey[800],
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 4,
                      ),
                      child: Text(
                        'Submit Request',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: fontSizeSubtitle,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String labelText,
    double fontSize, {
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: labelText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
      ),
      style: GoogleFonts.poppins(fontSize: fontSize),
      maxLines: maxLines,
      validator: validator,
    );
  }

  Widget _buildDropdown(
    String labelText,
    String value,
    List<String> items,
    Function(String?) onChanged,
    double fontSize,
  ) {
    return DropdownButtonFormField<String>(
      value: value,
      items: items
          .map((item) => DropdownMenuItem(
                value: item,
                child: Text(item, style: GoogleFonts.poppins(color: Colors.blueGrey[900])),
              ))
          .toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: labelText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
      ),
      style: GoogleFonts.poppins(color: Colors.blueGrey[900], fontSize: fontSize),
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