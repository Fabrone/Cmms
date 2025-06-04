import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';

class KpiScreen extends StatefulWidget {
  final String facilityId;

  const KpiScreen({super.key, required this.facilityId});

  @override
  State<KpiScreen> createState() => _KpiScreenState();
}

class _KpiScreenState extends State<KpiScreen> {
  final Logger _logger = Logger();
  String _timeFilter = 'All Time';
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _logger.i('KpiScreen initialized: facilityId=${widget.facilityId}');
    _setDateRange();
  }

  void _setDateRange() {
    final now = DateTime.now();
    switch (_timeFilter) {
      case 'Last 7 Days':
        _startDate = now.subtract(const Duration(days: 7));
        _endDate = now;
        break;
      case 'Last 30 Days':
        _startDate = now.subtract(const Duration(days: 30));
        _endDate = now;
        break;
      case 'Last 3 Months':
        _startDate = DateTime(now.year, now.month - 3, now.day);
        _endDate = now;
        break;
      case 'This Year':
        _startDate = DateTime(now.year, 1, 1);
        _endDate = now;
        break;
      default:
        _startDate = null;
        _endDate = null;
    }
  }

  Future<Map<String, dynamic>> _calculateKpis() async {
    try {
      _logger.i('Calculating KPIs for facility: ${widget.facilityId}');
      
      // Work Orders KPIs
      Query workOrderQuery = FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('work_orders');
      
      if (_startDate != null && _endDate != null) {
        workOrderQuery = workOrderQuery
            .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate!))
            .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(_endDate!));
      }
      
      final workOrders = await workOrderQuery.get();
      final totalWorkOrders = workOrders.docs.length;
      final completedWorkOrders = workOrders.docs.where((doc) => doc['status'] == 'Closed').length;
      final inProgressWorkOrders = workOrders.docs.where((doc) => doc['status'] == 'In Progress').length;
      final openWorkOrders = workOrders.docs.where((doc) => doc['status'] == 'Open').length;
      final completionRate = totalWorkOrders > 0 ? (completedWorkOrders / totalWorkOrders * 100) : 0.0;

      // Requests KPIs
      Query requestQuery = FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('requests');
      
      if (_startDate != null && _endDate != null) {
        requestQuery = requestQuery
            .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate!))
            .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(_endDate!));
      }
      
      final requests = await requestQuery.get();
      final totalRequests = requests.docs.length;
      final openRequests = requests.docs.where((doc) => doc['status'] == 'Open').length;
      final closedRequests = requests.docs.where((doc) => doc['status'] == 'Closed').length;

      // Equipment KPIs
      final equipment = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('equipment')
          .get();
      final totalEquipment = equipment.docs.length;
      final activeEquipment = equipment.docs.where((doc) => doc['status'] == 'Active').length;
      final underRepairEquipment = equipment.docs.where((doc) => doc['status'] == 'Under Repair').length;

      // Inventory KPIs
      final inventory = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('inventory')
          .get();
      final totalInventoryItems = inventory.docs.length;
      final lowStockItems = inventory.docs.where((doc) {
        final quantity = doc['quantity'] as int? ?? 0;
        final reorderPoint = doc['reorderPoint'] as int? ?? 0;
        return quantity <= reorderPoint && quantity > 0;
      }).length;
      final outOfStockItems = inventory.docs.where((doc) => (doc['quantity'] as int? ?? 0) == 0).length;

      // Vendor KPIs
      final vendors = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('vendors')
          .get();
      final totalVendors = vendors.docs.length;
      final activeVendors = vendors.docs.where((doc) => doc['status'] == 'Active').length;
      
      // Calculate average vendor rating
      double totalRating = 0;
      int ratedVendors = 0;
      for (var doc in vendors.docs) {
        final rating = doc['rating'] as double? ?? 0.0;
        if (rating > 0) {
          totalRating += rating;
          ratedVendors++;
        }
      }
      final averageVendorRating = ratedVendors > 0 ? totalRating / ratedVendors : 0.0;

      // Response Time Analysis (for work orders)
      double totalResponseTime = 0;
      int workOrdersWithResponseTime = 0;
      for (var doc in workOrders.docs) {
        final createdAt = (doc['createdAt'] as Timestamp?)?.toDate();
        final history = doc['history'] as List<dynamic>? ?? [];
        if (createdAt != null && history.isNotEmpty) {
          final firstResponse = history.first['timestamp'] as Timestamp?;
          if (firstResponse != null) {
            final responseTime = firstResponse.toDate().difference(createdAt).inHours;
            totalResponseTime += responseTime;
            workOrdersWithResponseTime++;
          }
        }
      }
      final averageResponseTime = workOrdersWithResponseTime > 0 ? totalResponseTime / workOrdersWithResponseTime : 0.0;

      return {
        'totalWorkOrders': totalWorkOrders,
        'completedWorkOrders': completedWorkOrders,
        'inProgressWorkOrders': inProgressWorkOrders,
        'openWorkOrders': openWorkOrders,
        'completionRate': completionRate,
        'totalRequests': totalRequests,
        'openRequests': openRequests,
        'closedRequests': closedRequests,
        'totalEquipment': totalEquipment,
        'activeEquipment': activeEquipment,
        'underRepairEquipment': underRepairEquipment,
        'totalInventoryItems': totalInventoryItems,
        'lowStockItems': lowStockItems,
        'outOfStockItems': outOfStockItems,
        'totalVendors': totalVendors,
        'activeVendors': activeVendors,
        'averageVendorRating': averageVendorRating,
        'averageResponseTime': averageResponseTime,
      };
    } catch (e) {
      _logger.e('Error calculating KPIs: $e');
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    final fontSizeTitle = isMobile ? 20.0 : 24.0;

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Key Performance Indicators',
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
                    Text(
                      'Time Period:',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w500,
                        color: Colors.blueGrey[800],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _timeFilter,
                        items: ['All Time', 'Last 7 Days', 'Last 30 Days', 'Last 3 Months', 'This Year']
                            .map((period) => DropdownMenuItem(
                                  value: period,
                                  child: Text(period, style: GoogleFonts.poppins(color: Colors.blueGrey[800])),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _timeFilter = value!;
                            _setDateRange();
                          });
                        },
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
              // KPI Dashboard
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: _calculateKpis(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      _logger.e('KPI calculation error: ${snapshot.error}');
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                            const SizedBox(height: 16),
                            Text(
                              'Error loading KPIs',
                              style: GoogleFonts.poppins(fontSize: 18, color: Colors.red[600]),
                            ),
                            Text(
                              '${snapshot.error}',
                              style: GoogleFonts.poppins(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      );
                    }
                    
                    final kpis = snapshot.data ?? {};
                    if (kpis.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.analytics_outlined, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No data available',
                              style: GoogleFonts.poppins(fontSize: 18, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Work Orders Section
                          _buildSectionHeader('Work Orders', Icons.work_outline),
                          const SizedBox(height: 12),
                          _buildKpiGrid([
                            _buildKpiCard(
                              'Total Work Orders',
                              '${kpis['totalWorkOrders'] ?? 0}',
                              Icons.assignment,
                              Colors.blue,
                            ),
                            _buildKpiCard(
                              'Completion Rate',
                              '${(kpis['completionRate'] ?? 0.0).toStringAsFixed(1)}%',
                              Icons.check_circle,
                              Colors.green,
                            ),
                            _buildKpiCard(
                              'In Progress',
                              '${kpis['inProgressWorkOrders'] ?? 0}',
                              Icons.hourglass_empty,
                              Colors.orange,
                            ),
                            _buildKpiCard(
                              'Open Orders',
                              '${kpis['openWorkOrders'] ?? 0}',
                              Icons.radio_button_unchecked,
                              Colors.red,
                            ),
                          ]),
                          const SizedBox(height: 24),

                          // Requests Section
                          _buildSectionHeader('Maintenance Requests', Icons.request_page),
                          const SizedBox(height: 12),
                          _buildKpiGrid([
                            _buildKpiCard(
                              'Total Requests',
                              '${kpis['totalRequests'] ?? 0}',
                              Icons.inbox,
                              Colors.purple,
                            ),
                            _buildKpiCard(
                              'Open Requests',
                              '${kpis['openRequests'] ?? 0}',
                              Icons.pending_actions,
                              Colors.amber,
                            ),
                            _buildKpiCard(
                              'Closed Requests',
                              '${kpis['closedRequests'] ?? 0}',
                              Icons.done_all,
                              Colors.green,
                            ),
                            _buildKpiCard(
                              'Avg Response Time',
                              '${(kpis['averageResponseTime'] ?? 0.0).toStringAsFixed(1)}h',
                              Icons.timer,
                              Colors.indigo,
                            ),
                          ]),
                          const SizedBox(height: 24),

                          // Equipment Section
                          _buildSectionHeader('Equipment', Icons.precision_manufacturing),
                          const SizedBox(height: 12),
                          _buildKpiGrid([
                            _buildKpiCard(
                              'Total Equipment',
                              '${kpis['totalEquipment'] ?? 0}',
                              Icons.inventory,
                              Colors.teal,
                            ),
                            _buildKpiCard(
                              'Active Equipment',
                              '${kpis['activeEquipment'] ?? 0}',
                              Icons.check_circle,
                              Colors.green,
                            ),
                            _buildKpiCard(
                              'Under Repair',
                              '${kpis['underRepairEquipment'] ?? 0}',
                              Icons.build,
                              Colors.orange,
                            ),
                            _buildKpiCard(
                              'Equipment Health',
                              '${kpis['totalEquipment'] > 0 ? ((kpis['activeEquipment'] / kpis['totalEquipment']) * 100).toStringAsFixed(1) : 0}%',
                              Icons.health_and_safety,
                              Colors.blue,
                            ),
                          ]),
                          const SizedBox(height: 24),

                          // Inventory Section
                          _buildSectionHeader('Inventory', Icons.inventory_2),
                          const SizedBox(height: 12),
                          _buildKpiGrid([
                            _buildKpiCard(
                              'Total Items',
                              '${kpis['totalInventoryItems'] ?? 0}',
                              Icons.list_alt,
                              Colors.cyan,
                            ),
                            _buildKpiCard(
                              'Low Stock Items',
                              '${kpis['lowStockItems'] ?? 0}',
                              Icons.warning,
                              Colors.orange,
                            ),
                            _buildKpiCard(
                              'Out of Stock',
                              '${kpis['outOfStockItems'] ?? 0}',
                              Icons.remove_circle,
                              Colors.red,
                            ),
                            _buildKpiCard(
                              'Stock Health',
                              '${kpis['totalInventoryItems'] > 0 ? (((kpis['totalInventoryItems'] - kpis['outOfStockItems']) / kpis['totalInventoryItems']) * 100).toStringAsFixed(1) : 0}%',
                              Icons.trending_up,
                              Colors.green,
                            ),
                          ]),
                          const SizedBox(height: 24),

                          // Vendors Section
                          _buildSectionHeader('Vendors', Icons.business),
                          const SizedBox(height: 12),
                          _buildKpiGrid([
                            _buildKpiCard(
                              'Total Vendors',
                              '${kpis['totalVendors'] ?? 0}',
                              Icons.groups,
                              Colors.deepPurple,
                            ),
                            _buildKpiCard(
                              'Active Vendors',
                              '${kpis['activeVendors'] ?? 0}',
                              Icons.verified,
                              Colors.green,
                            ),
                            _buildKpiCard(
                              'Avg Rating',
                              '${(kpis['averageVendorRating'] ?? 0.0).toStringAsFixed(1)}★',
                              Icons.star,
                              Colors.amber,
                            ),
                            _buildKpiCard(
                              'Vendor Utilization',
                              '${kpis['totalVendors'] > 0 ? ((kpis['activeVendors'] / kpis['totalVendors']) * 100).toStringAsFixed(1) : 0}%',
                              Icons.trending_up,
                              Colors.blue,
                            ),
                          ]),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueGrey[800], size: 24),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey[900],
          ),
        ),
      ],
    );
  }

  Widget _buildKpiGrid(List<Widget> cards) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.2,
      children: cards,
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.1),
              color.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.blueGrey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}