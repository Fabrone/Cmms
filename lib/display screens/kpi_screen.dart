import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:rxdart/rxdart.dart';
import 'package:async/async.dart';

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
    if (_startDate != null && _endDate != null && _startDate!.isAfter(_endDate!)) {
      _logger.w('Invalid date range: startDate after endDate');
      _startDate = _endDate;
    }
  }

  void _initializeKpiStream() {
    final workOrderStream = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('work_orders')
        .snapshots();
    final requestStream = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('requests')
        .snapshots();
    final equipmentStream = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('equipment')
        .snapshots();
    final inventoryStream = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('inventory')
        .snapshots();
    final vendorStream = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('vendors')
        .snapshots();

    _kpiStream = StreamGroup.merge([
      workOrderStream,
      requestStream,
      equipmentStream,
      inventoryStream,
      vendorStream,
    ])
        .debounceTime(const Duration(milliseconds: 500))
        .asyncMap((_) => _calculateKpis())
        .handleError((e, stackTrace) {
      _logger.e('KPI stream error: $e', stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating KPIs: $e', style: GoogleFonts.poppins())),
        );
      }
    });
  }

  Future<Map<String, dynamic>> _calculateKpis() async {
    if (!mounted) return {};

    try {
      _logger.i('Calculating real-time KPIs for facility: ${widget.facilityId}');

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

      final equipment = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('equipment')
          .get();
      final totalEquipment = equipment.docs.length;
      final activeEquipment = equipment.docs.where((doc) => doc['status'] == 'Active').length;
      final underRepairEquipment = equipment.docs.where((doc) => doc['status'] == 'Under Repair').length;
      final inactiveEquipment = equipment.docs.where((doc) => doc['status'] == 'Inactive').length;

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

      final vendors = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('vendors')
          .get();
      final totalVendors = vendors.docs.length;
      final activeVendors = vendors.docs.where((doc) => doc['status'] == 'Active').length;
      final inactiveVendors = vendors.docs.where((doc) => doc['status'] == 'Inactive').length;
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

      final requestToWorkOrderConversion = totalRequests > 0 ? (totalWorkOrders / totalRequests * 100) : 0.0;
      final equipmentUtilization = totalEquipment > 0 ? (activeEquipment / totalEquipment * 100) : 0.0;
      final vendorUtilization = totalVendors > 0 ? (activeVendors / totalVendors * 100) : 0.0;

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
    } catch (e, stackTrace) {
      _logger.e('Error calculating KPIs: $e', stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error calculating KPIs: $e', style: GoogleFonts.poppins())),
        );
      }
      return {};
    }
  }

  void _clearFilter() {
    setState(() {
      _timeFilter = 'All Time';
      _setDateRange();
      _initializeKpiStream();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Real-time KPIs',
      facilityId: widget.facilityId,
      currentRole: 'Engineer',
      organization: '-',
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _initializeKpiStream()),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterSection(padding: padding, fontSizeTitle: fontSizeTitle, fontSize: fontSize),
          const SizedBox(height: 12),
          StreamBuilder<Map<String, dynamic>>(
            stream: _kpiStream,
            builder: (context, snapshot) {
              _logger.i('StreamBuilder snapshot: connectionState=${snapshot.connectionState}, hasError=${snapshot.hasError}');
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                _logger.e('KPI stream error: ${snapshot.error}');
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                      const SizedBox(height: 8),
                      Text(
                        'Error loading KPIs',
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

              final kpis = snapshot.data ?? {};
              if (kpis.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.analytics_outlined, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'No data available',
                        style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLiveIndicator(padding: padding, fontSize: fontSize),
                  const SizedBox(height: 12),
                  _buildLastUpdated(kpis['lastUpdated'], padding: padding, fontSize: fontSize),
                  const SizedBox(height: 12),
                  _buildSectionHeader('Work Orders', Icons.work_outline, fontSize: fontSize),
                  const SizedBox(height: 8),
                  _buildKpiGrid(
                    [
                      _buildKpiCard('Total Work Orders', '${kpis['totalWorkOrders'] ?? 0}', Icons.assignment, Colors.blue, fontSize: fontSize),
                      _buildKpiCard('Completion Rate', '${(kpis['completionRate'] ?? 0.0).toStringAsFixed(1)}%', Icons.check_circle, Colors.green, fontSize: fontSize),
                      _buildKpiCard('In Progress', '${kpis['inProgressWorkOrders'] ?? 0}', Icons.hourglass_empty, Colors.orange, fontSize: fontSize),
                      _buildKpiCard('Open Orders', '${kpis['openWorkOrders'] ?? 0}', Icons.radio_button_unchecked, Colors.red, fontSize: fontSize),
                    ],
                    isMobile: isMobile,
                    isTablet: isTablet,
                  ),
                  const SizedBox(height: 12),
                  _buildSectionHeader('Priority Distribution', Icons.priority_high, fontSize: fontSize),
                  const SizedBox(height: 8),
                  _buildKpiGrid(
                    [
                      _buildKpiCard('High Priority', '${kpis['highPriorityWorkOrders'] ?? 0}', Icons.warning, Colors.red, fontSize: fontSize),
                      _buildKpiCard('Medium Priority', '${kpis['mediumPriorityWorkOrders'] ?? 0}', Icons.info, Colors.orange, fontSize: fontSize),
                      _buildKpiCard('Low Priority', '${kpis['lowPriorityWorkOrders'] ?? 0}', Icons.low_priority, Colors.green, fontSize: fontSize),
                      _buildKpiCard('Avg Response Time', '${(kpis['averageResponseTime'] ?? 0.0).toStringAsFixed(1)}h', Icons.timer, Colors.indigo, fontSize: fontSize),
                    ],
                    isMobile: isMobile,
                    isTablet: isTablet,
                  ),
                  const SizedBox(height: 12),
                  _buildSectionHeader('Maintenance Requests', Icons.request_page, fontSize: fontSize),
                  const SizedBox(height: 8),
                  _buildKpiGrid(
                    [
                      _buildKpiCard('Total Requests', '${kpis['totalRequests'] ?? 0}', Icons.inbox, Colors.purple, fontSize: fontSize),
                      _buildKpiCard('Open Requests', '${kpis['openRequests'] ?? 0}', Icons.pending_actions, Colors.amber, fontSize: fontSize),
                      _buildKpiCard('In Progress', '${kpis['inProgressRequests'] ?? 0}', Icons.hourglass_empty, Colors.orange, fontSize: fontSize),
                      _buildKpiCard('Conversion Rate', '${(kpis['requestToWorkOrderConversion'] ?? 0.0).toStringAsFixed(1)}%', Icons.transform, Colors.teal, fontSize: fontSize),
                    ],
                    isMobile: isMobile,
                    isTablet: isTablet,
                  ),
                  const SizedBox(height: 12),
                  _buildSectionHeader('Equipment', Icons.precision_manufacturing, fontSize: fontSize),
                  const SizedBox(height: 8),
                  _buildKpiGrid(
                    [
                      _buildKpiCard('Total Equipment', '${kpis['totalEquipment'] ?? 0}', Icons.inventory, Colors.teal, fontSize: fontSize),
                      _buildKpiCard('Active Equipment', '${kpis['activeEquipment'] ?? 0}', Icons.check_circle, Colors.green, fontSize: fontSize),
                      _buildKpiCard('Under Repair', '${kpis['underRepairEquipment'] ?? 0}', Icons.build, Colors.orange, fontSize: fontSize),
                      _buildKpiCard('Utilization Rate', '${(kpis['equipmentUtilization'] ?? 0.0).toStringAsFixed(1)}%', Icons.trending_up, Colors.blue, fontSize: fontSize),
                    ],
                    isMobile: isMobile,
                    isTablet: isTablet,
                  ),
                  const SizedBox(height: 12),
                  _buildSectionHeader('Inventory', Icons.inventory_2, fontSize: fontSize),
                  const SizedBox(height: 8),
                  _buildKpiGrid(
                    [
                      _buildKpiCard('Total Items', '${kpis['totalInventoryItems'] ?? 0}', Icons.list_alt, Colors.cyan, fontSize: fontSize),
                      _buildKpiCard('In Stock', '${kpis['inStockItems'] ?? 0}', Icons.check_circle, Colors.green, fontSize: fontSize),
                      _buildKpiCard('Low Stock', '${kpis['lowStockItems'] ?? 0}', Icons.warning, Colors.orange, fontSize: fontSize),
                      _buildKpiCard('Out of Stock', '${kpis['outOfStockItems'] ?? 0}', Icons.remove_circle, Colors.red, fontSize: fontSize),
                    ],
                    isMobile: isMobile,
                    isTablet: isTablet,
                  ),
                  const SizedBox(height: 12),
                  _buildSectionHeader('Vendors', Icons.business, fontSize: fontSize),
                  const SizedBox(height: 8),
                  _buildKpiGrid(
                    [
                      _buildKpiCard('Total Vendors', '${kpis['totalVendors'] ?? 0}', Icons.groups, Colors.deepPurple, fontSize: fontSize),
                      _buildKpiCard('Active Vendors', '${kpis['activeVendors'] ?? 0}', Icons.verified, Colors.green, fontSize: fontSize),
                      _buildKpiCard('Avg Rating', '${(kpis['averageVendorRating'] ?? 0.0).toStringAsFixed(1)}★', Icons.star, Colors.amber, fontSize: fontSize),
                      _buildKpiCard('Utilization Rate', '${(kpis['vendorUtilization'] ?? 0.0).toStringAsFixed(1)}%', Icons.trending_up, Colors.blue, fontSize: fontSize),
                    ],
                    isMobile: isMobile,
                    isTablet: isTablet,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection({required double padding, required double fontSizeTitle, required double fontSize}) {
    final isMobile = MediaQuery.of(context).size.width <= 768;

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
                  'KPI Filters',
                  style: GoogleFonts.poppins(
                    fontSize: fontSizeTitle,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey[900],
                  ),
                ),
                TextButton.icon(
                  onPressed: _clearFilter,
                  icon: const Icon(Icons.clear, size: 16, color: Colors.blueGrey),
                  label: Text('Clear Filter', style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.blueGrey)),
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
                      _buildDropdown(fontSize: fontSize),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: _buildDropdown(fontSize: fontSize)),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({required double fontSize}) {
    return DropdownButtonFormField<String>(
      value: _timeFilter,
      items: ['All Time', 'Last 7 Days', 'Last 30 Days', 'Last 3 Months', 'This Year']
          .map((period) => DropdownMenuItem(
                value: period,
                child: Text(period, style: GoogleFonts.poppins(fontSize: fontSize)),
              ))
          .toList(),
      onChanged: (value) {
        if (mounted) {
          setState(() {
            _timeFilter = value!;
            _setDateRange();
            _initializeKpiStream();
          });
        }
      },
      decoration: InputDecoration(
        labelText: 'Time Period',
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

  Widget _buildLiveIndicator({required double padding, required double fontSize}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding / 2),
        color: Colors.green[50],
        child: Row(
          children: [
            const Icon(Icons.circle, color: Colors.green, size: 12),
            const SizedBox(width: 8),
            Text(
              'Live Data - Auto-updating',
              style: GoogleFonts.poppins(
                fontSize: fontSize,
                color: Colors.green[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastUpdated(String? lastUpdated, {required double padding, required double fontSize}) {
    if (lastUpdated == null) return const SizedBox.shrink();
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue),
        ),
        child: Row(
          children: [
            Icon(Icons.update, color: Colors.blue[700], size: 16),
            const SizedBox(width: 8),
            Text(
              'Last updated: ${DateTime.parse(lastUpdated).toLocal().toString().split('.')[0]}',
              style: GoogleFonts.poppins(
                fontSize: fontSize,
                color: Colors.blue[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, {required double fontSize}) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueGrey[800], size: fontSize + 4),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: fontSize + 2,
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey[900],
          ),
        ),
      ],
    );
  }

  Widget _buildKpiGrid(List<Widget> cards, {required bool isMobile, required bool isTablet}) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isMobile ? 2 : isTablet ? 3 : 4,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: isMobile ? 1.2 : 1.3,
      children: cards,
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color, {required double fontSize}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: fontSize + 8),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: fontSize + 4,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: fontSize - 2,
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