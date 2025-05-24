import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/maintenance_task_model.dart';
import 'package:cmms/developer/notification_setup_screen.dart';

class MaintenanceTasksScreen extends StatefulWidget {
  const MaintenanceTasksScreen({super.key});

  @override
  MaintenanceTasksScreenState createState() => MaintenanceTasksScreenState();
}

class MaintenanceTasksScreenState extends State<MaintenanceTasksScreen> {
  final logger = Logger(printer: PrettyPrinter());
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  
  // Form controllers
  final _categoryController = TextEditingController();
  final _componentController = TextEditingController();
  final _interventionController = TextEditingController();
  final _frequencyController = TextEditingController();
  
  // Form key for validation
  final _formKey = GlobalKey<FormState>();
  
  // View mode: 'add' or 'edit'
  String _viewMode = 'add';
  
  // Selected document for editing
  String? _selectedDocId;
  
  // Firestore reference
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  @override
  void dispose() {
    _categoryController.dispose();
    _componentController.dispose();
    _interventionController.dispose();
    _frequencyController.dispose();
    super.dispose();
  }
  
  void _resetForm() {
    _categoryController.clear();
    _componentController.clear();
    _interventionController.clear();
    _frequencyController.clear();
    setState(() {
      _selectedDocId = null;
    });
  }
  
  // Generate a unique document ID based on category and timestamp
  String _generateDocumentId(String category) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final cleanCategory = category.replaceAll(' ', '_').replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
    return '${cleanCategory}_$timestamp';
  }
  
  Future<void> _addTask() async {
    if (!_formKey.currentState!.validate()) return;
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('User not authenticated');
        return;
      }
      
      // Parse frequency as integer
      final frequency = int.tryParse(_frequencyController.text.trim());
      if (frequency == null || frequency <= 0) {
        _showSnackBar('Please enter a valid frequency in months');
        return;
      }
      
      final category = _categoryController.text.trim();
      
      // Create a task model
      final task = MaintenanceTaskModel(
        category: category,
        component: _componentController.text.trim(),
        intervention: _interventionController.text.trim(),
        frequency: frequency,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: user.uid,
      );
      
      // Generate a unique document ID based on category
      final docId = _generateDocumentId(category);
      
      // Add the task with the generated document ID
      await _firestore.collection('Maintenance_Tasks').doc(docId).set(task.toMap());
      
      _showSnackBar('Maintenance task added successfully');
      _resetForm();
      
      logger.i('Added task with ID: $docId for category: $category');
      
    } catch (e) {
      logger.e('Error adding task: $e');
      _showSnackBar('Error adding task: $e');
    }
  }
  
  Future<void> _updateTask() async {
    if (!_formKey.currentState!.validate() || _selectedDocId == null) return;
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('User not authenticated');
        return;
      }
      
      // Parse frequency as integer
      final frequency = int.tryParse(_frequencyController.text.trim());
      if (frequency == null || frequency <= 0) {
        _showSnackBar('Please enter a valid frequency in months');
        return;
      }
      
      // Get the current document to preserve createdAt and createdBy
      final docSnapshot = await _firestore.collection('Maintenance_Tasks').doc(_selectedDocId).get();
      if (!docSnapshot.exists) {
        _showSnackBar('Task document not found');
        return;
      }
      
      final currentTask = MaintenanceTaskModel.fromFirestore(docSnapshot);
      
      // Create updated task
      final updatedTask = currentTask.copyWith(
        category: _categoryController.text.trim(),
        component: _componentController.text.trim(),
        intervention: _interventionController.text.trim(),
        frequency: frequency,
        updatedAt: DateTime.now(),
      );
      
      // Update the document
      await _firestore.collection('Maintenance_Tasks').doc(_selectedDocId).update(updatedTask.toMap());
      
      _showSnackBar('Maintenance task updated successfully');
      setState(() {
        _viewMode = 'edit';
        _selectedDocId = null;
      });
      _resetForm();
      
    } catch (e) {
      logger.e('Error updating task: $e');
      _showSnackBar('Error updating task: $e');
    }
  }
  
  Future<void> _deleteTask(String docId, String category) async {
    try {
      if (!mounted) return;
      bool? confirmDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete Task', style: GoogleFonts.poppins()),
          content: Text(
            'Are you sure you want to delete this $category maintenance task?',
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete', style: GoogleFonts.poppins()),
            ),
          ],
        ),
      );
      
      if (confirmDelete == true) {
        await _firestore.collection('Maintenance_Tasks').doc(docId).delete();
        _showSnackBar('Task deleted successfully');
      }
      
    } catch (e) {
      logger.e('Error deleting task: $e');
      _showSnackBar('Error deleting task: $e');
    }
  }
  
  void _editTask(MaintenanceTaskModel task, String docId) {
    setState(() {
      _viewMode = 'add';
      _selectedDocId = docId;
      _categoryController.text = task.category;
      _componentController.text = task.component;
      _interventionController.text = task.intervention;
      _frequencyController.text = task.frequency.toString();
    });
  }
  
  void _showSnackBar(String message) {
    if (mounted) {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins())),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Maintenance Tasks Management',
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.blueGrey,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _viewMode = 'add';
                  _resetForm();
                });
              },
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text('Add', style: GoogleFonts.poppins(color: Colors.white)),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _viewMode = 'edit';
                  _resetForm();
                });
              },
              icon: const Icon(Icons.edit, color: Colors.white),
              label: Text('Edit', style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _viewMode == 'add' ? _buildAddForm() : _buildEditView(),
        ),
      ),
    );
  }
  
  Widget _buildAddForm() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectedDocId == null ? 'Add New Maintenance Task' : 'Edit Maintenance Task',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey[800],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _categoryController,
              decoration: InputDecoration(
                labelText: 'Category',
                hintText: 'e.g., Civil, Electrical, Water_Sanitation',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                labelStyle: GoogleFonts.poppins(),
              ),
              style: GoogleFonts.poppins(),
              validator: (value) => value!.isEmpty ? 'Category is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _componentController,
              decoration: InputDecoration(
                labelText: 'Component',
                hintText: 'Brief description of the component (max 10 words)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                labelStyle: GoogleFonts.poppins(),
              ),
              style: GoogleFonts.poppins(),
              validator: (value) {
                if (value!.isEmpty) return 'Component is required';
                final wordCount = value.trim().split(RegExp(r'\s+')).length;
                if (wordCount > 10) return 'Component should not exceed 10 words';
                return null;
              },
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _interventionController,
              decoration: InputDecoration(
                labelText: 'Intervention',
                hintText: 'Detailed description of the intervention required',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                labelStyle: GoogleFonts.poppins(),
              ),
              style: GoogleFonts.poppins(),
              validator: (value) => value!.isEmpty ? 'Intervention is required' : null,
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _frequencyController,
              decoration: InputDecoration(
                labelText: 'Frequency (months)',
                hintText: 'Enter number of months (e.g., 6, 12, 24)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                labelStyle: GoogleFonts.poppins(),
                suffixText: 'months',
              ),
              style: GoogleFonts.poppins(),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                if (value!.isEmpty) return 'Frequency is required';
                final frequency = int.tryParse(value);
                if (frequency == null || frequency <= 0) {
                  return 'Enter a valid number of months';
                }
                if (frequency > 120) {
                  return 'Frequency cannot exceed 120 months';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    _resetForm();
                    if (_selectedDocId != null) {
                      setState(() {
                        _viewMode = 'edit';
                      });
                    }
                  },
                  child: Text('Cancel', style: GoogleFonts.poppins()),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    if (_selectedDocId != null) {
                      _updateTask();
                    } else {
                      _addTask();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    _selectedDocId == null ? 'Save Task' : 'Update Task',
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
                ),
              ],
            ),
            
            // Setup Notification Button (only show when not editing)
            if (_selectedDocId == null) ...[
              const SizedBox(height: 16),
              Center(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    // Get the latest task ID to setup notification for
                    final latestTaskQuery = await _firestore
                        .collection('Maintenance_Tasks')
                        .orderBy('createdAt', descending: true)
                        .limit(1)
                        .get();
                    
                    if (latestTaskQuery.docs.isNotEmpty && mounted) {
                      final doc = latestTaskQuery.docs.first;
                      final task = MaintenanceTaskModel.fromFirestore(doc);
                      final taskId = doc.id;
                      
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NotificationSetupScreen(
                            task: task,
                            taskId: taskId,
                          ),
                        ),
                      );
                      
                      if (mounted && result == true) {
                        _resetForm();
                      }
                    } else {
                      _showSnackBar('Please save a task first before setting up notifications');
                    }
                  },
                  icon: const Icon(Icons.notifications_active),
                  label: Text('Setup Notification', style: GoogleFonts.poppins()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildEditView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('Maintenance_Tasks').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins()));
        }
        
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.engineering, size: 64, color: Colors.blueGrey[300]),
                const SizedBox(height: 16),
                Text(
                  'No maintenance tasks found',
                  style: GoogleFonts.poppins(fontSize: 18, color: Colors.blueGrey[600]),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _viewMode = 'add';
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Add Task', style: GoogleFonts.poppins(color: Colors.white)),
                ),
              ],
            ),
          );
        }
        
        // Group tasks by category for better display
        final Map<String, List<QueryDocumentSnapshot>> groupedTasks = {};
        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final category = data['category'] ?? 'Unknown';
          if (!groupedTasks.containsKey(category)) {
            groupedTasks[category] = [];
          }
          groupedTasks[category]!.add(doc);
        }
        
        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Maintenance Tasks (${docs.length} tasks in ${groupedTasks.length} categories)',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[800],
                ),
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text('Category', style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Component', style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Intervention', style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Frequency (months)', style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Actions', style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                  ],
                  rows: docs.map((doc) {
                    final task = MaintenanceTaskModel.fromFirestore(doc);
                    final docId = doc.id;
                    
                    return DataRow(
                      cells: [
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              task.category,
                              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            constraints: const BoxConstraints(maxWidth: 150),
                            child: Text(
                              task.component,
                              style: GoogleFonts.poppins(),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Text(
                              task.intervention,
                              style: GoogleFonts.poppins(),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 3,
                            ),
                          ),
                        ),
                        DataCell(Text('${task.frequency}', style: GoogleFonts.poppins())),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _editTask(task, docId),
                                tooltip: 'Edit Task',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteTask(docId, task.category),
                                tooltip: 'Delete Task',
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
