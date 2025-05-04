import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
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
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Please sign in to submit requests')),
        );
        return;
      }
      try {
        _logger.i('Submitting request: title=${_titleController.text}, facilityId=${widget.facilityId}');
        final requestId = const Uuid().v4();
        await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('requests')
            .doc(requestId)
            .set({
          'requestId': requestId,
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'status': 'Open',
          'priority': _priority,
          'createdAt': Timestamp.now(),
          'createdBy': user.uid,
          'createdByEmail': user.email,
          'attachments': _attachmentUrls,
          'comments': _commentController.text.isNotEmpty
              ? [
                  {
                    'text': _commentController.text.trim(),
                    'by': user.email,
                    'timestamp': Timestamp.now(),
                  }
                ]
              : [],
          'workOrderIds': [],
          'clientStatus': 'Pending',
        });
        _titleController.clear();
        _descriptionController.clear();
        _commentController.clear();
        setState(() => _attachmentUrls.clear());
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Request submitted successfully')),
        );
      } catch (e) {
        _logger.e('Error submitting request: $e');
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error submitting request: $e')),
        );
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
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('No file selected')),
        );
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
        _attachmentUrls.add({'name': file.name, 'url': url});
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

  Future<void> _updateRequest(String docId, String newStatus, String comment) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _logger.e('No user signed in');
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Please sign in to update requests')),
      );
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
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Request status updated to $newStatus')),
      );
    } catch (e) {
      _logger.e('Error updating request: $e');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error updating request: $e')),
      );
    }
  }

  Future<void> _handleWorkOrderAction(
      String requestId, String workOrderId, String clientStatus, String clientNotes) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Please sign in to perform this action')),
      );
      return;
    }
    try {
      _logger.i(
          'Handling work order action: requestId=$requestId, workOrderId=$workOrderId, clientStatus=$clientStatus');
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('work_orders')
          .doc(workOrderId)
          .update({
        'clientStatus': clientStatus,
        'clientNotes': clientNotes,
        'history': FieldValue.arrayUnion([
          {
            'action': 'Client $clientStatus',
            'timestamp': Timestamp.now(),
            'notes': clientNotes,
          }
        ]),
      });

      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('requests')
          .doc(requestId)
          .update({
        'clientStatus': clientStatus,
        'comments': FieldValue.arrayUnion([
          {
            'text': 'Work order $clientStatus: $clientNotes',
            'by': user.email ?? 'Unknown',
            'timestamp': Timestamp.now(),
          }
        ]),
      });

      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Work order $clientStatus')),
      );
    } catch (e) {
      _logger.e('Error handling work order action: $e');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error: $e')),
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
    _logger.i('Building RequestScreen: facilityId=${widget.facilityId}');
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('Maintenance Requests')),
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
                              'Submit Request',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
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
                              validator: (value) => value!.isEmpty ? 'Enter a description' : null,
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
                              controller: _commentController,
                              decoration: const InputDecoration(
                                labelText: 'Comment (optional)',
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
                                    .map((attachment) => Chip(label: Text(attachment['name']!)))
                                    .toList(),
                              ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _submitRequest,
                              child: const Text('Submit Request'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButton<String>(
                    value: _selectedStatus,
                    items: ['All', 'Open', 'In Progress', 'Closed']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (value) => setState(() => _selectedStatus = value!),
                    underline: Container(),
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot>(
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
                      _logger.i(
                          'Requests - StreamBuilder: hasData=${snapshot.hasData}, hasError=${snapshot.hasError}, facilityId=${widget.facilityId}');
                      if (!snapshot.hasData) {
                        _logger.i('Loading requests...');
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        _logger.e('Firestore error: ${snapshot.error}');
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      final requests = snapshot.data!.docs;
                      _logger.i('Loaded ${requests.length} requests');
                      if (requests.isEmpty) return const Center(child: Text('No requests found'));
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: requests.length,
                        itemBuilder: (context, index) {
                          final request = requests[index];
                          final workOrderIds = (request['workOrderIds'] as List<dynamic>?)?.cast<String>() ?? [];
                          final comments = (request['comments'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
                          return Card(
                            elevation: 1,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ExpansionTile(
                              title: Text(request['title'] ?? 'Untitled Request'),
                              subtitle: Text('Status: ${request['status']} | Priority: ${request['priority']}'),
                              children: [
                                ListTile(
                                  title: Text('Description: ${request['description'] ?? 'N/A'}'),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('By: ${request['createdByEmail'] ?? 'Unknown'}'),
                                      Text(
                                          'Created: ${DateFormat.yMMMd().format((request['createdAt'] as Timestamp).toDate())}'),
                                      if (request['attachments'] != null &&
                                          (request['attachments'] as List<dynamic>).isNotEmpty)
                                        Wrap(
                                          spacing: 8,
                                          children: (request['attachments'] as List<dynamic>)
                                              .map((attachment) => Chip(label: Text(attachment['name'])))
                                              .toList(),
                                        ),
                                    ],
                                  ),
                                ),
                                ListTile(
                                  title: const Text('Comments'),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: comments.isEmpty
                                        ? [const Text('No comments available')]
                                        : comments
                                            .map((c) => Text(
                                                  '${c['text']} by ${c['by']} at ${DateFormat.yMMMd().format((c['timestamp'] as Timestamp).toDate())}',
                                                ))
                                            .toList(),
                                  ),
                                ),
                                ListTile(
                                  title: const Text('Work Orders'),
                                  subtitle: workOrderIds.isEmpty
                                      ? const Text('No work orders assigned')
                                      : Column(
                                          children: workOrderIds.map((workOrderId) {
                                            return StreamBuilder<DocumentSnapshot>(
                                              stream: FirebaseFirestore.instance
                                                  .collection('facilities')
                                                  .doc(widget.facilityId)
                                                  .collection('work_orders')
                                                  .doc(workOrderId)
                                                  .snapshots(),
                                              builder: (context, snapshot) {
                                                if (!snapshot.hasData) return const CircularProgressIndicator();
                                                final workOrder = snapshot.data!;
                                                return ListTile(
                                                  title: Text(workOrder['title'] ?? 'Untitled Work Order'),
                                                  subtitle: Text(
                                                      'Status: ${workOrder['clientStatus']} | Assigned: ${workOrder['assignedTo'] ?? 'Unassigned'}'),
                                                  trailing: workOrder['clientStatus'] == 'Pending'
                                                      ? Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            IconButton(
                                                              icon: const Icon(Icons.check),
                                                              onPressed: () => _handleWorkOrderAction(
                                                                  request.id, workOrderId, 'Accepted', ''),
                                                            ),
                                                            IconButton(
                                                              icon: const Icon(Icons.close),
                                                              onPressed: () => showDialog(
                                                                context: context,
                                                                builder: (context) {
                                                                  final declineReasonController = TextEditingController();
                                                                  return AlertDialog(
                                                                    title: const Text('Decline Work Order'),
                                                                    content: TextField(
                                                                      controller: declineReasonController,
                                                                      decoration: const InputDecoration(
                                                                          labelText: 'Reason for Decline'),
                                                                      maxLines: 2,
                                                                    ),
                                                                    actions: [
                                                                      TextButton(
                                                                        onPressed: () => Navigator.pop(context),
                                                                        child: const Text('Cancel'),
                                                                      ),
                                                                      TextButton(
                                                                        onPressed: () {
                                                                          _handleWorkOrderAction(
                                                                              request.id,
                                                                              workOrderId,
                                                                              'Declined',
                                                                              declineReasonController.text);
                                                                          Navigator.pop(context);
                                                                        },
                                                                        child: const Text('Decline'),
                                                                      ),
                                                                    ],
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                          ],
                                                        )
                                                      : workOrder['clientStatus'] == 'Pending Confirmation'
                                                          ? ElevatedButton(
                                                              onPressed: () => _handleWorkOrderAction(
                                                                  request.id,
                                                                  workOrderId,
                                                                  'Confirmed',
                                                                  'Client confirmed completion'),
                                                              child: const Text('Confirm'),
                                                            )
                                                          : null,
                                                );
                                              },
                                            );
                                          }).toList(),
                                        ),
                                ),
                                ListTile(
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (status) => showDialog(
                                      context: context,
                                      builder: (context) {
                                        final commentController = TextEditingController();
                                        return AlertDialog(
                                          title: const Text('Update Status'),
                                          content: TextField(
                                            controller: commentController,
                                            decoration: const InputDecoration(labelText: 'Comment (optional)'),
                                            maxLines: 2,
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                _updateRequest(request.id, status, commentController.text);
                                                Navigator.pop(context);
                                              },
                                              child: const Text('Update'),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(value: 'Open', child: Text('Open')),
                                      const PopupMenuItem(value: 'In Progress', child: Text('In Progress')),
                                      const PopupMenuItem(value: 'Closed', child: Text('Closed')),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}