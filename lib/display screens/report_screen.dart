import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';

class ReportScreen extends StatefulWidget {
  final String facilityId;

  const ReportScreen({super.key, required this.facilityId});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final Logger _logger = Logger();
  String _reportType = 'Work Orders';
  String _statusFilter = 'All';
  String _priorityFilter = 'All';
  String _categoryFilter = 'All';
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isGenerating = false;
  Map<String, dynamic>? _lastGeneratedReport;
  late Stream<QuerySnapshot> _dataStream;

  @override
  void initState() {
    super.initState();
    _logger.i('ReportScreen initialized: facilityId=${widget.facilityId}');
    _initializeDataStream();
  }

  void _initializeDataStream() {
    // Initialize real-time data stream based on report type
    _dataStream = _getDataStream();
  }

  Stream<QuerySnapshot> _getDataStream() {
    String collection = _getCollectionName();
    Query query = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection(collection);

    // Apply filters
    if (_statusFilter != 'All') {
      query = query.where('status', isEqualTo: _statusFilter);
    }
    if (_priorityFilter != 'All' && (_reportType == 'Work Orders' || _reportType == 'Requests')) {
      query = query.where('priority', isEqualTo: _priorityFilter);
    }
    if (_categoryFilter != 'All' && (_reportType == 'Equipment' || _reportType == 'Inventory' || _reportType == 'Vendors')) {
      query = query.where('category', isEqualTo: _categoryFilter);
    }
    if (_startDate != null) {
      query = query.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate!));
    }
    if (_endDate != null) {
      query = query.where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(_endDate!));
    }

    return query.orderBy('createdAt', descending: true).snapshots();
  }

  String _getCollectionName() {
    switch (_reportType) {
      case 'Work Orders':
        return 'work_orders';
      case 'Requests':
        return 'requests';
      case 'Equipment':
        return 'equipment';
      case 'Inventory':
        return 'inventory';
      case 'Vendors':
        return 'vendors';
      default:
        return 'work_orders';
    }
  }

  Future<Map<String, dynamic>> _generateDetailedReport(List<QueryDocumentSnapshot> docs) async {
    setState(() => _isGenerating = true);
    
    try {
      _logger.i('Generating detailed report for ${docs.length} items');
      
      final data = docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
      
      // Calculate summary statistics
      Map<String, int> statusCounts = {};
      Map<String, int> priorityCounts = {};
      Map<String, int> categoryCounts = {};
      Map<String, int> monthlyCounts = {};
      
      double totalValue = 0;
      int totalQuantity = 0;
      
      for (var item in data) {
        // Status distribution
        final status = item['status'] as String? ?? 'Unknown';
        statusCounts[status] = (statusCounts[status] ?? 0) + 1;
        
        // Priority distribution (for work orders and requests)
        if (item.containsKey('priority')) {
          final priority = item['priority'] as String? ?? 'Unknown';
          priorityCounts[priority] = (priorityCounts[priority] ?? 0) + 1;
        }
        
        // Category distribution
        if (item.containsKey('category')) {
          final category = item['category'] as String? ?? 'Unknown';
          categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
        }
        
        // Monthly distribution
        if (item.containsKey('createdAt')) {
          final createdAt = (item['createdAt'] as Timestamp?)?.toDate();
          if (createdAt != null) {
            final monthKey = DateFormat('yyyy-MM').format(createdAt);
            monthlyCounts[monthKey] = (monthlyCounts[monthKey] ?? 0) + 1;
          }
        }
        
        // Value calculations (for inventory)
        if (item.containsKey('cost')) {
          final cost = (item['cost'] as num?)?.toDouble() ?? 0;
          final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
          totalValue += cost * quantity;
          totalQuantity += quantity;
        }
      }
      
      // Calculate trends
      final sortedMonths = monthlyCounts.keys.toList()..sort();
      double trend = 0;
      if (sortedMonths.length >= 2) {
        final recent = monthlyCounts[sortedMonths.last] ?? 0;
        final previous = monthlyCounts[sortedMonths[sortedMonths.length - 2]] ?? 0;
        trend = previous > 0 ? ((recent - previous) / previous * 100) : 0;
      }
      
      final report = {
        'reportType': _reportType,
        'facilityId': widget.facilityId,
        'generatedAt': DateTime.now().toIso8601String(),
        'totalItems': docs.length,
        'filters': {
          'status': _statusFilter,
          'priority': _priorityFilter,
          'category': _categoryFilter,
          'startDate': _startDate?.toIso8601String(),
          'endDate': _endDate?.toIso8601String(),
        },
        'summary': {
          'statusDistribution': statusCounts,
          'priorityDistribution': priorityCounts,
          'categoryDistribution': categoryCounts,
          'monthlyDistribution': monthlyCounts,
          'totalValue': totalValue,
          'totalQuantity': totalQuantity,
          'trend': trend,
        },
        'data': data,
      };
      
      setState(() {
        _lastGeneratedReport = report;
        _isGenerating = false;
      });
      
      return report;
    } catch (e) {
      _logger.e('Error generating report: $e');
      setState(() => _isGenerating = false);
      return {};
    }
  }

  List<String> _getAvailableFilters() {
    switch (_reportType) {
      case 'Work Orders':
        return ['All', 'Open', 'In Progress', 'Closed'];
      case 'Requests':
        return ['All', 'Open', 'In Progress', 'Closed'];
      case 'Equipment':
        return ['All', 'Active', 'Inactive', 'Under Repair'];
      case 'Inventory':
        return ['All', 'In Stock', 'Low Stock', 'Out of Stock'];
      case 'Vendors':
        return ['All', 'Active', 'Inactive', 'Suspended'];
      default:
        return ['All'];
    }
  }

  List<String> _getAvailableCategories() {
    switch (_reportType) {
      case 'Equipment':
        return ['All', 'HVAC', 'Electrical', 'Plumbing', 'Safety', 'General'];
      case 'Inventory':
        return ['All', 'Tools', 'Parts', 'Supplies', 'Safety Equipment'];
      case 'Vendors':
        return ['All', 'General', 'Electrical', 'Plumbing', 'HVAC', 'Cleaning', 'Security', 'IT Support'];
      default:
        return ['All'];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Real-time Reports',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.blueGrey[800],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              setState(() {
                _initializeDataStream();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Controls
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.grey[100],
            child: Column(
              children: [
                // Report Type and Status Filter Row
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _reportType,
                        items: ['Work Orders', 'Requests', 'Equipment', 'Inventory', 'Vendors']
                            .map((r) => DropdownMenuItem(
                                  value: r,
                                  child: Text(r, style: GoogleFonts.poppins()),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _reportType = value!;
                            _statusFilter = 'All';
                            _priorityFilter = 'All';
                            _categoryFilter = 'All';
                            _initializeDataStream();
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Report Type',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          filled: true,
                          fillColor: Colors.white,
                          labelStyle: GoogleFonts.poppins(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _statusFilter,
                        items: _getAvailableFilters()
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s, style: GoogleFonts.poppins()),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _statusFilter = value!;
                            _initializeDataStream();
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Status Filter',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          filled: true,
                          fillColor: Colors.white,
                          labelStyle: GoogleFonts.poppins(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Priority and Category Filter Row
                Row(
                  children: [
                    if (_reportType == 'Work Orders' || _reportType == 'Requests')
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _priorityFilter,
                          items: ['All', 'High', 'Medium', 'Low']
                              .map((p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(p, style: GoogleFonts.poppins()),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _priorityFilter = value!;
                              _initializeDataStream();
                            });
                          },
                          decoration: InputDecoration(
                            labelText: 'Priority Filter',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            filled: true,
                            fillColor: Colors.white,
                            labelStyle: GoogleFonts.poppins(),
                          ),
                        ),
                      ),
                    
                    if (_reportType == 'Equipment' || _reportType == 'Inventory' || _reportType == 'Vendors')
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _categoryFilter,
                          items: _getAvailableCategories()
                              .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c, style: GoogleFonts.poppins()),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _categoryFilter = value!;
                              _initializeDataStream();
                            });
                          },
                          decoration: InputDecoration(
                            labelText: 'Category Filter',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            filled: true,
                            fillColor: Colors.white,
                            labelStyle: GoogleFonts.poppins(),
                          ),
                        ),
                      ),
                    
                    if (_reportType != 'Work Orders' && _reportType != 'Requests' && 
                        _reportType != 'Equipment' && _reportType != 'Inventory' && _reportType != 'Vendors')
                      const Expanded(child: SizedBox()),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Date Range Row
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _startDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() {
                              _startDate = picked;
                              _initializeDataStream();
                            });
                          }
                        },
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          _startDate == null
                              ? 'Start Date'
                              : DateFormat.yMMMd().format(_startDate!),
                          style: GoogleFonts.poppins(),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.blueGrey[800],
                          side: BorderSide(color: Colors.blueGrey[300]!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _endDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() {
                              _endDate = picked;
                              _initializeDataStream();
                            });
                          }
                        },
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          _endDate == null
                              ? 'End Date'
                              : DateFormat.yMMMd().format(_endDate!),
                          style: GoogleFonts.poppins(),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.blueGrey[800],
                          side: BorderSide(color: Colors.blueGrey[300]!),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Real-time Data Display
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _dataStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: GoogleFonts.poppins(color: Colors.red),
                    ),
                  );
                }
                
                final docs = snapshot.data?.docs ?? [];
                
                // Auto-generate report when data changes
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!_isGenerating) {
                    _generateDetailedReport(docs);
                  }
                });
                
                return Column(
                  children: [
                    // Live indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: Colors.green[50],
                      child: Row(
                        children: [
                          const Icon(Icons.circle, color: Colors.green, size: 12),
                          const SizedBox(width: 8),
                          Text(
                            'Live Data - ${docs.length} items found',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          if (_isGenerating)
                            Row(
                              children: [
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.green[700],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Generating...',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.green[700],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    
                    // Report Summary
                    if (_lastGeneratedReport != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        color: Colors.blue[50],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Report Summary',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey[800],
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildSummaryStats(_lastGeneratedReport!),
                          ],
                        ),
                      ),
                    
                    // Data List
                    Expanded(
                      child: docs.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.description_outlined,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No data found for current filters',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: docs.length,
                              itemBuilder: (context, index) {
                                final item = docs[index].data() as Map<String, dynamic>;
                                return _buildDataCard(item, index);
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStats(Map<String, dynamic> report) {
    final summary = report['summary'] as Map<String, dynamic>;
    
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _buildStatChip('Total Items', '${report['totalItems']}', Colors.blue),
        if (summary['totalValue'] != null && summary['totalValue'] > 0)
          _buildStatChip('Total Value', '\$${summary['totalValue'].toStringAsFixed(2)}', Colors.green),
        if (summary['totalQuantity'] != null && summary['totalQuantity'] > 0)
          _buildStatChip('Total Quantity', '${summary['totalQuantity']}', Colors.orange),
        if (summary['trend'] != null)
          _buildStatChip(
            'Trend',
            '${summary['trend'] > 0 ? '+' : ''}${summary['trend'].toStringAsFixed(1)}%',
            summary['trend'] > 0 ? Colors.green : Colors.red,
          ),
      ],
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataCard(Map<String, dynamic> item, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(item['status'] ?? 'Unknown'),
          child: Text(
            '${index + 1}',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(
          item['title'] ?? item['name'] ?? 'Item ${index + 1}',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status: ${item['status'] ?? 'N/A'}',
              style: GoogleFonts.poppins(fontSize: 12),
            ),
            if (item['priority'] != null)
              Text(
                'Priority: ${item['priority']}',
                style: GoogleFonts.poppins(fontSize: 12),
              ),
            if (item['category'] != null)
              Text(
                'Category: ${item['category']}',
                style: GoogleFonts.poppins(fontSize: 12),
              ),
            Text(
              'Created: ${item['createdAt'] != null ? DateFormat.yMMMd().format((item['createdAt'] as Timestamp).toDate()) : 'N/A'}',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: Colors.grey[400],
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
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.grey;
      case 'under repair':
        return Colors.red;
      case 'low stock':
        return Colors.orange;
      case 'out of stock':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}