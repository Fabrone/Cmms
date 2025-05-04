import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
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
  String? _latestWorkOrderId; // Track the latest submitted work order
  final List<String> _attachmentUrls = [];

  @override
  void initState() {
    super.initState();
    _logger.i('WorkOrderScreen initialized: facilityId=${widget.facilityId}');
    final user = FirebaseAuth.instance.currentUser;
    _logger.i('Current user: ${user?.uid ?? "Not signed in"}');
  }

  Future<bool> _isClient(String requestId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final request = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('requests')
          .doc(requestId)
          .get();
      if (!request.exists) {
        _logger.w('Request not found: requestId=$requestId');
        return false;
      }
      final isClient = request['createdBy'] == user.uid;
      _logger.i('Checking isClient for requestId=$requestId: $isClient, userUid=${user.uid}, createdBy=${request['createdBy']}');
      return isClient;
    } catch (e) {
      _logger.e('Error checking isClient: $e');
      return false;
    }
  }

  Future<void> _addWorkOrder() async {
    if (_formKey.currentState!.validate()) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Please sign in to add work orders')),
        );
        return;
      }
      try {
        final workOrderId = const Uuid().v4();
        _logger.i(
            'Adding work order: workOrderId=$workOrderId, title=${_titleController.text}, facilityId=${widget.facilityId}, requestId=$_selectedRequestId');
        await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('work_orders')
            .doc(workOrderId)
            .set({
          'workOrderId': workOrderId,
          'requestId': _selectedRequestId,
          'title': _titleController.text,
          'description': _descriptionController.text,
          'status': 'Open',
          'priority': _priority,
          'assignedTo': _selectedTechnicianId ?? '',
          'createdAt': Timestamp.now(),
          'attachments': _attachmentUrls,
          'history': [
            {
              'action': 'Created',
              'timestamp': Timestamp.now(),
              'notes': _notesController.text,
            }
          ],
          'clientStatus': 'Awaiting Client Action',
          'clientNotes': '',
        });

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

          final request = await FirebaseFirestore.instance
              .collection('facilities')
              .doc(widget.facilityId)
              .collection('requests')
              .doc(_selectedRequestId)
              .get();
          if (request.exists) {
            await FirebaseFirestore.instance.collection('notifications').add({
              'userId': request['createdBy'],
              'message': 'Work order created for request: ${_titleController.text}',
              'timestamp': Timestamp.now(),
              'read': false,
            });
            _logger.i('Notification sent to userId: ${request['createdBy']}');
          }
        }

        setState(() {
          _latestWorkOrderId = workOrderId; // Store the new work order ID
          _attachmentUrls.clear();
          _selectedRequestId = null;
          _selectedTechnicianId = null;
        });
        _titleController.clear();
        _descriptionController.clear();
        _notesController.clear();
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Work Order submitted')),
        );
      } catch (e) {
        _logger.e('Error adding work order: $e');
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _uploadAttachment() async {
    try {
      _logger.i('Picking attachment file, platform: ${kIsWeb ? "web" : "non-web"}');
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) {
        _logger.w('No file selected');
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('No file selected')),
        );
        return;
      }

      final file = result.files.first;
      _logger.i('Uploading attachment: ${file.name}, bytes: ${file.bytes != null}');

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('work_orders/${widget.facilityId}/${DateTime.now().millisecondsSinceEpoch}_${file.name}');

      String url;
      if (kIsWeb) {
        if (file.bytes == null) {
          _logger.e('No bytes available for web upload');
          _messengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('File data unavailable')),
          );
          return;
        }
        final uploadTask = await storageRef.putData(file.bytes!);
        url = await uploadTask.ref.getDownloadURL();
      } else {
        if (file.path == null) {
          _logger.e('No path available for non-web upload');
          _messengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('File path unavailable')),
          );
          return;
        }
        final uploadTask = await storageRef.putFile(File(file.path!));
        url = await uploadTask.ref.getDownloadURL();
      }

      _logger.i('Attachment uploaded successfully: $url');
      setState(() {
        _attachmentUrls.add(url);
      });
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Attachment uploaded')),
      );
    } catch (e) {
      _logger.e('Error uploading attachment: $e');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error uploading attachment: $e')),
      );
    }
  }

  Future<void> _updateStatus(String docId, String newStatus, String notes) async {
    try {
      _logger.i('Updating status: docId=$docId, newStatus=$newStatus, facilityId=${widget.facilityId}');
      final updates = {
        'status': newStatus,
        'history': FieldValue.arrayUnion([
          {
            'action': 'Status changed to $newStatus',
            'timestamp': Timestamp.now(),
            'notes': notes,
          }
        ]),
      };
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('work_orders')
          .doc(docId)
          .update(updates);

      if (newStatus == 'Closed') {
        final workOrder = await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('work_orders')
            .doc(docId)
            .get();
        final request = await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('requests')
            .doc(workOrder['requestId'])
            .get();
        if (request.exists) {
          await FirebaseFirestore.instance.collection('notifications').add({
            'userId': request['createdBy'],
            'message': 'Work order completed for request: ${workOrder['title']}. Please confirm.',
            'timestamp': Timestamp.now(),
            'read': false,
          });
          _logger.i('Notification sent to userId: ${request['createdBy']}');
        }
      }

      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Status updated to $newStatus')),
      );
    } catch (e) {
      _logger.e('Error updating status: $e');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error updating status: $e')),
      );
    }
  }

  Future<void> _confirmWorkOrder(String docId, String workOrderTitle) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Please sign in to confirm work orders')),
      );
      return;
    }
    try {
      _logger.i('Fetching work order: docId=$docId, facilityId=${widget.facilityId}');
      final workOrder = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('work_orders')
          .doc(docId)
          .get();
      if (!workOrder.exists) {
        _logger.e('Work order not found: docId=$docId');
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Work order not found')),
        );
        return;
      }
      final requestId = workOrder['requestId'];
      _logger.i('Fetching request: requestId=$requestId, facilityId=${widget.facilityId}');
      final request = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('requests')
          .doc(requestId)
          .get();
      if (!request.exists) {
        _logger.e('Request not found: requestId=$requestId');
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Linked request not found')),
        );
        return;
      }
      if (request['createdBy'] != user.uid) {
        _logger.w('User ${user.uid} is not the request creator: ${request['createdBy']}');
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Only the request creator can confirm this work order')),
        );
        return;
      }

      _logger.i('Confirming work order: docId=$docId, facilityId=${widget.facilityId}');
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('work_orders')
          .doc(docId)
          .update({
        'clientStatus': 'Confirmed',
        'history': FieldValue.arrayUnion([
          {
            'action': 'Confirmed by client',
            'timestamp': Timestamp.now(),
            'notes': 'Client confirmed work order',
          }
        ]),
      });

      // Notify technician and manager
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': workOrder['assignedTo'] ?? '',
        'message': 'Client confirmed work order: $workOrderTitle',
        'timestamp': Timestamp.now(),
        'read': false,
      });
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': request['createdBy'],
        'message': 'Work order confirmed: $workOrderTitle',
        'timestamp': Timestamp.now(),
        'read': false,
      });

      setState(() {
        _latestWorkOrderId = null; // Reset after confirmation
      });
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Work order confirmed')),
      );
    } catch (e) {
      _logger.e('Error confirming work order: $e');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error confirming work order: $e')),
      );
    }
  }

  Future<void> _reviewWorkOrder(String docId, String workOrderTitle) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Please sign in to review work orders')),
      );
      return;
    }
    final reviewNotes = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review Work Order'),
        content: TextField(
          controller: _reviewNotesController,
          decoration: const InputDecoration(
            labelText: 'Review Notes',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _reviewNotesController.text),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (reviewNotes == null || reviewNotes.trim().isEmpty) {
      _logger.i('Review cancelled or empty for docId=$docId');
      return;
    }

    try {
      _logger.i('Fetching work order: docId=$docId, facilityId=${widget.facilityId}');
      final workOrder = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('work_orders')
          .doc(docId)
          .get();
      if (!workOrder.exists) {
        _logger.e('Work order not found: docId=$docId');
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Work order not found')),
        );
        return;
      }
      final requestId = workOrder['requestId'];
      _logger.i('Fetching request: requestId=$requestId, facilityId=${widget.facilityId}');
      final request = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('requests')
          .doc(requestId)
          .get();
      if (!request.exists) {
        _logger.e('Request not found: requestId=$requestId');
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Linked request not found')),
        );
        return;
      }
      if (request['createdBy'] != user.uid) {
        _logger.w('User ${user.uid} is not the request creator: ${request['createdBy']}');
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Only the request creator can review this work order')),
        );
        return;
      }

      _logger.i('Reviewing work order: docId=$docId, facilityId=${widget.facilityId}');
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('work_orders')
          .doc(docId)
          .update({
        'clientNotes': reviewNotes,
        'history': FieldValue.arrayUnion([
          {
            'action': 'Reviewed by client',
            'timestamp': Timestamp.now(),
            'notes': reviewNotes,
          }
        ]),
      });

      // Notify technician and manager
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': workOrder['assignedTo'] ?? '',
        'message': 'Client reviewed work order: $workOrderTitle',
        'timestamp': Timestamp.now(),
        'read': false,
      });
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': request['createdBy'],
        'message': 'Review submitted for work order: $workOrderTitle',
        'timestamp': Timestamp.now(),
        'read': false,
      });

      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Review submitted')),
      );
      _reviewNotesController.clear();
    } catch (e) {
      _logger.e('Error reviewing work order: $e');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error reviewing work order: $e')),
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
    _logger.i('Building WorkOrderScreen: facilityId=${widget.facilityId}');
    final user = FirebaseAuth.instance.currentUser;
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('Work Orders')),
        body: SafeArea(
          child: SingleChildScrollView(
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
                              'Create Work Order',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('facilities')
                                  .doc(widget.facilityId)
                                  .collection('requests')
                                  .where('status', isEqualTo: 'Open')
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) return const CircularProgressIndicator();
                                if (snapshot.hasError) {
                                  _logger.e('Requests stream error: ${snapshot.error}');
                                  return const Text('Error loading requests');
                                }
                                final requests = snapshot.data!.docs;
                                return DropdownButtonFormField<String>(
                                  value: _selectedRequestId,
                                  hint: const Text('Select Request'),
                                  items: requests.map((doc) {
                                    return DropdownMenuItem(
                                      value: doc.id,
                                      child: Text(doc['title'] ?? 'Untitled'),
                                    );
                                  }).toList(),
                                  onChanged: (value) => setState(() => _selectedRequestId = value),
                                  decoration: const InputDecoration(
                                    labelText: 'Related Request',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (value) => value == null ? 'Select a request' : null,
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _titleController,
                              decoration: const InputDecoration(
                                labelText: 'Title',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) => value!.isEmpty ? 'Enter a title' : null,
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
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('users')
                                  .where('role', isEqualTo: 'technician')
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) return const CircularProgressIndicator();
                                if (snapshot.hasError) {
                                  _logger.e('Technicians stream error: ${snapshot.error}');
                                  return const Text('Error loading technicians');
                                }
                                final users = snapshot.data!.docs;
                                return DropdownButtonFormField<String>(
                                  value: _selectedTechnicianId,
                                  hint: const Text('Select Technician'),
                                  items: users.map((user) {
                                    return DropdownMenuItem(
                                      value: user.id,
                                      child: Text(user['email'] ?? 'Unknown'),
                                    );
                                  }).toList(),
                                  onChanged: (value) => setState(() => _selectedTechnicianId = value),
                                  decoration: const InputDecoration(
                                    labelText: 'Assigned To',
                                    border: OutlineInputBorder(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _priority,
                              items: ['Low', 'Medium', 'High']
                                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                                  .toList(),
                              onChanged: (value) => setState(() => _priority = value!),
                              decoration: const InputDecoration(
                                labelText: 'Priority',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _notesController,
                              decoration: const InputDecoration(
                                labelText: 'Notes',
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _uploadAttachment,
                              child: const Text('Add Attachment'),
                            ),
                            const SizedBox(height: 8),
                            if (_attachmentUrls.isNotEmpty)
                              Wrap(
                                spacing: 8,
                                children: _attachmentUrls
                                    .map((url) => Chip(label: Text(url.split('/').last)))
                                    .toList(),
                              ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _addWorkOrder,
                                    child: const Text('Submit Work Order'),
                                  ),
                                ),
                                if (_latestWorkOrderId != null)
                                  FutureBuilder<bool>(
                                    future: _isClient(_selectedRequestId ?? ''),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState == ConnectionState.waiting) {
                                        return const SizedBox.shrink();
                                      }
                                      final isClient = snapshot.data ?? false;
                                      _logger.i('Form buttons: isClient=$isClient, workOrderId=$_latestWorkOrderId');
                                      if (!isClient) return const SizedBox.shrink();
                                      return Row(
                                        children: [
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed: () => _confirmWorkOrder(
                                                  _latestWorkOrderId!, _titleController.text.isNotEmpty
                                                      ? _titleController.text
                                                      : 'Untitled'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green,
                                              ),
                                              child: const Text('Confirm'),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed: () => _reviewWorkOrder(
                                                  _latestWorkOrderId!, _titleController.text.isNotEmpty
                                                      ? _titleController.text
                                                      : 'Untitled'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.blue,
                                              ),
                                              child: const Text('Review'),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButton<String>(
                    value: _statusFilter,
                    items: ['All', 'Open', 'In Progress', 'Closed']
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
                      _logger.i(
                          'Work Orders - StreamBuilder: hasData=${snapshot.hasData}, hasError=${snapshot.hasError}, facilityId=${widget.facilityId}');
                      if (!snapshot.hasData) {
                        _logger.i('Loading work orders...');
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        _logger.e('Firestore error: ${snapshot.error}');
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      final docs = snapshot.data!.docs;
                      _logger.i('Loaded ${docs.length} work orders');
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final history =
                              (doc['history'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
                          return FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('facilities')
                                .doc(widget.facilityId)
                                .collection('requests')
                                .doc(doc['requestId'])
                                .get(),
                            builder: (context, requestSnapshot) {
                              _logger.i('FutureBuilder for workOrderId=${doc.id}, requestId=${doc['requestId']}');
                              if (requestSnapshot.connectionState == ConnectionState.waiting) {
                                return const ListTile(title: Text('Loading request data...'));
                              }
                              if (requestSnapshot.hasError) {
                                _logger.e('Request fetch error: ${requestSnapshot.error}');
                                return ListTile(
                                  title: Text('Error loading request: ${requestSnapshot.error}'),
                                );
                              }
                              if (!requestSnapshot.hasData || !requestSnapshot.data!.exists) {
                                _logger.w('Request not found for workOrderId=${doc.id}, requestId=${doc['requestId']}');
                                return ListTile(
                                  title: Text('Request not found for ${doc['title']}'),
                                  subtitle: const Text('Confirm/Review buttons unavailable'),
                                );
                              }
                              final requestData = requestSnapshot.data!;
                              final isClient = requestData['createdBy'] == user?.uid;
                              _logger.i(
                                  'WorkOrderId=${doc.id}, isClient=$isClient, clientStatus=${doc['clientStatus']}, userUid=${user?.uid}, requestCreatedBy=${requestData['createdBy']}');
                              return Card(
                                elevation: 1,
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ExpansionTile(
                                  title: Text(doc['title'] ?? 'Untitled'),
                                  subtitle: Text(
                                      'Status: ${doc['status']} | Priority: ${doc['priority']} | Client Status: ${doc['clientStatus'] ?? 'N/A'}'),
                                  children: [
                                    ListTile(
                                      title: Text('Description: ${doc['description'] ?? 'N/A'}'),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Assigned: ${doc['assignedTo'] ?? 'Unassigned'}'),
                                          Text(
                                              'Created: ${DateFormat.yMMMd().format((doc['createdAt'] as Timestamp).toDate())}'),
                                          if (doc['clientNotes'] != null && doc['clientNotes'].isNotEmpty)
                                            Text('Client Notes: ${doc['clientNotes']}'),
                                          if (doc['attachments'] != null &&
                                              (doc['attachments'] as List<dynamic>).isNotEmpty)
                                            Wrap(
                                              spacing: 8,
                                              children: (doc['attachments'] as List<dynamic>)
                                                  .map((url) => Chip(label: Text(url.split('/').last)))
                                                  .toList(),
                                            ),
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
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isClient)
                                            TextButton(
                                              onPressed: () => _confirmWorkOrder(doc.id, doc['title']),
                                              child: const Text('Confirm', style: TextStyle(color: Colors.green)),
                                            ),
                                          if (isClient)
                                            TextButton(
                                              onPressed: () => _reviewWorkOrder(doc.id, doc['title']),
                                              child: const Text('Review', style: TextStyle(color: Colors.blue)),
                                            ),
                                          PopupMenuButton<String>(
                                            onSelected: (status) =>
                                                _updateStatus(doc.id, status, _notesController.text),
                                            itemBuilder: (context) => [
                                              const PopupMenuItem(value: 'Open', child: Text('Open')),
                                              const PopupMenuItem(
                                                  value: 'In Progress', child: Text('In Progress')),
                                              const PopupMenuItem(value: 'Closed', child: Text('Closed')),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}