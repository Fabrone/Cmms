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

class EquipmentSuppliedScreen extends StatefulWidget {
  final String facilityId;

  const EquipmentSuppliedScreen({super.key, required this.facilityId});

  @override
  State<EquipmentSuppliedScreen> createState() => _EquipmentSuppliedScreenState();
}

class _EquipmentSuppliedScreenState extends State<EquipmentSuppliedScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _typeController = TextEditingController();
  final _serialController = TextEditingController();
  final _locationController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _warrantyController = TextEditingController();
  final _notesController = TextEditingController();
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  String _status = 'Active';
  String _statusFilter = 'All';
  final List<Map<String, String>> _attachmentUrls = [];

  @override
  void initState() {
    super.initState();
    _logger.i('EquipmentSuppliedScreen initialized: facilityId=${widget.facilityId}');
  }

  Future<void> _addEquipment() async {
    if (_formKey.currentState!.validate()) {
      try {
        _logger.i('Adding equipment: name=${_nameController.text}, facilityId=${widget.facilityId}');
        if (FirebaseAuth.instance.currentUser == null) {
          _logger.e('No user signed in');
          _messengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('Please sign in to add equipment')),
          );
          return;
        }

        final equipmentId = const Uuid().v4();
        await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('assets')
            .doc(equipmentId)
            .set({
          'equipmentId': equipmentId,
          'name': _nameController.text.trim(),
          'type': _typeController.text.trim(),
          'serialNumber': _serialController.text.trim(),
          'locationId': _locationController.text.trim(),
          'purchasePrice': double.tryParse(_purchasePriceController.text) ?? 0.0,
          'purchaseDate': Timestamp.now(),
          'warrantyMonths': int.tryParse(_warrantyController.text) ?? 0,
          'status': _status,
          'notes': _notesController.text.trim(),
          'attachments': _attachmentUrls,
          'maintenanceHistory': [],
          'createdAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
          'createdBy': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
        });
        _nameController.clear();
        _typeController.clear();
        _serialController.clear();
        _locationController.clear();
        _purchasePriceController.clear();
        _warrantyController.clear();
        _notesController.clear();
        setState(() => _attachmentUrls.clear());
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Equipment added successfully')),
        );
      } catch (e) {
        _logger.e('Error adding equipment: $e');
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error adding equipment: $e')),
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
      _logger.i('Selected file: ${file.name}, extension: ${file.extension}, bytes: ${file.bytes != null}');
      if (!['pdf', 'jpg', 'png', 'docx'].contains(file.extension)) {
        _logger.w('Invalid file type: ${file.extension}');
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Please select a PDF, JPG, PNG, or DOCX file')),
        );
        return;
      }

      final fileName = '${const Uuid().v4()}_${file.name}';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('assets/${widget.facilityId}/$fileName');

      _logger.i('Uploading attachment to Storage: ${storageRef.fullPath}');
      String url;
      if (kIsWeb) {
        if (file.bytes == null) {
          throw Exception('No bytes available for web upload');
        }
        _logger.i('Uploading ${file.bytes!.length} bytes on web');
        final uploadTask = storageRef.putData(file.bytes!);
        final snapshot = await uploadTask.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw Exception('Upload timed out after 30 seconds');
          },
        );
        url = await snapshot.ref.getDownloadURL();
      } else {
        if (file.path == null) {
          throw Exception('No path available for non-web upload');
        }
        _logger.i('Uploading file from path: ${file.path}');
        final uploadTask = storageRef.putFile(File(file.path!));
        final snapshot = await uploadTask.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw Exception('Upload timed out after 30 seconds');
          },
        );
        url = await snapshot.ref.getDownloadURL();
      }

      _logger.i('Attachment uploaded successfully: $url');
      setState(() {
        _attachmentUrls.add({'name': file.name, 'url': url});
      });
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Attachment uploaded')),
      );
    } catch (e, stackTrace) {
      _logger.e('Error uploading attachment: $e', stackTrace: stackTrace);
      String errorMessage;
      if (e is FirebaseException) {
        switch (e.code) {
          case 'storage/unauthorized':
            errorMessage = 'Permission denied. Check Firebase Storage rules.';
            break;
          case 'storage/canceled':
            errorMessage = 'Upload canceled. Please try again.';
            break;
          case 'storage/quota-exceeded':
            errorMessage = 'Storage quota exceeded. Contact support.';
            break;
          default:
            errorMessage = 'Upload failed: ${e.message}';
        }
      } else if (e.toString().contains('timed out')) {
        errorMessage = 'Upload timed out. Check your network connection.';
      } else {
        errorMessage = 'Upload failed: $e';
      }
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  Future<void> _updateStatus(String docId, String newStatus, String notes) async {
    try {
      _logger.i('Updating status: docId=$docId, newStatus=$newStatus, facilityId=${widget.facilityId}');
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('assets')
          .doc(docId)
          .update({
        'status': newStatus,
        'updatedAt': Timestamp.now(),
        'maintenanceHistory': FieldValue.arrayUnion([
          {
            'action': 'Status changed to $newStatus',
            'timestamp': Timestamp.now(),
            'notes': notes,
            'userId': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          }
        ]),
      });
      _logger.i('Status updated successfully');
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

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _serialController.dispose();
    _locationController.dispose();
    _purchasePriceController.dispose();
    _warrantyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _logger.i('Building EquipmentSuppliedScreen: facilityId=${widget.facilityId}');
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('Equipment Supplied')),
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
                              'Create Equipment',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Equipment Name',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) => value!.isEmpty ? 'Enter name' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _typeController,
                              decoration: const InputDecoration(
                                labelText: 'Equipment Type',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) => value!.isEmpty ? 'Enter type' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _serialController,
                              decoration: const InputDecoration(
                                labelText: 'Serial Number (optional)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _locationController,
                              decoration: const InputDecoration(
                                labelText: 'Location ID (optional)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _purchasePriceController,
                              decoration: const InputDecoration(
                                labelText: 'Purchase Price (optional)',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _warrantyController,
                              decoration: const InputDecoration(
                                labelText: 'Warranty Months (optional)',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
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
                            DropdownButtonFormField<String>(
                              value: _status,
                              items: ['Active', 'Inactive', 'Under Repair', 'Decommissioned']
                                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (value) => setState(() => _status = value!),
                              decoration: const InputDecoration(
                                labelText: 'Status',
                                border: OutlineInputBorder(),
                              ),
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
                              onPressed: _addEquipment,
                              child: const Text('Add Equipment'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButton<String>(
                    value: _statusFilter,
                    items: ['All', 'Active', 'Inactive', 'Under Repair', 'Decommissioned']
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
                            .collection('assets')
                            .orderBy('createdAt', descending: true)
                            .snapshots()
                        : FirebaseFirestore.instance
                            .collection('facilities')
                            .doc(widget.facilityId)
                            .collection('assets')
                            .where('status', isEqualTo: _statusFilter)
                            .orderBy('createdAt', descending: true)
                            .snapshots(),
                    builder: (context, snapshot) {
                      _logger.i('Equipment - StreamBuilder: hasData=${snapshot.hasData}, hasError=${snapshot.hasError}');
                      if (!snapshot.hasData) {
                        _logger.i('Loading equipment...');
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        _logger.e('Firestore error: ${snapshot.error}');
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      final docs = snapshot.data!.docs;
                      _logger.i('Loaded ${docs.length} equipment items');
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final history = (doc['maintenanceHistory'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
                          return Card(
                            elevation: 1,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ExpansionTile(
                              title: Text(doc['name'] ?? 'Unnamed Equipment'),
                              subtitle: Text('Type: ${doc['type']} | Status: ${doc['status']}'),
                              children: [
                                ListTile(
                                  title: Text('Serial: ${doc['serialNumber'] ?? 'N/A'}'),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Location ID: ${doc['locationId'] ?? 'N/A'}'),
                                      Text('Price: \$${doc['purchasePrice'] ?? 0}'),
                                      Text('Warranty: ${doc['warrantyMonths'] ?? 0} months'),
                                      Text('Notes: ${doc['notes'] ?? 'N/A'}'),
                                      Text('Created: ${DateFormat.yMMMd().format((doc['createdAt'] as Timestamp).toDate())}'),
                                      if (doc['attachments'] != null && (doc['attachments'] as List<dynamic>).isNotEmpty)
                                        Wrap(
                                          spacing: 8,
                                          children: (doc['attachments'] as List<dynamic>)
                                              .map((attachment) => Chip(label: Text(attachment['name'])))
                                              .toList(),
                                        ),
                                    ],
                                  ),
                                ),
                                ListTile(
                                  title: const Text('Maintenance History'),
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
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (status) => _updateStatus(doc['equipmentId'], status, _notesController.text),
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(value: 'Active', child: Text('Active')),
                                      const PopupMenuItem(value: 'Inactive', child: Text('Inactive')),
                                      const PopupMenuItem(value: 'Under Repair', child: Text('Under Repair')),
                                      const PopupMenuItem(value: 'Decommissioned', child: Text('Decommissioned')),
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