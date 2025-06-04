import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/models/vendor.dart';

class VendorScreen extends StatefulWidget {
  final String facilityId;

  const VendorScreen({super.key, required this.facilityId});

  @override
  State<VendorScreen> createState() => _VendorScreenState();
}

class _VendorScreenState extends State<VendorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _serviceController = TextEditingController();
  final _contractController = TextEditingController();
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  
  String _category = 'General';
  String _status = 'Active';
  String _categoryFilter = 'All';
  String _statusFilter = 'All';
  double _rating = 5.0;
  bool _showForm = false;

  @override
  void initState() {
    super.initState();
    _logger.i('VendorScreen initialized: facilityId=${widget.facilityId}');
  }

  Future<void> _addVendor() async {
    if (_formKey.currentState!.validate()) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('Please sign in to add vendors');
        return;
      }

      try {
        final vendorId = const Uuid().v4();
        _logger.i('Adding vendor: vendorId=$vendorId, name=${_nameController.text}');
        
        final vendor = Vendor(
          id: vendorId,
          vendorId: vendorId,
          name: _nameController.text.trim(),
          contact: _contactController.text.trim(),
          email: _emailController.text.trim(),
          phone: _phoneController.text.trim(),
          services: _serviceController.text.trim(),
          contractDetails: _contractController.text.trim(),
          category: _category,
          rating: _rating,
          status: _status,
          serviceHistory: [
            {
              'action': 'Vendor Added',
              'timestamp': Timestamp.now(),
              'notes': 'Vendor registered in system',
              'userId': user.uid,
            }
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          createdBy: user.uid,
        );

        await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('vendors')
            .doc(vendorId)
            .set(vendor.toMap());

        setState(() {
          _showForm = false;
        });
        _clearForm();
        _showSnackBar('Vendor added successfully');
      } catch (e) {
        _logger.e('Error adding vendor: $e');
        _showSnackBar('Error adding vendor: $e');
      }
    }
  }

  Future<void> _addServiceHistory(String docId, String service, String notes) async {
    try {
      _logger.i('Adding service history: docId=$docId, service=$service');
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('vendors')
          .doc(docId)
          .update({
        'serviceHistory': FieldValue.arrayUnion([
          {
            'action': service,
            'timestamp': Timestamp.now(),
            'notes': notes,
            'userId': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          }
        ]),
        'updatedAt': Timestamp.now(),
      });
      _showSnackBar('Service logged successfully');
    } catch (e) {
      _logger.e('Error logging service: $e');
      _showSnackBar('Error logging service: $e');
    }
  }

  Future<void> _updateVendorRating(String docId, double newRating) async {
    try {
      _logger.i('Updating vendor rating: docId=$docId, rating=$newRating');
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('vendors')
          .doc(docId)
          .update({
        'rating': newRating,
        'updatedAt': Timestamp.now(),
        'serviceHistory': FieldValue.arrayUnion([
          {
            'action': 'Rating updated to $newRating stars',
            'timestamp': Timestamp.now(),
            'notes': 'Vendor rating updated',
            'userId': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          }
        ]),
      });
      _showSnackBar('Rating updated successfully');
    } catch (e) {
      _logger.e('Error updating rating: $e');
      _showSnackBar('Error updating rating: $e');
    }
  }

  Future<void> _updateVendorStatus(String docId, String newStatus) async {
    try {
      _logger.i('Updating vendor status: docId=$docId, status=$newStatus');
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('vendors')
          .doc(docId)
          .update({
        'status': newStatus,
        'updatedAt': Timestamp.now(),
        'serviceHistory': FieldValue.arrayUnion([
          {
            'action': 'Status changed to $newStatus',
            'timestamp': Timestamp.now(),
            'notes': 'Vendor status updated',
            'userId': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          }
        ]),
      });
      _showSnackBar('Status updated to $newStatus');
    } catch (e) {
      _logger.e('Error updating status: $e');
      _showSnackBar('Error updating status: $e');
    }
  }

  void _clearForm() {
    _nameController.clear();
    _contactController.clear();
    _emailController.clear();
    _phoneController.clear();
    _serviceController.clear();
    _contractController.clear();
    _category = 'General';
    _status = 'Active';
    _rating = 5.0;
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
    _nameController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _serviceController.dispose();
    _contractController.dispose();
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
              'Vendor Management',
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
                                items: ['All', 'General', 'Electrical', 'Plumbing', 'HVAC', 'Cleaning', 'Security', 'IT Support']
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
                              'Status:',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w500,
                                color: Colors.blueGrey[800],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _statusFilter,
                                items: ['All', 'Active', 'Inactive', 'Suspended']
                                    .map((s) => DropdownMenuItem(
                                          value: s,
                                          child: Text(s, style: GoogleFonts.poppins(color: Colors.blueGrey[800])),
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
                ),
                // Vendors List
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _buildVendorStream(),
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
                      
                      // Apply status filter
                      final filteredDocs = docs.where((doc) {
                        if (_statusFilter == 'All') return true;
                        final vendor = Vendor.fromSnapshot(doc);
                        return vendor.status == _statusFilter;
                      }).toList();

                      if (filteredDocs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.business_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No vendors found',
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
                          final vendor = Vendor.fromSnapshot(filteredDocs[index]);
                          
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                backgroundColor: _getStatusColor(vendor.status),
                                child: Icon(
                                  _getStatusIcon(vendor.status),
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                vendor.name,
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blueGrey[900],
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Category: ${vendor.category} | Status: ${vendor.status}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      ...List.generate(5, (index) => Icon(
                                        index < vendor.rating ? Icons.star : Icons.star_border,
                                        color: Colors.amber,
                                        size: 16,
                                      )),
                                      const SizedBox(width: 4),
                                      Text(
                                        '(${vendor.rating.toStringAsFixed(1)})',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildDetailRow('Contact', vendor.contact),
                                      if (vendor.email.isNotEmpty)
                                        _buildDetailRow('Email', vendor.email),
                                      if (vendor.phone.isNotEmpty)
                                        _buildDetailRow('Phone', vendor.phone),
                                      _buildDetailRow('Services', vendor.services),
                                      if (vendor.contractDetails.isNotEmpty)
                                        _buildDetailRow('Contract', vendor.contractDetails),
                                      _buildDetailRow('Created', vendor.createdAt != null ? DateFormat.yMMMd().format(vendor.createdAt!) : 'Unknown date'),
                                      if (vendor.serviceHistory.isNotEmpty) 
                                        _buildHistorySection(vendor.serviceHistory),
                                      const SizedBox(height: 12),
                                      _buildActionButtons(vendor),
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
              _showForm ? 'Cancel' : 'New Vendor',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
          bottomSheet: _showForm ? _buildVendorForm() : null,
        ),
      ),
    );
  }

  Stream<QuerySnapshot> _buildVendorStream() {
    Query query = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('vendors');

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
            width: 80,
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
            'Service History:',
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

  Widget _buildActionButtons(Vendor vendor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: () => _showLogServiceDialog(vendor),
          icon: const Icon(Icons.add_task, size: 16),
          label: Text('Log Service', style: GoogleFonts.poppins()),
          style: TextButton.styleFrom(
            foregroundColor: Colors.blueGrey[700],
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => _showRatingDialog(vendor),
          icon: const Icon(Icons.star, size: 16),
          label: Text('Rate', style: GoogleFonts.poppins()),
          style: TextButton.styleFrom(
            foregroundColor: Colors.amber[700],
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => _showStatusDialog(vendor),
          icon: const Icon(Icons.edit, size: 16),
          label: Text('Status', style: GoogleFonts.poppins()),
          style: TextButton.styleFrom(
            foregroundColor: Colors.blueGrey[700],
          ),
        ),
      ],
    );
  }

  void _showLogServiceDialog(Vendor vendor) {
    final serviceController = TextEditingController();
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Log Service', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: serviceController,
              decoration: InputDecoration(
                labelText: 'Service Performed',
                border: const OutlineInputBorder(),
                labelStyle: GoogleFonts.poppins(),
              ),
              style: GoogleFonts.poppins(),
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
              if (serviceController.text.isNotEmpty) {
                _addServiceHistory(vendor.id, serviceController.text, notesController.text);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800]),
            child: Text('Log Service', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRatingDialog(Vendor vendor) {
    double newRating = vendor.rating;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Rate Vendor', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Current Rating: ${vendor.rating.toStringAsFixed(1)}', style: GoogleFonts.poppins()),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) => GestureDetector(
                  onTap: () => setState(() => newRating = index + 1.0),
                  child: Icon(
                    index < newRating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 32,
                  ),
                )),
              ),
              const SizedBox(height: 8),
              Text('New Rating: ${newRating.toStringAsFixed(1)}', style: GoogleFonts.poppins()),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            ElevatedButton(
              onPressed: () {
                _updateVendorRating(vendor.id, newRating);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[700]),
              child: Text('Update Rating', style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showStatusDialog(Vendor vendor) {
    String selectedStatus = vendor.status;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Status', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: DropdownButtonFormField<String>(
          value: selectedStatus,
          items: ['Active', 'Inactive', 'Suspended']
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () {
              _updateVendorStatus(vendor.id, selectedStatus);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800]),
            child: Text('Update', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorForm() {
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
                'Add New Vendor',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[900],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Vendor Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                  ),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
                validator: (value) => value!.isEmpty ? 'Enter vendor name' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                        ),
                        labelStyle: GoogleFonts.poppins(),
                      ),
                      style: GoogleFonts.poppins(),
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                        ),
                        labelStyle: GoogleFonts.poppins(),
                      ),
                      style: GoogleFonts.poppins(),
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contactController,
                decoration: InputDecoration(
                  labelText: 'Primary Contact Info',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                  ),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
                validator: (value) => value!.isEmpty ? 'Enter contact info' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _category,
                items: ['General', 'Electrical', 'Plumbing', 'HVAC', 'Cleaning', 'Security', 'IT Support']
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
                controller: _serviceController,
                decoration: InputDecoration(
                  labelText: 'Services Offered',
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
              TextFormField(
                controller: _contractController,
                decoration: InputDecoration(
                  labelText: 'Contract Details (optional)',
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
                    child: DropdownButtonFormField<String>(
                      value: _status,
                      items: ['Active', 'Inactive', 'Suspended']
                          .map((status) => DropdownMenuItem(
                                value: status,
                                child: Text(status, style: GoogleFonts.poppins()),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => _status = value!),
                      decoration: InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
                        ),
                        labelStyle: GoogleFonts.poppins(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Initial Rating', style: GoogleFonts.poppins(color: Colors.blueGrey[700])),
                        const SizedBox(height: 8),
                        Row(
                          children: List.generate(5, (index) => GestureDetector(
                            onTap: () => setState(() => _rating = index + 1.0),
                            child: Icon(
                              index < _rating ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 24,
                            ),
                          )),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _addVendor,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey[800],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    'Add Vendor',
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
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.grey;
      case 'suspended':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Icons.check_circle;
      case 'inactive':
        return Icons.pause_circle;
      case 'suspended':
        return Icons.block;
      default:
        return Icons.help;
    }
  }
}