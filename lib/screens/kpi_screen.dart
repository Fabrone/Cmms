import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class KpiScreen extends StatefulWidget {
  final String facilityId;

  const KpiScreen({super.key, required this.facilityId});

  @override
  State<KpiScreen> createState() => _KpiScreenState();
}

class _KpiScreenState extends State<KpiScreen> {
  Future<Map<String, dynamic>> _calculateKpis() async {
    final workOrders = await FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('work_orders')
        .get();
    final total = workOrders.docs.length;
    final completed = workOrders.docs.where((doc) => doc['status'] == 'Closed').length;
    final completionRate = total > 0 ? (completed / total * 100).toStringAsFixed(1) : '0.0';
    final requests = await FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('requests')
        .get();
    final openRequests = requests.docs.where((doc) => doc['status'] == 'Open').length;
    return {
      'totalWorkOrders': total,
      'completionRate': completionRate,
      'openRequests': openRequests,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('KPIs')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _calculateKpis(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
            final kpis = snapshot.data ?? {
              'totalWorkOrders': 0,
              'completionRate': '0.0',
              'openRequests': 0
            };
            return Column(
              children: [
                Card(
                  child: ListTile(
                    title: const Text('Total Work Orders'),
                    subtitle: Text('${kpis['totalWorkOrders']}'),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text('Work Order Completion Rate'),
                    subtitle: Text('${kpis['completionRate']}%'),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text('Open Maintenance Requests'),
                    subtitle: Text('${kpis['openRequests']}'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}