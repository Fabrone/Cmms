import 'package:cmms/developer/collection_detail_screen.dart';
import 'package:cmms/developer/maintenance_tasks_screen.dart';
import 'package:cmms/notifications/screens/system_notifications_screen.dart';
import 'package:flutter/material.dart';

class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({super.key});

  @override
  DeveloperScreenState createState() => DeveloperScreenState();
}

class DeveloperScreenState extends State<DeveloperScreen> {
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth > 800 ? screenWidth * 0.6 : screenWidth * 0.9;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Developer Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blueGrey,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: BoxConstraints(maxWidth: contentWidth),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Firestore Collections',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  
                  // Organizations management 
                  ListTile(
                    leading: const Icon(Icons.business, color: Colors.blueGrey),
                    title: const Text('Organizations'),
                    subtitle: const Text('Manage system organizations'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CollectionDetailScreen(
                          collectionName: 'Organizations',
                          fields: ['name', 'description', 'createdAt', 'isActive'],
                          hasActions: true,
                        ),
                      ),
                    ),
                  ),
                  
                  const Divider(),
                  
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings, color: Colors.blueGrey),
                    title: const Text('Admins'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CollectionDetailScreen(
                          collectionName: 'Admins',
                          fields: ['username', 'email', 'organization', 'createdAt', 'isDisabled'],
                          hasActions: true,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.group, color: Colors.blueGrey),
                    title: const Text('Users'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CollectionDetailScreen(
                          collectionName: 'Users',
                          fields: ['username', 'email', 'role', 'organization', 'createdAt'],
                          hasActions: true,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.build, color: Colors.blueGrey),
                    title: const Text('Technicians'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CollectionDetailScreen(
                          collectionName: 'Technicians',
                          fields: ['username', 'email', 'organization', 'createdAt', 'isDisabled'],
                          hasActions: true,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.history, color: Colors.blueGrey),
                    title: const Text('Admin Actions'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CollectionDetailScreen(
                          collectionName: 'admin_logs',
                          fields: ['action', 'timestamp', 'performedBy'],
                          hasActions: true,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.developer_mode, color: Colors.blueGrey),
                    title: const Text('Developers'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CollectionDetailScreen(
                          collectionName: 'Developers',
                          fields: ['username', 'email', 'organization', 'createdAt'],
                          hasActions: true,
                        ),
                      ),
                    ),
                  ),
                  
                  const Divider(),
                  
                  ListTile(
                    leading: const Icon(Icons.build, color: Colors.blueGrey),
                    title: const Text('Update M-Tasks'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MaintenanceTasksScreen(),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_active, color: Colors.blueGrey),
                    title: const Text('System Notifications'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SystemNotificationsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}