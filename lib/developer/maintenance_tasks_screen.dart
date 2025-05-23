import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/maintenance_task_model.dart';

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
  String? _selectedCategory;
  
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
      _selectedCategory = null;
    });
  }
  
  Future<void> _addTask() async {
    if (!_formKey.currentState!.validate()) return;
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('User not authenticated');
        return;
      }
      
      final category = _categoryController.text.trim();
      
      // Create a task model
      final task = MaintenanceTaskModel(
        component: _componentController.text.trim(),
        intervention: _interventionController.text.trim(),
        frequency: _frequencyController.text.trim(),
        createdBy: user.uid,
      );
      
      // Add the category as a document if it doesn't exist
      final categoryDoc = await _firestore.collection('Maintenance_Tasks').doc(category).get();
      
      if (!categoryDoc.exists) {
        await _firestore.collection('Maintenance_Tasks').doc(category).set({
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': user.uid,
          'tasks': []
        });
      }
      
      // Add the task to the category document
      await _firestore.collection('Maintenance_Tasks').doc(category).update({
        'tasks': FieldValue.arrayUnion([task.toMap()])
      });
      
      _showSnackBar('Maintenance task added successfully');
      _resetForm();
      
    } catch (e) {
      logger.e('Error adding task: $e');
      _showSnackBar('Error adding task: $e');
    }
  }
  
  Future<void> _updateTask(int taskIndex) async {
    if (!_formKey.currentState!.validate() || _selectedCategory == null) return;
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('User not authenticated');
        return;
      }
      
      // Get the current tasks array
      final docSnapshot = await _firestore.collection('Maintenance_Tasks').doc(_selectedCategory).get();
      if (!docSnapshot.exists) {
        _showSnackBar('Category document not found');
        return;
      }
      
      final categoryModel = CategoryModel.fromFirestore(docSnapshot);
      
      if (taskIndex >= categoryModel.tasks.length) {
        _showSnackBar('Task index out of bounds');
        return;
      }
      
      // Update the specific task
      final updatedTask = categoryModel.tasks[taskIndex].copyWith(
        component: _componentController.text.trim(),
        intervention: _interventionController.text.trim(),
        frequency: _frequencyController.text.trim(),
        updatedAt: DateTime.now(),
      );
      
      final updatedTasks = List<MaintenanceTaskModel>.from(categoryModel.tasks);
      updatedTasks[taskIndex] = updatedTask;
      
      // Update the document with the modified tasks array
      await _firestore.collection('Maintenance_Tasks').doc(_selectedCategory).update({
        'tasks': updatedTasks.map((task) => task.toMap()).toList()
      });
      
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
  
  Future<void> _deleteTask(String category, int taskIndex) async {
    try {
      // Get the current tasks array
      final docSnapshot = await _firestore.collection('Maintenance_Tasks').doc(category).get();
      if (!docSnapshot.exists) {
        _showSnackBar('Category document not found');
        return;
      }
      
      final tasks = List<Map<String, dynamic>>.from(docSnapshot.data()!['tasks'] ?? []);
      
      if (taskIndex >= tasks.length) {
        _showSnackBar('Task index out of bounds');
        return;
      }
      
      // Remove the task at the specified index
      tasks.removeAt(taskIndex);
      
      // Update the document with the modified tasks array
      await _firestore.collection('Maintenance_Tasks').doc(category).update({
        'tasks': tasks
      });
      
      // If no tasks remain, consider deleting the category document
      if (tasks.isEmpty) {
        if (!mounted) return;
        bool? confirmDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete Category', style: GoogleFonts.poppins()),
            content: Text(
              'No tasks remain in this category. Do you want to delete the category "$category"?',
              style: GoogleFonts.poppins(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Keep', style: GoogleFonts.poppins()),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Delete', style: GoogleFonts.poppins()),
              ),
            ],
          ),
        );
        
        if (confirmDelete == true) {
          await _firestore.collection('Maintenance_Tasks').doc(category).delete();
          _showSnackBar('Category "$category" deleted');
        }
      } else {
        _showSnackBar('Task deleted successfully');
      }
      
    } catch (e) {
      logger.e('Error deleting task: $e');
      _showSnackBar('Error deleting task: $e');
    }
  }
  
  Future<void> _deleteCategory(String category) async {
    try {
      if (!mounted) return;
      bool? confirmDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete Category', style: GoogleFonts.poppins()),
          content: Text(
            'Are you sure you want to delete the category "$category" and all its tasks?',
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
        await _firestore.collection('Maintenance_Tasks').doc(category).delete();
        _showSnackBar('Category "$category" deleted');
      }
      
    } catch (e) {
      logger.e('Error deleting category: $e');
      _showSnackBar('Error deleting category: $e');
    }
  }
  
  void _editTask(String category, Map<String, dynamic> task, int index) {
    setState(() {
      _viewMode = 'add';
      _selectedCategory = category;
      _selectedDocId = index.toString();
      _categoryController.text = category;
      _componentController.text = task['component'] ?? '';
      _interventionController.text = task['intervention'] ?? '';
      _frequencyController.text = task['frequency'] ?? '';
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
              enabled: _selectedDocId == null, // Disable when editing
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _componentController,
              decoration: InputDecoration(
                labelText: 'Component',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                labelStyle: GoogleFonts.poppins(),
              ),
              style: GoogleFonts.poppins(),
              validator: (value) => value!.isEmpty ? 'Component is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _interventionController,
              decoration: InputDecoration(
                labelText: 'Intervention',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                labelStyle: GoogleFonts.poppins(),
              ),
              style: GoogleFonts.poppins(),
              validator: (value) => value!.isEmpty ? 'Intervention is required' : null,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _frequencyController,
              decoration: InputDecoration(
                labelText: 'Frequency',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                labelStyle: GoogleFonts.poppins(),
              ),
              style: GoogleFonts.poppins(),
              validator: (value) => value!.isEmpty ? 'Frequency is required' : null,
            ),
            const SizedBox(height: 20),
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
                      _updateTask(int.parse(_selectedDocId!));
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
          ],
        ),
      ),
    );
  }
  
  Widget _buildEditView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('Maintenance_Tasks').snapshots(),
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
        
        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Maintenance Tasks',
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
                    DataColumn(label: Text('Frequency', style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Actions', style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                  ],
                  rows: _buildTableRows(docs),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  List<DataRow> _buildTableRows(List<QueryDocumentSnapshot> docs) {
    List<DataRow> rows = [];
    
    for (var doc in docs) {
      final categoryModel = CategoryModel.fromFirestore(doc);
      
      if (categoryModel.tasks.isEmpty) {
        rows.add(
          DataRow(
            cells: [
              DataCell(Text(categoryModel.id, style: GoogleFonts.poppins())),
              const DataCell(Text('-')),
              const DataCell(Text('-')),
              const DataCell(Text('-')),
              DataCell(
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteCategory(categoryModel.id),
                  tooltip: 'Delete Category',
                ),
              ),
            ],
          ),
        );
      } else {
        for (int i = 0; i < categoryModel.tasks.length; i++) {
          final task = categoryModel.tasks[i];
          rows.add(
            DataRow(
              cells: [
                DataCell(Text(categoryModel.id, style: GoogleFonts.poppins())),
                DataCell(Text(task.component, style: GoogleFonts.poppins())),
                DataCell(Text(task.intervention, style: GoogleFonts.poppins())),
                DataCell(Text(task.frequency, style: GoogleFonts.poppins())),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _editTask(categoryModel.id, task.toMap(), i),
                        tooltip: 'Edit Task',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteTask(categoryModel.id, i),
                        tooltip: 'Delete Task',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
      }
    }
    
    return rows;
  }
}
