import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
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
  String _category = 'General';
  String _status = 'Active';
  String _categoryFilter = 'All';
  String _statusFilter = 'All';
  double _rating = 5.0;
  bool _showForm = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _logger.i('VendorScreen initialized: facilityId=${widget.facilityId}');
  }

  Future<void> _addVendor() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar('Please sign in to add vendors');
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

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
        userId: user.uid,
        facilityId: widget.facilityId,
      );

      await FirebaseFirestore.instance
          .collection('Vendors')
          .doc(vendorId)
          .set(vendor.toMap());

      if (mounted) {
        setState(() {
          _showForm = false;
          _isLoading = false;
        });
        _clearForm();
        _showSnackBar('Vendor added successfully');
      }
    } catch (e, stackTrace) {
      _logger.e('Error adding vendor: $e', stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Error adding vendor: $e');
      }
    }
  }

  Future<void> _addServiceHistory(String docId, String service, String notes) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      _logger.i('Adding service history: docId=$docId, service=$service');
      await FirebaseFirestore.instance
          .collection('Vendors')
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
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Service logged successfully');
      }
    } catch (e, stackTrace) {
      _logger.e('Error logging service: $e', stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Error logging service: $e');
      }
    }
  }

  Future<void> _updateVendorRating(String docId, double newRating) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      _logger.i('Updating vendor rating: docId=$docId, rating=$newRating');
      await FirebaseFirestore.instance
          .collection('Vendors')
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
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Rating updated successfully');
      }
    } catch (e, stackTrace) {
      _logger.e('Error updating rating: $e', stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Error updating rating: $e');
      }
    }
  }

  Future<void> _updateVendorStatus(String docId, String newStatus) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      _logger.i('Updating vendor status: docId=$docId, status=$newStatus');
      await FirebaseFirestore.instance
          .collection('Vendors')
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
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Status updated to $newStatus');
      }
    } catch (e, stackTrace) {
      _logger.e('Error updating status: $e', stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Error updating status: $e');
      }
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

  void _clearFilters() {
    if (mounted) {
      setState(() {
        _categoryFilter = 'All';
        _statusFilter = 'All';
      });
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
    return ResponsiveScreenWrapper(
      title: 'Vendor Management',
      facilityId: widget.facilityId,
      currentRole: 'Engineer',
      organization: '-',
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _showForm = !_showForm),
        backgroundColor: Colors.blueGrey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Icon(_showForm ? Icons.close : Icons.add, color: Colors.white),
      ),
      child: Stack(
        children: [
          _buildBody(),
          if (_showForm) _buildFormOverlay(),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 768;
    final isTablet = screenWidth > 768 && screenWidth <= 1024;
    final padding = isMobile ? 8.0 : isTablet ? 12.0 : 16.0;
    final fontSizeTitle = isMobile ? 16.0 : isTablet ? 20.0 : 24.0;
    final fontSize = isMobile ? 12.0 : isTablet ? 14.0 : 16.0;

    return Column(
      children: [
        _buildFilterSection(padding: padding, fontSizeTitle: fontSizeTitle, fontSize: fontSize, isMobile: isMobile),
        Expanded(child: _buildVendorList(padding: padding, fontSize: fontSize)),
      ],
    );
  }

  Widget _buildFilterSection({required double padding, required double fontSizeTitle, required double fontSize, required bool isMobile}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Vendor Filters',
                  style: GoogleFonts.poppins(
                    fontSize: fontSizeTitle,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey[900],
                  ),
                ),
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear, size: 16, color: Colors.blueGrey),
                  label: Text('Clear Filters', style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.blueGrey)),
                  style: TextButton.styleFrom(foregroundColor: Colors.blueGrey[700]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            isMobile
                ? Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildFilterDropdown('Category', _categoryFilter, ['All', 'General', 'Electrical', 'Plumbing', 'HVAC', 'Cleaning', 'Security', 'IT Support'], (value) {
                        setState(() => _categoryFilter = value!);
                      }, fontSize),
                      _buildFilterDropdown('Status', _statusFilter, ['All', 'Active', 'Inactive', 'Suspended'], (value) {
                        setState(() => _statusFilter = value!);
                      }, fontSize),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _buildFilterDropdown('Category', _categoryFilter, ['All', 'General', 'Electrical', 'Plumbing', 'HVAC', 'Cleaning', 'Security', 'IT Support'], (value) {
                          setState(() => _categoryFilter = value!);
                        }, fontSize),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFilterDropdown('Status', _statusFilter, ['All', 'Active', 'Inactive', 'Suspended'], (value) {
                          setState(() => _statusFilter = value!);
                        }, fontSize),
                      ),
                    ],
                  ),
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: GoogleFonts.poppins(fontSize: fontSize, color: Colors.grey[600]),
      ),
      style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.blueGrey[900], fontWeight: FontWeight.w500),
      dropdownColor: Colors.white,
      icon: const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
    );
  }

  Widget _buildVendorList({required double padding, required double fontSize}) {
    return StreamBuilder<QuerySnapshot>(
      stream: _buildVendorStream(),
      builder: (context, snapshot) {
        _logger.i('StreamBuilder snapshot: connectionState=${snapshot.connectionState}, hasError=${snapshot.hasError}, docCount=${snapshot.data?.docs.length ?? 0}');
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          _logger.e('Firestore error: ${snapshot.error}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                const SizedBox(height: 8),
                Text(
                  'Error loading vendors',
                  style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.red[600]),
                ),
                Text(
                  '${snapshot.error}',
                  style: GoogleFonts.poppins(fontSize: fontSize - 2, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.business_outlined, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text(
                  'No vendors found',
                  style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(padding),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final vendor = Vendor.fromSnapshot(docs[index]);
            return Card(
              elevation: 4.0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: _getStatusColor(vendor.status),
                  radius: 16,
                  child: Icon(
                    _getStatusIcon(vendor.status),
                    color: Colors.white,
                    size: fontSize + 2,
                  ),
                ),
                title: Text(
                  vendor.name,
                  style: GoogleFonts.poppins(
                    fontSize: fontSize + 2,
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
                        fontSize: fontSize - 2,
                        color: Colors.grey[600],
                      ),
                    ),
                    Row(
                      children: [
                        ...List.generate(5, (index) => Icon(
                              index < vendor.rating ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: fontSize,
                            )),
                        const SizedBox(width: 4),
                        Text(
                          '(${vendor.rating.toStringAsFixed(1)})',
                          style: GoogleFonts.poppins(
                            fontSize: fontSize - 2,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                children: [
                  Padding(
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailRow('Contact', vendor.contact, fontSize: fontSize),
                        if (vendor.email.isNotEmpty) _buildDetailRow('Email', vendor.email, fontSize: fontSize),
                        if (vendor.phone.isNotEmpty) _buildDetailRow('Phone', vendor.phone, fontSize: fontSize),
                        _buildDetailRow('Services', vendor.services, fontSize: fontSize),
                        if (vendor.contractDetails.isNotEmpty) _buildDetailRow('Contract', vendor.contractDetails, fontSize: fontSize),
                        _buildDetailRow('Created', vendor.createdAt != null ? DateFormat.yMMMd().format(vendor.createdAt!) : 'Unknown date', fontSize: fontSize),
                        if (vendor.serviceHistory.isNotEmpty) _buildHistorySection(vendor.serviceHistory, fontSize: fontSize, padding: padding),
                        const SizedBox(height: 12),
                        _buildActionButtons(vendor, fontSize: fontSize),
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
  }

  Stream<QuerySnapshot> _buildVendorStream() {
    Query query = FirebaseFirestore.instance
        .collection('Vendors')
        .where('facilityId', isEqualTo: widget.facilityId);

    if (_categoryFilter != 'All') {
      query = query.where('category', isEqualTo: _categoryFilter);
    }
    if (_statusFilter != 'All') {
      query = query.where('status', isEqualTo: _statusFilter);
    }

    return query.orderBy('createdAt', descending: true).snapshots();
  }

  Widget _buildDetailRow(String label, String value, {required double fontSize}) {
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
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                color: Colors.blueGrey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(List<Map<String, dynamic>> history, {required double fontSize, required double padding}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Service History:',
            style: GoogleFonts.poppins(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              color: Colors.blueGrey[700],
            ),
          ),
          const SizedBox(height: 4),
          ...history.take(3).map((entry) => Container(
                margin: EdgeInsets.only(bottom: padding / 2),
                padding: EdgeInsets.all(padding),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry['action'] ?? '',
                      style: GoogleFonts.poppins(fontSize: fontSize, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'at ${entry['timestamp'] != null ? DateFormat.yMMMd().format((entry['timestamp'] as Timestamp).toDate()) : 'Unknown date'}',
                      style: GoogleFonts.poppins(
                        fontSize: fontSize - 2,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (entry['notes'] != null && entry['notes'].isNotEmpty)
                      Text(
                        entry['notes'],
                        style: GoogleFonts.poppins(fontSize: fontSize - 1),
                      ),
                  ],
                ),
              )),
          if (history.length > 3)
            Text(
              '... and ${history.length - 3} more entries',
              style: GoogleFonts.poppins(
                fontSize: fontSize - 1,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(Vendor vendor, {required double fontSize}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: () => _showLogServiceDialog(vendor),
          icon: Icon(Icons.add_task, size: fontSize, color: Colors.blueGrey[700]),
          label: Text('Log Service', style: GoogleFonts.poppins(fontSize: fontSize)),
          style: TextButton.styleFrom(foregroundColor: Colors.blueGrey[700]),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => _showRatingDialog(vendor),
          icon: Icon(Icons.star, size: fontSize, color: Colors.amber[700]),
          label: Text('Rate', style: GoogleFonts.poppins(fontSize: fontSize)),
          style: TextButton.styleFrom(foregroundColor: Colors.amber[700]),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => _showStatusDialog(vendor),
          icon: Icon(Icons.edit, size: fontSize, color: Colors.blueGrey[700]),
          label: Text('Status', style: GoogleFonts.poppins(fontSize: fontSize)),
          style: TextButton.styleFrom(foregroundColor: Colors.blueGrey[700]),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Log Service', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey[900])),
        content: Card(
          elevation: 0,
          color: Colors.grey[50],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: serviceController,
                  decoration: InputDecoration(
                    labelText: 'Service Performed',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                    ),
                    labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
                  ),
                  style: GoogleFonts.poppins(),
                  validator: (value) => value!.isEmpty ? 'Enter service performed' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: notesController,
                  decoration: InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                    ),
                    labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
                  ),
                  style: GoogleFonts.poppins(),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.blueGrey[700])),
          ),
          ElevatedButton(
            onPressed: () {
              if (serviceController.text.isNotEmpty && mounted) {
                _addServiceHistory(vendor.id, serviceController.text, notesController.text);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey[900],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text('Rate Vendor', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey[900])),
          content: Card(
            elevation: 0,
            color: Colors.grey[50],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
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
                            size: 24,
                          ),
                        )),
                  ),
                  const SizedBox(height: 8),
                  Text('New Rating: ${newRating.toStringAsFixed(1)}', style: GoogleFonts.poppins()),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.blueGrey[700])),
            ),
            ElevatedButton(
              onPressed: () {
                if (mounted) {
                  _updateVendorRating(vendor.id, newRating);
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber[600],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Update Status', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey[900])),
        content: Card(
          elevation: 0,
          color: Colors.grey[50],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: DropdownButtonFormField<String>(
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                ),
                labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
              ),
              style: GoogleFonts.poppins(color: Colors.blueGrey[900], fontWeight: FontWeight.w500),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.blueGrey[700])),
          ),
          ElevatedButton(
            onPressed: () {
              if (mounted) {
                _updateVendorStatus(vendor.id, selectedStatus);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey[900],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Update', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildFormOverlay() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 768;
    final isTablet = screenWidth > 768 && screenWidth <= 1024;
    final padding = isMobile ? 8.0 : isTablet ? 12.0 : 16.0;
    final fontSize = isMobile ? 12.0 : isTablet ? 14.0 : 16.0;

    return GestureDetector(
      onTap: () => setState(() => _showForm = false),
      child: Container(
        color: Colors.black54,
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Prevent closing when tapping inside form
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Container(
                width: isMobile ? screenWidth * 0.9 : isTablet ? screenWidth * 0.7 : 600,
                padding: EdgeInsets.all(padding * 2),
                child: _buildVendorForm(padding: padding, fontSize: fontSize),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVendorForm({required double padding, required double fontSize}) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Add New Vendor',
                  style: GoogleFonts.poppins(
                    fontSize: fontSize + 4,
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
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Vendor Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                labelStyle: GoogleFonts.poppins(fontSize: fontSize, color: Colors.grey[600]),
              ),
              style: GoogleFonts.poppins(fontSize: fontSize),
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                      labelStyle: GoogleFonts.poppins(fontSize: fontSize, color: Colors.grey[600]),
                    ),
                    style: GoogleFonts.poppins(fontSize: fontSize),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value!.isNotEmpty && !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: 'Phone',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                      labelStyle: GoogleFonts.poppins(fontSize: fontSize, color: Colors.grey[600]),
                    ),
                    style: GoogleFonts.poppins(fontSize: fontSize),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value!.isNotEmpty && !RegExp(r'^\+?[\d\s-]{7,15}$').hasMatch(value)) {
                        return 'Enter a valid phone number';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _contactController,
              decoration: InputDecoration(
                labelText: 'Primary Contact Info',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                labelStyle: GoogleFonts.poppins(fontSize: fontSize, color: Colors.grey[600]),
              ),
              style: GoogleFonts.poppins(fontSize: fontSize),
              validator: (value) => value!.isEmpty ? 'Enter contact info' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _category,
              items: ['General', 'Electrical', 'Plumbing', 'HVAC', 'Cleaning', 'Security', 'IT Support']
                  .map((category) => DropdownMenuItem(
                        value: category,
                        child: Text(category, style: GoogleFonts.poppins(fontSize: fontSize)),
                      ))
                  .toList(),
              onChanged: (value) {
                if (mounted) setState(() => _category = value!);
              },
              decoration: InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                labelStyle: GoogleFonts.poppins(fontSize: fontSize, color: Colors.grey[600]),
              ),
              style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.blueGrey[900], fontWeight: FontWeight.w500),
              dropdownColor: Colors.white,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _serviceController,
              decoration: InputDecoration(
                labelText: 'Services Offered',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                labelStyle: GoogleFonts.poppins(fontSize: fontSize, color: Colors.grey[600]),
              ),
              style: GoogleFonts.poppins(fontSize: fontSize),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _contractController,
              decoration: InputDecoration(
                labelText: 'Contract Details (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                labelStyle: GoogleFonts.poppins(fontSize: fontSize, color: Colors.grey[600]),
              ),
              style: GoogleFonts.poppins(fontSize: fontSize),
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
                              child: Text(status, style: GoogleFonts.poppins(fontSize: fontSize)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (mounted) setState(() => _status = value!);
                    },
                    decoration: InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                      labelStyle: GoogleFonts.poppins(fontSize: fontSize, color: Colors.grey[600]),
                    ),
                    style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.blueGrey[900], fontWeight: FontWeight.w500),
                    dropdownColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Initial Rating', style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.blueGrey[700])),
                      const SizedBox(height: 8),
                      Row(
                        children: List.generate(5, (index) => GestureDetector(
                              onTap: () {
                                if (mounted) setState(() => _rating = index + 1.0);
                              },
                              child: Icon(
                                index < _rating ? Icons.star : Icons.star_border,
                                color: Colors.amber,
                                size: fontSize + 4,
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
                  backgroundColor: Colors.blueGrey[900],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  'Add Vendor',
                  style: GoogleFonts.poppins(
                    fontSize: fontSize,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green.shade600;
      case 'inactive':
        return Colors.grey.shade600;
      case 'suspended':
        return Colors.red.shade600;
      default:
        return Colors.grey.shade600;
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