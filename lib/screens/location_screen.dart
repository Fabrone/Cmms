import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

class LocationScreen extends StatefulWidget {
  final String facilityId;

  const LocationScreen({super.key, required this.facilityId});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _typeController = TextEditingController();
  final _parentController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _logger.i('LocationScreen initialized: facilityId=${widget.facilityId}');
  }

  Future<void> _addLocation() async {
    if (_formKey.currentState!.validate()) {
      try {
        _logger.i('Adding location: name=${_nameController.text}, facilityId=${widget.facilityId}');
        if (FirebaseAuth.instance.currentUser == null) {
          _logger.e('No user signed in');
          _messengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('Please sign in to add locations')),
          );
          return;
        }

        final locationId = const Uuid().v4();
        await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('locations')
            .doc(locationId)
            .set({
          'locationId': locationId,
          'name': _nameController.text.trim(),
          'type': _typeController.text.trim(),
          'parentId': _parentController.text.isEmpty ? null : _parentController.text.trim(),
          'address': _addressController.text.trim(),
          'notes': _notesController.text.trim(),
          'createdAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
          'createdBy': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          'history': [
            {
              'action': 'Created',
              'timestamp': Timestamp.now(),
              'notes': _notesController.text.trim(),
            }
          ],
        });
        _nameController.clear();
        _typeController.clear();
        _parentController.clear();
        _addressController.clear();
        _notesController.clear();
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Location added successfully')),
        );
      } catch (e) {
        _logger.e('Error adding location: $e');
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error adding location: $e')),
        );
      }
    }
  }

  Future<void> _deleteLocation(String docId, String notes) async {
    try {
      _logger.i('Deleting location: docId=$docId, facilityId=${widget.facilityId}');
      final assets = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('assets')
          .where('locationId', isEqualTo: docId)
          .get();
      final inventory = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('inventory')
          .where('locationId', isEqualTo: docId)
          .get();
      if (assets.docs.isNotEmpty || inventory.docs.isNotEmpty) {
        _logger.w('Cannot delete location with assigned assets or inventory');
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Cannot delete location with assigned assets or inventory')),
        );
        return;
      }

      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('locations')
          .doc(docId)
          .delete();
      _logger.i('Location deleted successfully');
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Location deleted successfully')),
      );
    } catch (e) {
      _logger.e('Error deleting location: $e');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error deleting location: $e')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _parentController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _logger.i('Building LocationScreen: facilityId=${widget.facilityId}');
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('Locations')),
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
                              'Add Location',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Location Name',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) => value!.isEmpty ? 'Enter name' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _typeController,
                              decoration: const InputDecoration(
                                labelText: 'Type (e.g., Building, Room)',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) => value!.isEmpty ? 'Enter type' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _parentController,
                              decoration: const InputDecoration(
                                labelText: 'Parent Location ID (optional)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _addressController,
                              decoration: const InputDecoration(
                                labelText: 'Address (optional)',
                                border: OutlineInputBorder(),
                              ),
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
                            ElevatedButton(
                              onPressed: _addLocation,
                              child: const Text('Add Location'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('facilities')
                        .doc(widget.facilityId)
                        .collection('locations')
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      _logger.i('Locations - StreamBuilder: hasData=${snapshot.hasData}, hasError=${snapshot.hasError}');
                      if (!snapshot.hasData) {
                        _logger.i('Loading locations...');
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        _logger.e('Firestore error: ${snapshot.error}');
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      final docs = snapshot.data!.docs;
                      _logger.i('Loaded ${docs.length} locations');
                      if (docs.isEmpty) return const Center(child: Text('No locations found'));
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final history = (doc['history'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
                          return Card(
                            elevation: 1,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ExpansionTile(
                              title: Text(doc['name'] ?? 'Unnamed Location'),
                              subtitle: Text('Type: ${doc['type']}'),
                              children: [
                                ListTile(
                                  title: Text('Parent: ${doc['parentId'] ?? 'None'}'),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Address: ${doc['address'] ?? 'N/A'}'),
                                      Text('Notes: ${doc['notes'] ?? 'N/A'}'),
                                      Text('Created: ${DateFormat.yMMMd().format((doc['createdAt'] as Timestamp).toDate())}'),
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
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => showDialog(
                                      context: context,
                                      builder: (context) {
                                        final notesController = TextEditingController();
                                        return AlertDialog(
                                          title: const Text('Delete Location'),
                                          content: TextField(
                                            controller: notesController,
                                            decoration: const InputDecoration(labelText: 'Deletion Notes (optional)'),
                                            maxLines: 2,
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                _deleteLocation(doc['locationId'], notesController.text.trim());
                                                Navigator.pop(context);
                                              },
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
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