import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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
  final _serviceController = TextEditingController();
  final _contractController = TextEditingController();

  Future<void> _addVendor() async {
    if (_formKey.currentState!.validate()) {
      try {
        await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('vendors')
            .add({
          'name': _nameController.text,
          'contact': _contactController.text,
          'services': _serviceController.text,
          'contractDetails': _contractController.text,
          'history': [],
          'createdAt': Timestamp.now(),
        });
        _nameController.clear();
        _contactController.clear();
        _serviceController.clear();
        _contractController.clear();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vendor added')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _addServiceHistory(String docId, String service) async {
    try {
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('vendors')
          .doc(docId)
          .update({
        'history': FieldValue.arrayUnion([
          {
            'service': service,
            'timestamp': Timestamp.now(),
          }
        ]),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Service logged')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _serviceController.dispose();
    _contractController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vendors')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Add Vendor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Vendor Name'),
                        validator: (value) => value!.isEmpty ? 'Enter name' : null,
                      ),
                      TextFormField(
                        controller: _contactController,
                        decoration: const InputDecoration(labelText: 'Contact Info (e.g., email, phone)'),
                        validator: (value) => value!.isEmpty ? 'Enter contact' : null,
                      ),
                      TextFormField(
                        controller: _serviceController,
                        decoration: const InputDecoration(labelText: 'Services Offered'),
                      ),
                      TextFormField(
                        controller: _contractController,
                        decoration: const InputDecoration(labelText: 'Contract Details (optional)'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _addVendor,
                        child: const Text('Add Vendor'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('facilities')
                    .doc(widget.facilityId)
                    .collection('vendors')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) return const Center(child: Text('No vendors found'));
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final history = (doc['history'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
                      return Card(
                        child: ExpansionTile(
                          title: Text(doc['name']),
                          subtitle: Text('Contact: ${doc['contact']}'),
                          children: [
                            ListTile(
                              title: Text('Services: ${doc['services'] ?? 'N/A'}'),
                              subtitle: Text('Contract: ${doc['contractDetails'] ?? 'N/A'}'),
                            ),
                            ListTile(
                              title: const Text('Service History'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: history.isEmpty
                                    ? [const Text('No history')]
                                    : history.map((h) => Text(
                                          '${h['service']} at ${DateFormat.yMMMd().format((h['timestamp'] as Timestamp).toDate())}',
                                        )).toList(),
                              ),
                            ),
                            ListTile(
                              trailing: ElevatedButton(
                                onPressed: () => _addServiceHistory(doc.id, 'Service performed'),
                                child: const Text('Log Service'),
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
    );
  }
}