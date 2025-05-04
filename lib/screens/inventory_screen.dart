import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

class InventoryScreen extends StatefulWidget {
  final String facilityId;

  const InventoryScreen({super.key, required this.facilityId});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _itemNameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _reorderPointController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  String _category = 'General';
  String _categoryFilter = 'All';

  @override
  void initState() {
    super.initState();
    _logger.i('InventoryScreen initialized: facilityId=${widget.facilityId}');
  }

  Future<void> _addItem() async {
    if (_formKey.currentState!.validate()) {
      try {
        _logger.i('Adding inventory item: name=${_itemNameController.text}, facilityId=${widget.facilityId}');
        if (FirebaseAuth.instance.currentUser == null) {
          _logger.e('No user signed in');
          _messengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('Please sign in to add inventory items')),
          );
          return;
        }

        final itemId = const Uuid().v4();
        await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('inventory')
            .doc(itemId)
            .set({
          'itemId': itemId,
          'itemName': _itemNameController.text.trim(),
          'quantity': int.parse(_quantityController.text),
          'reorderPoint': int.parse(_reorderPointController.text.isEmpty ? '0' : _reorderPointController.text),
          'category': _category,
          'locationId': _locationController.text.trim(),
          'notes': _notesController.text.trim(),
          'lastUpdated': Timestamp.now(),
          'createdAt': Timestamp.now(),
          'createdBy': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          'history': [
            {
              'action': 'Created',
              'timestamp': Timestamp.now(),
              'notes': _notesController.text.trim(),
            }
          ],
        });
        _itemNameController.clear();
        _quantityController.clear();
        _reorderPointController.clear();
        _locationController.clear();
        _notesController.clear();
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Item added successfully')),
        );
      } catch (e) {
        _logger.e('Error adding item: $e');
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error adding item: $e')),
        );
      }
    }
  }

  Future<void> _updateItem(String docId, Map<String, dynamic> data, String notes) async {
    try {
      _logger.i('Updating item: docId=$docId, facilityId=${widget.facilityId}');
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('inventory')
          .doc(docId)
          .update({
        ...data,
        'lastUpdated': Timestamp.now(),
        'history': FieldValue.arrayUnion([
          {
            'action': 'Updated quantity to ${data['quantity']}',
            'timestamp': Timestamp.now(),
            'notes': notes,
            'userId': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          }
        ]),
      });
      _logger.i('Item updated successfully');
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Item updated')),
      );
    } catch (e) {
      _logger.e('Error updating item: $e');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error updating item: $e')),
      );
    }
  }

  @override
  void dispose() {
    _itemNameController.dispose();
    _quantityController.dispose();
    _reorderPointController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _logger.i('Building InventoryScreen: facilityId=${widget.facilityId}');
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('Inventory')),
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
                              'Add Inventory Item',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _itemNameController,
                              decoration: const InputDecoration(
                                labelText: 'Item Name',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) => value!.isEmpty ? 'Enter item name' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _quantityController,
                              decoration: const InputDecoration(
                                labelText: 'Quantity',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) => value!.isEmpty ? 'Enter quantity' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _reorderPointController,
                              decoration: const InputDecoration(
                                labelText: 'Reorder Point (optional)',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
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
                              controller: _notesController,
                              decoration: const InputDecoration(
                                labelText: 'Notes (optional)',
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _category,
                              items: ['General', 'Electrical', 'Mechanical', 'HVAC']
                                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                  .toList(),
                              onChanged: (value) => setState(() => _category = value!),
                              decoration: const InputDecoration(
                                labelText: 'Category',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _addItem,
                              child: const Text('Add Item'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButton<String>(
                    value: _categoryFilter,
                    items: ['All', 'General', 'Electrical', 'Mechanical', 'HVAC']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (value) => setState(() => _categoryFilter = value!),
                    underline: Container(),
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream: _categoryFilter == 'All'
                        ? FirebaseFirestore.instance
                            .collection('facilities')
                            .doc(widget.facilityId)
                            .collection('inventory')
                            .orderBy('createdAt', descending: true)
                            .snapshots()
                        : FirebaseFirestore.instance
                            .collection('facilities')
                            .doc(widget.facilityId)
                            .collection('inventory')
                            .where('category', isEqualTo: _categoryFilter)
                            .orderBy('createdAt', descending: true)
                            .snapshots(),
                    builder: (context, snapshot) {
                      _logger.i('Inventory - StreamBuilder: hasData=${snapshot.hasData}, hasError=${snapshot.hasError}');
                      if (!snapshot.hasData) {
                        _logger.i('Loading inventory...');
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        _logger.e('Firestore error: ${snapshot.error}');
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      final docs = snapshot.data!.docs;
                      _logger.i('Loaded ${docs.length} inventory items');
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final quantity = doc['quantity'] as int;
                          final reorderPoint = doc['reorderPoint'] as int;
                          final history = (doc['history'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
                          return Card(
                            elevation: 1,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: quantity < reorderPoint ? Colors.yellow[100] : null,
                            child: ExpansionTile(
                              title: Text(doc['itemName'] ?? 'Unnamed Item'),
                              subtitle: Text('Category: ${doc['category']} | Quantity: $quantity'),
                              children: [
                                ListTile(
                                  title: Text('Reorder Point: $reorderPoint'),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Location ID: ${doc['locationId'] ?? 'N/A'}'),
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
                                    icon: const Icon(Icons.edit),
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) {
                                          final qtyController = TextEditingController(text: quantity.toString());
                                          final notesController = TextEditingController();
                                          return AlertDialog(
                                            title: const Text('Update Quantity'),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                TextField(
                                                  controller: qtyController,
                                                  decoration: const InputDecoration(labelText: 'New Quantity'),
                                                  keyboardType: TextInputType.number,
                                                ),
                                                TextField(
                                                  controller: notesController,
                                                  decoration: const InputDecoration(labelText: 'Update Notes'),
                                                  maxLines: 2,
                                                ),
                                              ],
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  _updateItem(
                                                    doc['itemId'],
                                                    {'quantity': int.parse(qtyController.text)},
                                                    notesController.text.trim(),
                                                  );
                                                  Navigator.pop(context);
                                                },
                                                child: const Text('Update'),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    },
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