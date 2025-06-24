import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'dart:async';

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
  bool _isLoading = false;
  Map<String, dynamic>? _lastGeneratedReport;
  StreamSubscription<QuerySnapshot>? _dataSubscription;
  List<QueryDocumentSnapshot> _currentData = [];
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _logger.i('ReportScreen initialized: facilityId=${widget.facilityId}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDataStream();
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }

  void _initializeDataStream() {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _lastError = null;
    });

    _dataSubscription?.cancel();
    
    try {
      final stream = _getDataStream();
      _dataSubscription = stream.listen(
        (QuerySnapshot snapshot) {
          if (mounted) {
            setState(() {
              _currentData = snapshot.docs;
              _isLoading = false;
              _lastError = null;
            });
            _generateDetailedReport(_currentData);
          }
        },
        onError: (error) {
          _logger.e('Stream error: $error');
          if (mounted) {
            setState(() {
              _isLoading = false;
              _lastError = error.toString();
            });
          }
        },
      );
    } catch (e) {
      _logger.e('Error initializing stream: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _lastError = e.toString();
        });
      }
    }
  }

  Stream<QuerySnapshot> _getDataStream() {
    String collection = _getCollectionName();
    
    // Use the correct subcollection path under facilities
    Query query;
    
    if (_reportType == 'Vendors') {
      // Vendors are at root level but need facilityId filter
      query = FirebaseFirestore.instance
          .collection('Vendors')
          .where('facilityId', isEqualTo: widget.facilityId)
          .limit(100);
    } else {
      // Other collections are under facilities subcollection
      query = FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection(collection)
          .limit(100);
    }

    // Apply filters one at a time to avoid complex composite queries
    if (_statusFilter != 'All') {
      query = query.where('status', isEqualTo: _statusFilter);
    }

    // For date filtering, use a simpler approach
    if (_startDate != null) {
      query = query.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate!));
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
        return 'Vendors'; // This will be handled differently in _getDataStream
      default:
        return 'work_orders';
    }
  }

  Future<void> _generateDetailedReport(List<QueryDocumentSnapshot> docs) async {
    if (!mounted || _isGenerating) return;

    setState(() => _isGenerating = true);

    try {
      await Future.delayed(const Duration(milliseconds: 100)); // Prevent UI blocking
      
      if (!mounted) return;

      _logger.i('Generating detailed report for ${docs.length} items');

      // Process data in smaller chunks to prevent memory issues
      final data = <Map<String, dynamic>>[];
      for (int i = 0; i < docs.length; i += 10) {
        final chunk = docs.skip(i).take(10);
        for (final doc in chunk) {
          try {
            final docData = doc.data() as Map<String, dynamic>?;
            if (docData != null) {
              data.add(docData);
            }
          } catch (e) {
            _logger.w('Error processing document ${doc.id}: $e');
          }
        }
        
        // Yield control back to UI thread
        if (i % 20 == 0) {
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }

      if (!mounted) return;

      // Apply additional filtering in memory for better performance
      final filteredData = data.where((item) {
        if (_priorityFilter != 'All' && item['priority'] != _priorityFilter) {
          return false;
        }
        if (_categoryFilter != 'All' && item['category'] != _categoryFilter) {
          return false;
        }
        if (_endDate != null) {
          final createdAt = (item['createdAt'] as Timestamp?)?.toDate();
          if (createdAt != null && createdAt.isAfter(_endDate!)) {
            return false;
          }
        }
        return true;
      }).toList();

      // Generate statistics
      final stats = await _generateStatistics(filteredData);
      
      if (!mounted) return;

      final report = {
        'reportType': _reportType,
        'facilityId': widget.facilityId,
        'generatedAt': DateTime.now().toIso8601String(),
        'totalItems': filteredData.length,
        'filters': {
          'status': _statusFilter,
          'priority': _priorityFilter,
          'category': _categoryFilter,
          'startDate': _startDate?.toIso8601String(),
          'endDate': _endDate?.toIso8601String(),
        },
        'summary': stats,
        'data': filteredData.take(50).toList(), // Limit displayed data
      };

      if (mounted) {
        setState(() {
          _lastGeneratedReport = report;
          _isGenerating = false;
        });
      }
    } catch (e, stackTrace) {
      _logger.e('Error generating report: $e', stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating report: $e', style: GoogleFonts.poppins()),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>> _generateStatistics(List<Map<String, dynamic>> data) async {
    final Map<String, int> statusCounts = {};
    final Map<String, int> priorityCounts = {};
    final Map<String, int> categoryCounts = {};
    final Map<String, int> monthlyCounts = {};
    double totalValue = 0;
    int totalQuantity = 0;

    for (final item in data) {
      // Status distribution
      final status = item['status'] as String? ?? 'Unknown';
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;

      // Priority distribution
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
        try {
          final createdAt = (item['createdAt'] as Timestamp?)?.toDate();
          if (createdAt != null) {
            final monthKey = DateFormat('yyyy-MM').format(createdAt);
            monthlyCounts[monthKey] = (monthlyCounts[monthKey] ?? 0) + 1;
          }
        } catch (e) {
          _logger.w('Error processing date for item: $e');
        }
      }

      // Value calculations
      if (item.containsKey('cost')) {
        try {
          final cost = (item['cost'] as num?)?.toDouble() ?? 0;
          final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
          totalValue += cost * quantity;
          totalQuantity += quantity;
        } catch (e) {
          _logger.w('Error processing cost for item: $e');
        }
      }
    }

    // Calculate trend
    final sortedMonths = monthlyCounts.keys.toList()..sort();
    double trend = 0;
    if (sortedMonths.length >= 2) {
      final recent = monthlyCounts[sortedMonths.last] ?? 0;
      final previous = monthlyCounts[sortedMonths[sortedMonths.length - 2]] ?? 0;
      trend = previous > 0 ? ((recent - previous) / previous * 100) : 0;
    }

    return {
      'statusDistribution': statusCounts,
      'priorityDistribution': priorityCounts,
      'categoryDistribution': categoryCounts,
      'monthlyDistribution': monthlyCounts,
      'totalValue': totalValue,
      'totalQuantity': totalQuantity,
      'trend': trend,
    };
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
    });
    _initializeDataStream();
  }

  void _refreshData() {
    _initializeDataStream();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Real-time Reports',
      facilityId: widget.facilityId,
      currentRole: 'Engineer',
      organization: '-',
      floatingActionButton: FloatingActionButton(
        onPressed: _refreshData,
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

    if (_lastError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              'Error loading data',
              style: GoogleFonts.poppins(
                fontSize: fontSizeTitle,
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _lastError!,
              style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh),
              label: Text('Retry', style: GoogleFonts.poppins()),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey[800],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        children: [
          _buildFilterSection(padding, fontSizeTitle: fontSizeTitle, fontSize: fontSize),
          const SizedBox(height: 12),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            _buildSummaryStatsSection(padding: padding, fontSize: fontSize),
            const SizedBox(height: 12),
            _buildDataList(fontSize: fontSize, padding: padding),
          ],
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
                        });
                        _initializeDataStream();
                      }, fontSize),
                      _buildDropdown('Status', _statusFilter, _getAvailableFilters(), (value) {
                        setState(() {
                          _statusFilter = value!;
                        });
                        _initializeDataStream();
                      }, fontSize),
                      if (_reportType == 'Work Orders' || _reportType == 'Requests')
                        _buildDropdown('Priority', _priorityFilter, ['All', 'High', 'Medium', 'Low'], (value) {
                          setState(() {
                            _priorityFilter = value!;
                          });
                          _initializeDataStream();
                        }, fontSize),
                      if (_reportType == 'Equipment' || _reportType == 'Inventory' || _reportType == 'Vendors')
                        _buildDropdown('Category', _categoryFilter, _getAvailableCategories(), (value) {
                          setState(() {
                            _categoryFilter = value!;
                          });
                          _initializeDataStream();
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
                              });
                              _initializeDataStream();
                            }, fontSize),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildDropdown('Status', _statusFilter, _getAvailableFilters(), (value) {
                              setState(() {
                                _statusFilter = value!;
                              });
                              _initializeDataStream();
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
                                });
                                _initializeDataStream();
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
                                });
                                _initializeDataStream();
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
          });
          _initializeDataStream();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLiveIndicator(_currentData.length, fontSize: fontSize, padding: padding),
        const SizedBox(height: 12),
        if (_lastGeneratedReport != null) _buildSummarySection(_lastGeneratedReport!, fontSize: fontSize, padding: padding),
      ],
    );
  }

  Widget _buildLiveIndicator(int itemCount, {required double fontSize, required double padding}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding / 2),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, color: Colors.green, size: 12),
          const SizedBox(width: 8),
          Text(
            'Live Data - $itemCount items found',
            style: GoogleFonts.poppins(
              fontSize: fontSize,
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
    if (_currentData.isEmpty) {
      return Center(
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
      );
    }

    // Limit the number of items displayed to prevent performance issues
    final displayData = _currentData.take(50).toList();

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: displayData.length,
      itemBuilder: (context, index) {
        try {
          final item = displayData[index].data() as Map<String, dynamic>?;
          if (item == null) return const SizedBox.shrink();
          
          return _buildDataCard(item, index, fontSize: fontSize, padding: padding);
        } catch (e) {
          _logger.w('Error building item at index $index: $e');
          return const SizedBox.shrink();
        }
      },
    );
  }

  Widget _buildDataCard(Map<String, dynamic> item, int index, {required double fontSize, required double padding}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.symmetric(vertical: padding / 4),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
