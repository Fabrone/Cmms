import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';

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
    _dataStream = _getDataStream();
  }

  Stream<QuerySnapshot> _getDataStream() {
    String collection = _getCollectionName();
    Query query = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection(collection);

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
    if (!mounted) return {};

    setState(() => _isGenerating = true);

    try {
      _logger.i('Generating detailed report for ${docs.length} items');

      final data = docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

      Map<String, int> statusCounts = {};
      Map<String, int> priorityCounts = {};
      Map<String, int> categoryCounts = {};
      Map<String, int> monthlyCounts = {};
      double totalValue = 0;
      int totalQuantity = 0;

      for (var item in data) {
        final status = item['status'] as String? ?? 'Unknown';
        statusCounts[status] = (statusCounts[status] ?? 0) + 1;

        if (item.containsKey('priority')) {
          final priority = item['priority'] as String? ?? 'Unknown';
          priorityCounts[priority] = (priorityCounts[priority] ?? 0) + 1;
        }

        if (item.containsKey('category')) {
          final category = item['category'] as String? ?? 'Unknown';
          categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
        }

        if (item.containsKey('createdAt')) {
          final createdAt = (item['createdAt'] as Timestamp?)?.toDate();
          if (createdAt != null) {
            final monthKey = DateFormat('yyyy-MM').format(createdAt);
            monthlyCounts[monthKey] = (monthlyCounts[monthKey] ?? 0) + 1;
          }
        }

        if (item.containsKey('cost')) {
          final cost = (item['cost'] as num?)?.toDouble() ?? 0;
          final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
          totalValue += cost * quantity;
          totalQuantity += quantity;
        }
      }

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

      if (mounted) {
        setState(() {
          _lastGeneratedReport = report;
          _isGenerating = false;
        });
      }

      return report;
    } catch (e, stackTrace) {
      _logger.e('Error generating report: $e', stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating report: $e', style: GoogleFonts.poppins())),
        );
      }
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

  void _clearFilters() {
    setState(() {
      _statusFilter = 'All';
      _priorityFilter = 'All';
      _categoryFilter = 'All';
      _startDate = null;
      _endDate = null;
      _initializeDataStream();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Real-time Reports',
      facilityId: widget.facilityId,
      currentRole: 'Engineer',
      organization: '-',
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _initializeDataStream()),
        backgroundColor: Colors.blueGrey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.refresh, color: Colors.white),
      ),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 768;
    final isTablet = screenWidth > 768 && screenWidth <= 1024;
    final padding = isMobile ? 8.0 : isTablet ? 12.0 : 16.0;
    final fontSizeTitle = isMobile ? 16.0 : isTablet ? 20.0 : 24.0;
    final fontSize = isMobile ? 12.0 : isTablet ? 14.0 : 16.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        children: [
          _buildFilterSection(padding, fontSizeTitle: fontSizeTitle, fontSize: fontSize),
          const SizedBox(height: 12),
          _buildSummaryStatsSection(padding: padding, fontSize: fontSize),
          const SizedBox(height: 12),
          _buildDataList(fontSize: fontSize, padding: padding),
        ],
      ),
    );
  }

  Widget _buildFilterSection(double padding, {required double fontSizeTitle, required double fontSize}) {
    final isMobile = MediaQuery.of(context).size.width <= 720;

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
                  'Report Filters',
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
                      _buildDropdown('Report Type', _reportType, ['Work Orders', 'Requests', 'Equipment', 'Inventory', 'Vendors'], (value) {
                        setState(() {
                          _reportType = value!;
                          _statusFilter = 'All';
                          _priorityFilter = 'All';
                          _categoryFilter = 'All';
                          _initializeDataStream();
                        });
                      }, fontSize),
                      _buildDropdown('Status', _statusFilter, _getAvailableFilters(), (value) {
                        setState(() {
                          _statusFilter = value!;
                          _initializeDataStream();
                        });
                      }, fontSize),
                      if (_reportType == 'Work Orders' || _reportType == 'Requests')
                        _buildDropdown('Priority', _priorityFilter, ['All', 'High', 'Medium', 'Low'], (value) {
                          setState(() {
                            _priorityFilter = value!;
                            _initializeDataStream();
                          });
                        }, fontSize),
                      if (_reportType == 'Equipment' || _reportType == 'Inventory' || _reportType == 'Vendors')
                        _buildDropdown('Category', _categoryFilter, _getAvailableCategories(), (value) {
                          setState(() {
                            _categoryFilter = value!;
                            _initializeDataStream();
                          });
                        }, fontSize),
                    ],
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdown('Report Type', _reportType, ['Work Orders', 'Requests', 'Equipment', 'Inventory', 'Vendors'], (value) {
                              setState(() {
                                _reportType = value!;
                                _statusFilter = 'All';
                                _priorityFilter = 'All';
                                _categoryFilter = 'All';
                                _initializeDataStream();
                              });
                            }, fontSize),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildDropdown('Status', _statusFilter, _getAvailableFilters(), (value) {
                              setState(() {
                                _statusFilter = value!;
                                _initializeDataStream();
                              });
                            }, fontSize),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (_reportType == 'Work Orders' || _reportType == 'Requests')
                            Expanded(
                              child: _buildDropdown('Priority', _priorityFilter, ['All', 'High', 'Medium', 'Low'], (value) {
                                setState(() {
                                  _priorityFilter = value!;
                                  _initializeDataStream();
                                });
                              }, fontSize),
                            )
                          else
                            const Expanded(child: SizedBox()),
                          const SizedBox(width: 12),
                          if (_reportType == 'Equipment' || _reportType == 'Inventory' || _reportType == 'Vendors')
                            Expanded(
                              child: _buildDropdown('Category', _categoryFilter, _getAvailableCategories(), (value) {
                                setState(() {
                                  _categoryFilter = value!;
                                  _initializeDataStream();
                                });
                              }, fontSize),
                            )
                          else
                            const Expanded(child: SizedBox()),
                        ],
                      ),
                    ],
                  ),
            const SizedBox(height: 12),
            isMobile
                ? Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildDateButton('Start Date', _startDate, fontSize, true),
                      _buildDateButton('End Date', _endDate, fontSize, false),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: _buildDateButton('Start Date', _startDate, fontSize, true)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildDateButton('End Date', _endDate, fontSize, false)),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged, double fontSize) {
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

  Widget _buildDateButton(String label, DateTime? date, double fontSize, bool isStart) {
    return ElevatedButton.icon(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null && mounted) {
          setState(() {
            if (isStart) {
              _startDate = picked;
              if (_endDate != null && picked.isAfter(_endDate!)) {
                _endDate = null;
              }
            } else {
              if (_startDate == null || !picked.isBefore(_startDate!)) {
                _endDate = picked;
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('End date must be after start date', style: GoogleFonts.poppins(fontSize: fontSize))),
                );
              }
            }
            _initializeDataStream();
          });
        }
      },
      icon: const Icon(Icons.calendar_today, size: 16, color: Colors.blueGrey),
      label: Text(
        date == null ? label : DateFormat.yMMMd().format(date),
        style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.blueGrey[900]),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[50],
        foregroundColor: Colors.blueGrey[900],
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: Colors.blueGrey),
      ),
    );
  }

  Widget _buildSummaryStatsSection({required double padding, required double fontSize}) {
    return StreamBuilder<QuerySnapshot>(
      stream: _dataStream,
      builder: (context, snapshot) {
        _logger.i('StreamBuilder snapshot: connectionState=${snapshot.connectionState}, hasError=${snapshot.hasError}, docCount=${snapshot.data?.docs.length ?? 0}');
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          _logger.e('Firestore error: ${snapshot.error}');
          return Text('Error: ${snapshot.error}', style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.red));
        }

        final docs = snapshot.data?.docs ?? [];
        if (!_isGenerating && mounted) {
          _generateDetailedReport(docs);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLiveIndicator(docs.length, fontSize: fontSize, padding: padding),
            const SizedBox(height: 12),
            if (_lastGeneratedReport != null) _buildSummarySection(_lastGeneratedReport!, fontSize: fontSize, padding: padding),
          ],
        );
      },
    );
  }

  Widget _buildLiveIndicator(int itemCount, {required double fontSize, required double padding}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding / 2),
      color: Colors.green[50],
      child: Row(
        children: [
          const Icon(Icons.circle, color: Colors.green, size: 12),
          const SizedBox(width: 8),
          Text(
            'Live Data - $itemCount items found',
            style: GoogleFonts.poppins(
              fontSize: fontSize,
              color: Colors.green[700],
              fontWeight: FontWeight.w500),
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
                    fontSize: fontSize,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSummarySection(Map<String, dynamic> report, {required double fontSize, required double padding}) {
    final summary = report['summary'] as Map<String, dynamic>;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Report Summary',
              style: GoogleFonts.poppins(
                fontSize: fontSize + 2,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey[900],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatChip('Total Items', '${report['totalItems']}', Colors.blue, fontSize: fontSize),
                if (summary['totalValue'] != null && summary['totalValue'] > 0)
                  _buildStatChip('Total Value', '\$${summary['totalValue'].toStringAsFixed(2)}', Colors.green, fontSize: fontSize),
                if (summary['totalQuantity'] != null && summary['totalQuantity'] > 0)
                  _buildStatChip('Total Quantity', '${summary['totalQuantity']}', Colors.orange, fontSize: fontSize),
                if (summary['totalQuantity'] != null && summary['totalQuantity'] > 0)
                  _buildStatChip('Total Quantity', '${summary['totalQuantity']}', Colors.orange, fontSize: fontSize),
                if (summary['trend'] != null)
                  _buildStatChip(
                    'Trend',
                    '${summary['trend'] > 0 ? '+' : ''}${summary['trend'].toStringAsFixed(1)}%',
                    summary['trend'] > 0 ? Colors.green : Colors.red,
                    fontSize: fontSize,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color, {required double fontSize}) {
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
              fontSize: fontSize,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: fontSize,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataList({required double fontSize, required double padding}) {
    return StreamBuilder<QuerySnapshot>(
      stream: _dataStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          _logger.e('Firestore error: ${snapshot.error}');
          return Text('Error: ${snapshot.error}', style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.red));
        }

        final docs = snapshot.data?.docs ?? [];

        return docs.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No data found for current filters',
                      style: GoogleFonts.poppins(
                        fontSize: fontSize,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final item = docs[index].data() as Map<String, dynamic>;
                  return _buildDataCard(item, index, fontSize: fontSize, padding: padding);
                },
              );
      },
    );
  }

  Widget _buildDataCard(Map<String, dynamic> item, int index, {required double fontSize, required double padding}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.symmetric(vertical: padding / 2),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: _getStatusColor(item['status'] ?? 'Unknown'),
              radius: 16,
              child: Text(
                '${index + 1}',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: fontSize - 2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'] ?? item['name'] ?? 'Item ${index + 1}',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: fontSize,
                      color: Colors.blueGrey[900],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Status: ${item['status'] ?? 'N/A'}',
                    style: GoogleFonts.poppins(fontSize: fontSize - 2, color: Colors.grey[600]),
                  ),
                  if (item['priority'] != null)
                    Text(
                      'Priority: ${item['priority']}',
                      style: GoogleFonts.poppins(fontSize: fontSize - 2, color: Colors.grey[600]),
                    ),
                  if (item['category'] != null)
                    Text(
                      'Category: ${item['category']}',
                      style: GoogleFonts.poppins(fontSize: fontSize - 2, color: Colors.grey[600]),
                    ),
                  Text(
                    'Created: ${item['createdAt'] != null ? DateFormat.yMMMd().format((item['createdAt'] as Timestamp).toDate()) : 'N/A'}',
                    style: GoogleFonts.poppins(fontSize: fontSize - 2, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Colors.blue.shade600;
      case 'in progress':
        return Colors.orange.shade600;
      case 'closed':
        return Colors.green.shade600;
      case 'active':
        return Colors.green.shade600;
      case 'inactive':
        return Colors.grey.shade600;
      case 'under repair':
        return Colors.red.shade600;
      case 'low stock':
        return Colors.orange.shade600;
      case 'out of stock':
        return Colors.red.shade600;
      default:
        return Colors.grey.shade600;
    }
  }
}