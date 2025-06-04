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
  late Stream<Map<String, dynamic>> _kpiStream;

  @override
  void initState() {
    super.initState();
    _logger.i('KpiScreen initialized: facilityId=${widget.facilityId}');
    _setDateRange();
    _initializeKpiStream();
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

  void _initializeKpiStream() {
    // Create a stream that combines multiple collection streams for real-time updates
    _kpiStream = Stream.periodic(const Duration(seconds: 2), (i) => i)
        .asyncMap((_) => _calculateKpis());
  }

  Future<Map<String, dynamic>> _calculateKpis() async {
    try {
      _logger.i('Calculating real-time KPIs for facility: ${widget.facilityId}');
      
      // Work Orders KPIs with real-time data
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

      // Requests KPIs with real-time data
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
      final inProgressRequests = requests.docs.where((doc) => doc['status'] == 'In Progress').length;

      // Equipment KPIs with real-time data
      final equipment = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('equipment')
          .get();
      final totalEquipment = equipment.docs.length;
      final activeEquipment = equipment.docs.where((doc) => doc['status'] == 'Active').length;
      final underRepairEquipment = equipment.docs.where((doc) => doc['status'] == 'Under Repair').length;
      final inactiveEquipment = equipment.docs.where((doc) => doc['status'] == 'Inactive').length;

      // Inventory KPIs with real-time data
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
      final inStockItems = inventory.docs.where((doc) => (doc['quantity'] as int? ?? 0) > 0).length;

      // Vendor KPIs with real-time data
      final vendors = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('vendors')
          .get();
      final totalVendors = vendors.docs.length;
      final activeVendors = vendors.docs.where((doc) => doc['status'] == 'Active').length;
      final inactiveVendors = vendors.docs.where((doc) => doc['status'] == 'Inactive').length;
      
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

      // Calculate efficiency metrics
      final requestToWorkOrderConversion = totalRequests > 0 ? (totalWorkOrders / totalRequests * 100) : 0.0;
      final equipmentUtilization = totalEquipment > 0 ? (activeEquipment / totalEquipment * 100) : 0.0;
      final vendorUtilization = totalVendors > 0 ? (activeVendors / totalVendors * 100) : 0.0;

      // Calculate priority distribution
      final highPriorityWorkOrders = workOrders.docs.where((doc) => doc['priority'] == 'High').length;
      final mediumPriorityWorkOrders = workOrders.docs.where((doc) => doc['priority'] == 'Medium').length;
      final lowPriorityWorkOrders = workOrders.docs.where((doc) => doc['priority'] == 'Low').length;

      return {
        'totalWorkOrders': totalWorkOrders,
        'completedWorkOrders': completedWorkOrders,
        'inProgressWorkOrders': inProgressWorkOrders,
        'openWorkOrders': openWorkOrders,
        'completionRate': completionRate,
        'totalRequests': totalRequests,
        'openRequests': openRequests,
        'closedRequests': closedRequests,
        'inProgressRequests': inProgressRequests,
        'totalEquipment': totalEquipment,
        'activeEquipment': activeEquipment,
        'underRepairEquipment': underRepairEquipment,
        'inactiveEquipment': inactiveEquipment,
        'totalInventoryItems': totalInventoryItems,
        'lowStockItems': lowStockItems,
        'outOfStockItems': outOfStockItems,
        'inStockItems': inStockItems,
        'totalVendors': totalVendors,
        'activeVendors': activeVendors,
        'inactiveVendors': inactiveVendors,
        'averageVendorRating': averageVendorRating,
        'averageResponseTime': averageResponseTime,
        'requestToWorkOrderConversion': requestToWorkOrderConversion,
        'equipmentUtilization': equipmentUtilization,
        'vendorUtilization': vendorUtilization,
        'highPriorityWorkOrders': highPriorityWorkOrders,
        'mediumPriorityWorkOrders': mediumPriorityWorkOrders,
        'lowPriorityWorkOrders': lowPriorityWorkOrders,
        'lastUpdated': DateTime.now().toIso8601String(),
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
            'Real-time KPIs',
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
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () {
                setState(() {
                  _initializeKpiStream();
                });
              },
            ),
          ],
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
                            _initializeKpiStream();
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
              // Real-time indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.green[50],
                child: Row(
                  children: [
                    const Icon(Icons.circle, color: Colors.green, size: 12),
                    const SizedBox(width: 8),
                    Text(
                      'Live Data - Auto-updating every 2 seconds',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // KPI Dashboard
              Expanded(
                child: StreamBuilder<Map<String, dynamic>>(
                  stream: _kpiStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      _logger.e('KPI stream error: ${snapshot.error}');
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
                          // Last updated indicator
                          if (kpis['lastUpdated'] != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue[200]!),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.update, color: Colors.blue[700], size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Last updated: ${DateTime.parse(kpis['lastUpdated']).toLocal().toString().split('.')[0]}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.blue[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),

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

                          // Priority Distribution
                          _buildSectionHeader('Priority Distribution', Icons.priority_high),
                          const SizedBox(height: 12),
                          _buildKpiGrid([
                            _buildKpiCard(
                              'High Priority',
                              '${kpis['highPriorityWorkOrders'] ?? 0}',
                              Icons.warning,
                              Colors.red,
                            ),
                            _buildKpiCard(
                              'Medium Priority',
                              '${kpis['mediumPriorityWorkOrders'] ?? 0}',
                              Icons.info,
                              Colors.orange,
                            ),
                            _buildKpiCard(
                              'Low Priority',
                              '${kpis['lowPriorityWorkOrders'] ?? 0}',
                              Icons.low_priority,
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
                              'In Progress',
                              '${kpis['inProgressRequests'] ?? 0}',
                              Icons.hourglass_empty,
                              Colors.orange,
                            ),
                            _buildKpiCard(
                              'Conversion Rate',
                              '${(kpis['requestToWorkOrderConversion'] ?? 0.0).toStringAsFixed(1)}%',
                              Icons.transform,
                              Colors.teal,
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
                              'Utilization Rate',
                              '${(kpis['equipmentUtilization'] ?? 0.0).toStringAsFixed(1)}%',
                              Icons.trending_up,
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
                              'In Stock',
                              '${kpis['inStockItems'] ?? 0}',
                              Icons.check_circle,
                              Colors.green,
                            ),
                            _buildKpiCard(
                              'Low Stock',
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
                              'Utilization Rate',
                              '${(kpis['vendorUtilization'] ?? 0.0).toStringAsFixed(1)}%',
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