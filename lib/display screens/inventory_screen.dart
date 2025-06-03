import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/models/inventory.dart';

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
  String _stockFilter = 'All';
  bool _showForm = false;

  @override
  void initState() {
    super.initState();
    _logger.i('InventoryScreen initialized: facilityId=${widget.facilityId}');
  }

  Future<void> _addItem() async {
    if (_formKey.currentState!.validate()) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('Please sign in to add inventory items');
        return;
      }

      try {
        final itemId = const Uuid().v4();
        _logger.i('Adding inventory item: itemId=$itemId, name=${_itemNameController.text}');
        
        final inventoryItem = InventoryItem(
          id: itemId,
          itemId: itemId,
          itemName: _itemNameController.text.trim(),
          quantity: int.parse(_quantityController.text),
          reorderPoint: int.parse(_reorderPointController.text.isEmpty ? '0' : _reorderPointController.text),
          category: _category,
          locationId: _locationController.text.trim(),
          notes: _notesController.text.trim(),
          lastUpdated: DateTime.now(),
          createdAt: DateTime.now(),
          createdBy: user.uid,
          history: [
            {
              'action': 'Item Created',
              'timestamp': Timestamp.now(),
              'notes': _notesController.text.trim(),
              'userId': user.uid,
              'quantity': int.parse(_quantityController.text),
            }
          ],
        );

        await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('inventory')
            .doc(itemId)
            .set(inventoryItem.toMap());

        setState(() {
          _showForm = false;
        });
        _clearForm();
        _showSnackBar('Inventory item added successfully');
      } catch (e) {
        _logger.e('Error adding item: $e');
        _showSnackBar('Error adding item: $e');
      }
    }
  }

  Future<void> _updateQuantity(String docId, int newQuantity, String notes) async {
    try {
      _logger.i('Updating quantity: docId=$docId, newQuantity=$newQuantity');
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('inventory')
          .doc(docId)
          .update({
        'quantity': newQuantity,
        'lastUpdated': Timestamp.now(),
        'history': FieldValue.arrayUnion([
          {
            'action': 'Quantity updated to $newQuantity',
            'timestamp': Timestamp.now(),
            'notes': notes,
            'userId': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
            'quantity': newQuantity,
          }
        ]),
      });
      _showSnackBar('Quantity updated successfully');
    } catch (e) {
      _logger.e('Error updating quantity: $e');
      _showSnackBar('Error updating quantity: $e');
    }
  }

  Future<void> _deleteItem(String docId, String itemName) async {
    try {
      _logger.i('Deleting item: docId=$docId, itemName=$itemName');
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('inventory')
          .doc(docId)
          .delete();
      _showSnackBar('Item "$itemName" deleted successfully');
    } catch (e) {
      _logger.e('Error deleting item: $e');
      _showSnackBar('Error deleting item: $e');
    }
  }

  void _clearForm() {
    _itemNameController.clear();
    _quantityController.clear();
    _reorderPointController.clear();
    _locationController.clear();
    _notesController.clear();
    _category = 'General';
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
    _itemNameController.dispose();
    _quantityController.dispose();
    _reorderPointController.dispose();
    _locationController.dispose();
    _notesController.dispose();
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
              'Inventory Management',
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
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  'Category:',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w500,
                                    color: Colors.blueGrey[800],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _categoryFilter,
                                    items: ['All', 'General', 'Electrical', 'Mechanical', 'HVAC', 'Plumbing', 'Safety', 'Cleaning']
                                        .map((c) => DropdownMenuItem(
                                              value: c,
                                              child: Text(c, style: GoogleFonts.poppins(color: Colors.blueGrey[800])),
                                            ))
                                        .toList(),
                                    onChanged: (value) => setState(() => _categoryFilter = value!),
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
                          const SizedBox(width: 16),
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  'Stock:',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w500,
                                    color: Colors.blueGrey[800],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _stockFilter,
                                    items: ['All', 'Low Stock', 'In Stock', 'Out of Stock']
                                        .map((s) => DropdownMenuItem(
                                              value: s,
                                              child: Text(s, style: GoogleFonts.poppins(color: Colors.blueGrey[800])),
                                            ))
                                        .toList(),
                                    onChanged: (value) => setState(() => _stockFilter = value!),
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
                        ],
                      ),
                    ],
                  ),
                ),
                // Inventory List
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _buildInventoryStream(),
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
                      
                      // Apply stock filter
                      final filteredDocs = docs.where((doc) {
                        if (_stockFilter == 'All') return true;
                        final item = InventoryItem.fromSnapshot(doc);
                        switch (_stockFilter) {
                          case 'Low Stock':
                            return item.isLowStock && item.quantity > 0;
                          case 'In Stock':
                            return item.quantity > item.reorderPoint;
                          case 'Out of Stock':
                            return item.quantity == 0;
                          default:
                            return true;
                        }
                      }).toList();

                      if (filteredDocs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No inventory items found',
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
                        itemCount: filteredDocs.length,
                        itemBuilder: (context, index) {
                          final inventoryItem = InventoryItem.fromSnapshot(filteredDocs[index]);
                          
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            color: inventoryItem.isLowStock ? Colors.orange[50] : null,
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                backgroundColor: _getStockColor(inventoryItem),
                                child: Icon(
                                  _getStockIcon(inventoryItem),
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                inventoryItem.itemName,
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blueGrey[900],
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Category: ${inventoryItem.category} | Quantity: ${inventoryItem.quantity}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  if (inventoryItem.isLowStock)
                                    Text(
                                      'LOW STOCK WARNING',
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: Colors.orange[700],
                                        fontWeight: FontWeight.bold,
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
                                      _buildDetailRow('Reorder Point', '${inventoryItem.reorderPoint}'),
                                      _buildDetailRow('Location ID', inventoryItem.locationId.isEmpty ? 'N/A' : inventoryItem.locationId),
                                      _buildDetailRow('Created', inventoryItem.createdAt != null ? DateFormat.yMMMd().format(inventoryItem.createdAt!) : 'Unknown date'),
                                      _buildDetailRow('Last Updated', inventoryItem.lastUpdated != null ? DateFormat.yMMMd().format(inventoryItem.lastUpdated!) : 'Never'),
                                      if (inventoryItem.notes.isNotEmpty)
                                        _buildDetailRow('Notes', inventoryItem.notes),
                                      if (inventoryItem.history.isNotEmpty) 
                                        _buildHistorySection(inventoryItem.history),
                                      const SizedBox(height: 12),
                                      _buildActionButtons(inventoryItem),
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
              _showForm ? 'Cancel' : 'New Item',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
          bottomSheet: _showForm ? _buildInventoryForm() : null,
        ),
      ),
    );
  }

  Stream<QuerySnapshot> _buildInventoryStream() {
    Query query = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('inventory');

    if (_categoryFilter != 'All') {
      query = query.where('category', isEqualTo: _categoryFilter);
    }

    return query.orderBy('createdAt', descending: true).snapshots();
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
          ...history.take(3).map((entry) => Container(
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
          if (history.length > 3)
            Text(
              '... and ${history.length - 3} more entries',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(InventoryItem item) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: () => _showUpdateQuantityDialog(item),
          icon: const Icon(Icons.edit, size: 16),
          label: Text('Update Qty', style: GoogleFonts.poppins()),
          style: TextButton.styleFrom(
            foregroundColor: Colors.blueGrey[700],
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => _showDeleteConfirmDialog(item),
          icon: const Icon(Icons.delete, size: 16),
          label: Text('Delete', style: GoogleFonts.poppins()),
          style: TextButton.styleFrom(
            foregroundColor: Colors.red[700],
          ),
        ),
      ],
    );
  }

  void _showUpdateQuantityDialog(InventoryItem item) {
    final quantityController = TextEditingController(text: item.quantity.toString());
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Quantity', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: quantityController,
              decoration: InputDecoration(
                labelText: 'New Quantity',
                border: const OutlineInputBorder(),
                labelStyle: GoogleFonts.poppins(),
              ),
              style: GoogleFonts.poppins(),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: InputDecoration(
                labelText: 'Update Notes (optional)',
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
              final newQuantity = int.tryParse(quantityController.text);
              if (newQuantity != null) {
                _updateQuantity(item.id, newQuantity, notesController.text);
                Navigator.pop(context);
              } else {
                _showSnackBar('Please enter a valid quantity');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800]),
            child: Text('Update', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(InventoryItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Item', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete "${item.itemName}"? This action cannot be undone.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () {
              _deleteItem(item.id, item.itemName);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryForm() {
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
                'Add New Inventory Item',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[900],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _itemNameController,
                decoration: InputDecoration(
                  labelText: 'Item Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                  ),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
                validator: (value) => value!.isEmpty ? 'Enter item name' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _quantityController,
                      decoration: InputDecoration(
                        labelText: 'Quantity',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                        ),
                        labelStyle: GoogleFonts.poppins(),
                      ),
                      style: GoogleFonts.poppins(),
                      keyboardType: TextInputType.number,
                      validator: (value) => value!.isEmpty ? 'Enter quantity' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _reorderPointController,
                      decoration: InputDecoration(
                        labelText: 'Reorder Point',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                        ),
                        labelStyle: GoogleFonts.poppins(),
                        hintText: 'Optional',
                        hintStyle: GoogleFonts.poppins(color: Colors.grey),
                      ),
                      style: GoogleFonts.poppins(),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _category,
                items: ['General', 'Electrical', 'Mechanical', 'HVAC', 'Plumbing', 'Safety', 'Cleaning']
                    .map((category) => DropdownMenuItem(
                          value: category,
                          child: Text(category, style: GoogleFonts.poppins()),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _category = value!),
                decoration: InputDecoration(
                  labelText: 'Category',
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
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: 'Location ID (optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                  ),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
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
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _addItem,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey[800],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    'Add Inventory Item',
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

  Color _getStockColor(InventoryItem item) {
    if (item.quantity == 0) {
      return Colors.red;
    } else if (item.isLowStock) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  IconData _getStockIcon(InventoryItem item) {
    if (item.quantity == 0) {
      return Icons.remove_circle;
    } else if (item.isLowStock) {
      return Icons.warning;
    } else {
      return Icons.check_circle;
    }
  }
}