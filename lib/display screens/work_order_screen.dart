import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/models/work_order.dart';
import 'dart:io';

class WorkOrderScreen extends StatefulWidget {
  final String facilityId;

  const WorkOrderScreen({super.key, required this.facilityId});

  @override
  State<WorkOrderScreen> createState() => _WorkOrderScreenState();
}

class _WorkOrderScreenState extends State<WorkOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  final _reviewNotesController = TextEditingController();
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  String _priority = 'Medium';
  String _statusFilter = 'All';
  String? _selectedRequestId;
  String? _selectedTechnicianId;
  final List<String> _attachmentUrls = [];
  bool _showForm = false;

  @override
  void initState() {
    super.initState();
    _logger.i('WorkOrderScreen initialized: facilityId=${widget.facilityId}');
  }

  Future<void> _addWorkOrder() async {
    if (_formKey.currentState!.validate()) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('Please sign in to add work orders');
        return;
      }
      try {
        final workOrderId = const Uuid().v4();
        _logger.i('Adding work order: workOrderId=$workOrderId, title=${_titleController.text}');
        
        final workOrder = WorkOrder(
          id: workOrderId,
          workOrderId: workOrderId,
          requestId: _selectedRequestId,
          title: _titleController.text,
          description: _descriptionController.text,
          status: 'Open',
          priority: _priority,
          assignedTo: _selectedTechnicianId ?? '',
          createdAt: DateTime.now(),
          attachments: _attachmentUrls,
          history: [
            {
              'action': 'Created',
              'timestamp': Timestamp.now(),
              'notes': _notesController.text,
            }
          ],
          clientStatus: 'Awaiting Client Action',
          clientNotes: '',
        );

        await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('work_orders')
            .doc(workOrderId)
            .set(workOrder.toMap());

        if (_selectedRequestId != null) {
          await FirebaseFirestore.instance
              .collection('facilities')
              .doc(widget.facilityId)
              .collection('requests')
              .doc(_selectedRequestId)
              .update({
            'workOrderIds': FieldValue.arrayUnion([workOrderId]),
            'clientStatus': 'Awaiting Client Action',
          });
        }

        setState(() {
          _attachmentUrls.clear();
          _selectedRequestId = null;
          _selectedTechnicianId = null;
          _showForm = false;
        });
        _titleController.clear();
        _descriptionController.clear();
        _notesController.clear();
        _showSnackBar('Work Order submitted');
      } catch (e) {
        _logger.e('Error adding work order: $e');
        _showSnackBar('Error: $e');
      }
    }
  }

  Future<void> _uploadAttachment() async {
    try {
      _logger.i('Picking attachment file');
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) {
        _showSnackBar('No file selected');
        return;
      }

      final file = result.files.first;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('work_orders/${widget.facilityId}/${DateTime.now().millisecondsSinceEpoch}_${file.name}');

      String url;
      if (kIsWeb) {
        if (file.bytes == null) {
          _showSnackBar('File data unavailable');
          return;
        }
        final uploadTask = await storageRef.putData(file.bytes!);
        url = await uploadTask.ref.getDownloadURL();
      } else {
        if (file.path == null) {
          _showSnackBar('File path unavailable');
          return;
        }
        final uploadTask = await storageRef.putFile(File(file.path!));
        url = await uploadTask.ref.getDownloadURL();
      }

      setState(() {
        _attachmentUrls.add(url);
      });
      _showSnackBar('Attachment uploaded');
    } catch (e) {
      _logger.e('Error uploading attachment: $e');
      _showSnackBar('Error uploading attachment: $e');
    }
  }

  Future<void> _updateStatus(String docId, String newStatus, String notes) async {
    try {
      _logger.i('Updating status: docId=$docId, newStatus=$newStatus');
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('work_orders')
          .doc(docId)
          .update({
        'status': newStatus,
        'history': FieldValue.arrayUnion([
          {
            'action': 'Status changed to $newStatus',
            'timestamp': Timestamp.now(),
            'notes': notes,
          }
        ]),
      });
      _showSnackBar('Status updated to $newStatus');
    } catch (e) {
      _logger.e('Error updating status: $e');
      _showSnackBar('Error updating status: $e');
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
    _notesController.dispose();
    _reviewNotesController.dispose();
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
              'Work Orders',
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
                          value: _statusFilter,
                          items: ['All', 'Open', 'In Progress', 'Closed']
                              .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s, style: GoogleFonts.poppins()),
                                  ))
                              .toList(),
                          onChanged: (value) => setState(() => _statusFilter = value!),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.blueGrey[300]!),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          style: GoogleFonts.poppins(),
                        ),
                      ),
                    ],
                  ),
                ),
                // Work Orders List
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _statusFilter == 'All'
                        ? FirebaseFirestore.instance
                            .collection('facilities')
                            .doc(widget.facilityId)
                            .collection('work_orders')
                            .orderBy('createdAt', descending: true)
                            .snapshots()
                        : FirebaseFirestore.instance
                            .collection('facilities')
                            .doc(widget.facilityId)
                            .collection('work_orders')
                            .where('status', isEqualTo: _statusFilter)
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
                                Icons.work_outline,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No work orders found',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  color: Colors.grey[600],
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
                          final workOrder = WorkOrder.fromSnapshot(docs[index]);
                          
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                backgroundColor: _getStatusColor(workOrder.status),
                                child: Icon(
                                  _getStatusIcon(workOrder.status),
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                workOrder.title,
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blueGrey[900],
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Status: ${workOrder.status} | Priority: ${workOrder.priority}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  Text(
                                    'Assigned: ${workOrder.assignedTo.isEmpty ? 'Unassigned' : workOrder.assignedTo}',
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
                                      _buildDetailRow('Description', workOrder.description),
                                      _buildDetailRow('Created', workOrder.createdAt != null ? DateFormat.yMMMd().format(workOrder.createdAt!) : 'Unknown date'),
                                      if (workOrder.clientNotes.isNotEmpty)
                                        _buildDetailRow('Client Notes', workOrder.clientNotes),
                                      if (workOrder.attachments.isNotEmpty)
                                        _buildAttachmentsSection(workOrder.attachments),
                                      if (workOrder.history.isNotEmpty) 
                                        _buildHistorySection(workOrder.history),
                                      const SizedBox(height: 12),
                                      _buildActionButtons(workOrder),
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
              _showForm ? 'Cancel' : 'New Work Order',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
          bottomSheet: _showForm ? _buildWorkOrderForm() : null,
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

  Widget _buildAttachmentsSection(List<String> attachments) {
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
                .map((url) => Chip(
                      label: Text(
                        url.split('/').last,
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

  Widget _buildHistorySection(List<Map<String, dynamic>> history) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'History:',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
              color: Colors.blueGrey[700],
            ),
          ),
          const SizedBox(height: 4),
          ...history.map((entry) => Container(
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
                      entry['action'] ?? '',
                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'at ${entry['timestamp'] != null ? DateFormat.yMMMd().format((entry['timestamp'] as Timestamp).toDate()) : 'Unknown date'}',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (entry['notes'] != null && entry['notes'].isNotEmpty)
                      Text(
                        entry['notes'],
                        style: GoogleFonts.poppins(fontSize: 11),
                      ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildActionButtons(WorkOrder workOrder) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: () => _showUpdateStatusDialog(workOrder),
          icon: const Icon(Icons.edit, size: 16),
          label: Text('Update Status', style: GoogleFonts.poppins()),
          style: TextButton.styleFrom(
            foregroundColor: Colors.blueGrey[700],
          ),
        ),
      ],
    );
  }

  void _showUpdateStatusDialog(WorkOrder workOrder) {
    final notesController = TextEditingController();
    String selectedStatus = workOrder.status;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Work Order Status', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
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
              controller: notesController,
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
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
              _updateStatus(workOrder.id, selectedStatus, notesController.text);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800]),
            child: Text('Update', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkOrderForm() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
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
                'Create Work Order',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[900],
                ),
              ),
              const SizedBox(height: 16),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('facilities')
                    .doc(widget.facilityId)
                    .collection('requests')
                    .where('status', isEqualTo: 'Open')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const CircularProgressIndicator();
                  final requests = snapshot.data!.docs;
                  return DropdownButtonFormField<String>(
                    value: _selectedRequestId,
                    hint: Text('Select Request', style: GoogleFonts.poppins()),
                    items: requests.map((doc) {
                      return DropdownMenuItem(
                        value: doc.id,
                        child: Text(doc['title'] ?? 'Untitled', style: GoogleFonts.poppins()),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedRequestId = value),
                    decoration: InputDecoration(
                      labelText: 'Related Request',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                      ),
                      labelStyle: GoogleFonts.poppins(),
                    ),
                    validator: (value) => value == null ? 'Select a request' : null,
                  );
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                  ),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where('role', isEqualTo: 'technician')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const CircularProgressIndicator();
                  final users = snapshot.data!.docs;
                  return DropdownButtonFormField<String>(
                    value: _selectedTechnicianId,
                    hint: Text('Select Technician', style: GoogleFonts.poppins()),
                    items: users.map((user) {
                      return DropdownMenuItem(
                        value: user.id,
                        child: Text(user['email'] ?? 'Unknown', style: GoogleFonts.poppins()),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedTechnicianId = value),
                    decoration: InputDecoration(
                      labelText: 'Assigned To',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                      ),
                      labelStyle: GoogleFonts.poppins(),
                    ),
                  );
                },
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                  ),
                  labelStyle: GoogleFonts.poppins(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
                      .map((url) => Chip(
                            label: Text(url.split('/').last, style: GoogleFonts.poppins(fontSize: 12)),
                            backgroundColor: Colors.blue[50],
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _addWorkOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey[800],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    'Submit Work Order',
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
