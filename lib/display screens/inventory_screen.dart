import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/models/inventory.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';

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
  String _category = 'General';
  String _categoryFilter = 'All';
  String _stockFilter = 'All';
  bool _showForm = false;

  @override
  void initState() {
    super.initState();
    _logger.i('InventoryScreen initialized: facilityId=${widget.facilityId}');
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

  Future<void> _addItem() async {
    if (_formKey.currentState!.validate()) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) _showSnackBar('Please sign in to add inventory items');
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

        if (mounted) {
          setState(() {
            _showForm = false;
          });
          _clearForm();
          _showSnackBar('Inventory item added successfully');
        }
      } catch (e, stackTrace) {
        _logger.e('Error adding item: $e', stackTrace: stackTrace);
        if (mounted) _showSnackBar('Error adding item: $e');
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
      if (mounted) _showSnackBar('Quantity updated successfully');
    } catch (e, stackTrace) {
      _logger.e('Error updating quantity: $e', stackTrace: stackTrace);
      if (mounted) _showSnackBar('Error updating quantity: $e');
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
      if (mounted) _showSnackBar('Item "$itemName" deleted successfully');
    } catch (e, stackTrace) {
      _logger.e('Error deleting item: $e', stackTrace: stackTrace);
      if (mounted) _showSnackBar('Error deleting item: $e');
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Inventory Management',
      facilityId: widget.facilityId,
      currentRole: 'User',
      organization: '-',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _showForm = !_showForm),
        backgroundColor: Colors.blueGrey[800],
        icon: Icon(_showForm ? Icons.close : Icons.add, color: Colors.white),
        label: Text(
          _showForm ? 'Cancel' : 'New Item',
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
    final isTablet = screenWidth > 600 && screenWidth <= 900;
    final padding = isMobile ? 16.0 : isTablet ? 24.0 : 32.0;
    final fontSizeTitle = isMobile ? 20.0 : isTablet ? 24.0 : 28.0;
    final fontSizeSubtitle = isMobile ? 14.0 : isTablet ? 16.0 : 18.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterSection(padding, fontSizeSubtitle),
          const SizedBox(height: 24),
          if (_showForm) _buildForm(padding, fontSizeTitle, fontSizeSubtitle),
          const SizedBox(height: 24),
          Text(
            'Inventory List',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: fontSizeTitle,
              color: Colors.blueGrey[900],
            ),
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: _buildInventoryStream(),
            builder: (context, snapshot) {
              _logger.i('StreamBuilder snapshot: connectionState=${snapshot.connectionState}, hasError=${snapshot.hasError}, docCount=${snapshot.data?.docs.length ?? 0}');
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                _logger.e('Firestore error: ${snapshot.error}');
                return Text('Error: ${snapshot.error}', style: GoogleFonts.poppins());
              }
              final docs = snapshot.data!.docs;
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
                          fontSize: fontSizeSubtitle,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredDocs.length,
                itemBuilder: (context, index) {
                  final inventoryItem = InventoryItem.fromSnapshot(filteredDocs[index]);
                  return _buildInventoryCard(inventoryItem, isMobile, fontSizeSubtitle);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection(double padding, double fontSize) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.all(padding),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: isMobile
            ? Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildFilterDropdown('Category', _categoryFilter, ['All', 'General', 'Electrical', 'Mechanical', 'HVAC', 'Plumbing', 'Safety', 'Cleaning'], (value) => setState(() => _categoryFilter = value!), fontSize),
                  _buildFilterDropdown('Stock', _stockFilter, ['All', 'Low Stock', 'In Stock', 'Out of Stock'], (value) => setState(() => _stockFilter = value!), fontSize),
                ],
              )
            : Row(
                children: [
                  Expanded(child: _buildFilterDropdown('Category', _categoryFilter, ['All', 'General', 'Electrical', 'Mechanical', 'HVAC', 'Plumbing', 'Safety', 'Cleaning'], (value) => setState(() => _categoryFilter = value!), fontSize)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildFilterDropdown('Stock', _stockFilter, ['All', 'Low Stock', 'In Stock', 'Out of Stock'], (value) => setState(() => _stockFilter = value!), fontSize)),
                ],
              ),
      ),
    );
  }

  Widget _buildFilterDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged, double fontSize) {
    return DropdownButtonFormField<String>(
      value: value,
      items: items.map((s) => DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.poppins(fontSize: fontSize)))).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
      ),
      style: GoogleFonts.poppins(color: Colors.blueGrey[800], fontWeight: FontWeight.w500),
      dropdownColor: Colors.white,
      icon: const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
    );
  }

  Widget _buildInventoryCard(InventoryItem item, bool isMobile, double fontSize) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: item.isLowStock ? Colors.orange[50] : null,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _getStockColor(item),
          child: Icon(
            _getStockIcon(item),
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          item.itemName,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.blueGrey[900],
            fontSize: fontSize,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Category: ${item.category} | Quantity: ${item.quantity}',
              style: GoogleFonts.poppins(
                fontSize: fontSize - 2,
                color: Colors.grey[600],
              ),
            ),
            if (item.isLowStock)
              Text(
                'LOW STOCK WARNING',
                style: GoogleFonts.poppins(
                  fontSize: fontSize - 3,
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
                _buildDetailRow('Reorder Point', '${item.reorderPoint}', fontSize),
                _buildDetailRow('Location ID', item.locationId.isEmpty ? 'N/A' : item.locationId, fontSize),
                _buildDetailRow('Created', item.createdAt != null ? DateFormat.yMMMd().format(item.createdAt!) : 'Unknown date', fontSize),
                _buildDetailRow('Last Updated', item.lastUpdated != null ? DateFormat.yMMMd().format(item.lastUpdated!) : 'Never', fontSize),
                if (item.notes.isNotEmpty) _buildDetailRow('Notes', item.notes, fontSize),
                if (item.history.isNotEmpty) _buildHistorySection(item.history, fontSize),
                const SizedBox(height: 12),
                _buildActionButtons(item),
              ],
            ),
          ),
        ],
      ),
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
                fontSize: fontSize - 2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                color: Colors.grey[800],
                fontSize: fontSize - 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(List<Map<String, dynamic>> history, double fontSize) {
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
              fontSize: fontSize - 2,
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
                      style: GoogleFonts.poppins(fontSize: fontSize - 2, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'at ${entry['timestamp'] != null ? DateFormat.yMMMd().format((entry['timestamp'] as Timestamp).toDate()) : 'Unknown date'}',
                      style: GoogleFonts.poppins(
                        fontSize: fontSize - 4,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (entry['notes'] != null && entry['notes'].isNotEmpty)
                      Text(
                        entry['notes'],
                        style: GoogleFonts.poppins(fontSize: fontSize - 3),
                      ),
                  ],
                ),
              )),
          if (history.length > 3)
            Text(
              '... and ${history.length - 3} more entries',
              style: GoogleFonts.poppins(
                fontSize: fontSize - 3,
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
          icon: const Icon(Icons.edit, size: 16, color: Colors.blueGrey),
          label: Text('Update Qty', style: GoogleFonts.poppins(color: Colors.blueGrey)),
          style: TextButton.styleFrom(foregroundColor: Colors.blueGrey[700]),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => _showDeleteConfirmDialog(item),
          icon: const Icon(Icons.delete, size: 16, color: Colors.red),
          label: Text('Delete', style: GoogleFonts.poppins(color: Colors.red)),
          style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
        ),
      ],
    );
  }

  Widget _buildForm(double padding, double fontSizeTitle, double fontSizeSubtitle) {
    final isMobile = MediaQuery.of(context).size.width <= 600;
    final isTablet = MediaQuery.of(context).size.width > 600 && MediaQuery.of(context).size.width <= 900;

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
                    'Add New Inventory Item',
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
                        _buildTextField(_itemNameController, 'Item Name', fontSizeSubtitle, validator: (value) => value!.isEmpty ? 'Enter item name' : null),
                        const SizedBox(height: 16),
                        _buildTextField(
                          _quantityController,
                          'Quantity',
                          fontSizeSubtitle,
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value!.isEmpty) return 'Enter quantity';
                            final qty = int.tryParse(value);
                            if (qty == null || qty < 0) return 'Enter a valid non-negative quantity';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          _reorderPointController,
                          'Reorder Point (optional)',
                          fontSizeSubtitle,
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value!.isNotEmpty) {
                              final point = int.tryParse(value);
                              if (point == null || point < 0) return 'Enter a valid non-negative number';
                            }
                            return null;
                          },
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildTextField(_itemNameController, 'Item Name', fontSizeSubtitle, validator: (value) => value!.isEmpty ? 'Enter item name' : null),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            _quantityController,
                            'Quantity',
                            fontSizeSubtitle,
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value!.isEmpty) return 'Enter quantity';
                              final qty = int.tryParse(value);
                              if (qty == null || qty < 0) return 'Enter a valid non-negative quantity';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            _reorderPointController,
                            'Reorder Point (optional)',
                            fontSizeSubtitle,
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value!.isNotEmpty) {
                                final point = int.tryParse(value);
                                if (point == null || point < 0) return 'Enter a valid non-negative number';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 16),
              isMobile || isTablet
                  ? Column(
                      children: [
                        _buildCategoryDropdown(fontSizeSubtitle),
                        const SizedBox(height: 16),
                        _buildTextField(_locationController, 'Location ID (optional)', fontSizeSubtitle),
                        const SizedBox(height: 16),
                        _buildTextField(_notesController, 'Notes (optional)', fontSizeSubtitle, maxLines: 2),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildCategoryDropdown(fontSizeSubtitle),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(_locationController, 'Location ID (optional)', fontSizeSubtitle),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(_notesController, 'Notes (optional)', fontSizeSubtitle, maxLines: 2),
                        ),
                      ],
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
                      fontSize: fontSizeSubtitle,
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

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    double fontSize, {
    TextInputType? keyboardType,
    int? maxLines,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
      keyboardType: keyboardType,
      maxLines: maxLines ?? 1,
      validator: validator,
    );
  }

  Widget _buildCategoryDropdown(double fontSize) {
    return DropdownButtonFormField<String>(
      value: _category,
      items: ['General', 'Electrical', 'Mechanical', 'HVAC', 'Plumbing', 'Safety', 'Cleaning']
          .map((category) => DropdownMenuItem(value: category, child: Text(category, style: GoogleFonts.poppins(fontSize: fontSize))))
          .toList(),
      onChanged: (value) {
        setState(() {
          _category = value!;
        });
      },
      decoration: InputDecoration(
        labelText: 'Category',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
      ),
      style: GoogleFonts.poppins(color: Colors.blueGrey[800], fontWeight: FontWeight.w500),
      dropdownColor: Colors.white,
      icon: const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
    );
  }

  void _showUpdateQuantityDialog(InventoryItem item) {
    final quantityController = TextEditingController(text: item.quantity.toString());
    final notesController = TextEditingController();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Quantity', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: quantityController,
              decoration: InputDecoration(
                labelText: 'New Quantity',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[100],
                labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
              ),
              style: GoogleFonts.poppins(),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value!.isEmpty) return 'Enter quantity';
                final qty = int.tryParse(value);
                if (qty == null || qty < 0) return 'Enter a valid non-negative quantity';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: notesController,
              decoration: InputDecoration(
                labelText: 'Update Notes (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[100],
                labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
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
              if (newQuantity != null && newQuantity >= 0) {
                _updateQuantity(item.id, newQuantity, notesController.text);
                Navigator.pop(context);
              } else {
                _showSnackBar('Please enter a valid non-negative quantity');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey[800],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Update', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(InventoryItem item) {
    if (!mounted) return;

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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
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

  Color _getStockColor(InventoryItem item) {
    if (item.quantity == 0) {
      return Colors.red.shade600;
    } else if (item.isLowStock) {
      return Colors.orange.shade600;
    } else {
      return Colors.green.shade600;
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