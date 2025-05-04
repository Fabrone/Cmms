import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ReportScreen extends StatefulWidget {
  final String facilityId;

  const ReportScreen({super.key, required this.facilityId});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _reportType = 'Work Orders';
  String _statusFilter = 'All';
  DateTime? _startDate;
  DateTime? _endDate;

  Future<Map<String, dynamic>> _generateReport() async {
    Query query = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection(_reportType.toLowerCase().replaceAll(' ', '_'));
    if (_statusFilter != 'All') {
      query = query.where('status', isEqualTo: _statusFilter);
    }
    if (_startDate != null) {
      query = query.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate!));
    }
    if (_endDate != null) {
      query = query.where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(_endDate!));
    }
    final snapshot = await query.get();
    return {
      'count': snapshot.docs.length,
      'data': snapshot.docs.map((doc) => doc.data()).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Generate Report', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    DropdownButtonFormField<String>(
                      value: _reportType,
                      items: ['Work Orders', 'Requests', 'Assets', 'Inventory']
                          .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                          .toList(),
                      onChanged: (value) => setState(() => _reportType = value!),
                      decoration: const InputDecoration(labelText: 'Report Type'),
                    ),
                    DropdownButtonFormField<String>(
                      value: _statusFilter,
                      items: ['All', 'Open', 'In Progress', 'Closed']
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (value) => setState(() => _statusFilter = value!),
                      decoration: const InputDecoration(labelText: 'Status Filter'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) setState(() => _startDate = picked);
                            },
                            child: Text(_startDate == null
                                ? 'Select Start Date'
                                : DateFormat.yMMMd().format(_startDate!)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) setState(() => _endDate = picked);
                            },
                            child: Text(_endDate == null
                                ? 'Select End Date'
                                : DateFormat.yMMMd().format(_endDate!)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _generateReport(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                  final report = snapshot.data ?? {'count': 0, 'data': []};
                  return Column(
                    children: [
                      Text('$_reportType Report: ${report['count']} items'),
                      Expanded(
                        child: ListView.builder(
                          itemCount: report['data'].length,
                          itemBuilder: (context, index) {
                            final item = report['data'][index];
                            return Card(
                              child: ListTile(
                                title: Text(item['name'] ?? item['title'] ?? 'Item ${index + 1}'),
                                subtitle: Text(
                                  'Status: ${item['status'] ?? 'N/A'}\n'
                                  'Created: ${item['createdAt'] != null ? DateFormat.yMMMd().format((item['createdAt'] as Timestamp).toDate()) : 'N/A'}',
                                ),
                              ),
                            );
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
      ),
    );
  }
}