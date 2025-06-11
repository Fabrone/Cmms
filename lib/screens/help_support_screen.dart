import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  
  String _selectedCategory = 'General';
  final List<String> _categories = [
    'General',
    'Technical Issue',
    'Feature Request',
    'Account Problem',
    'Maintenance Tasks',
    'Notifications',
    'Maps & Locations',
    'Other'
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Help & Support',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.blueGrey,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Quick Help Section
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.help_outline, color: Colors.blueGrey[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Quick Help',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey[800],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  _buildQuickHelpItem(
                    Icons.assignment,
                    'How to create maintenance tasks?',
                    'Navigate to Maintenance > Add Task to create new maintenance schedules.',
                  ),
                  
                  _buildQuickHelpItem(
                    Icons.notifications,
                    'Setting up notifications',
                    'Go to Maintenance > Setup Notification to configure automated reminders.',
                  ),
                  
                  _buildQuickHelpItem(
                    Icons.map,
                    'Using the map feature',
                    'Click on any facility in Locations to view it on the map or get directions.',
                  ),
                  
                  _buildQuickHelpItem(
                    Icons.person,
                    'Managing your profile',
                    'Access Profile from the menu to update your personal information.',
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // FAQ Section
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.quiz, color: Colors.blueGrey[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Frequently Asked Questions',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey[800],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  _buildFAQItem(
                    'How do I reset my password?',
                    'Contact your system administrator or use the password reset option on the login screen.',
                  ),
                  
                  _buildFAQItem(
                    'Can I access the system offline?',
                    'The app requires an internet connection for real-time data synchronization and updates.',
                  ),
                  
                  _buildFAQItem(
                    'How are maintenance notifications scheduled?',
                    'Notifications are automatically calculated based on the last inspection date and maintenance frequency.',
                  ),
                  
                  _buildFAQItem(
                    'Who can see my maintenance tasks?',
                    'Tasks are visible to assigned technicians and administrators based on your organization\'s access controls.',
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Contact Support Section
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.support_agent, color: Colors.blueGrey[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Contact Support',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey[800],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  Text(
                    'Need additional help? Send us a message and we\'ll get back to you as soon as possible.',
                    style: GoogleFonts.poppins(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      border: const OutlineInputBorder(),
                      labelStyle: GoogleFonts.poppins(),
                    ),
                    style: GoogleFonts.poppins(),
                    items: _categories.map((category) {
                      return DropdownMenuItem(
                        value: category,
                        child: Text(category, style: GoogleFonts.poppins()),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedCategory = value!;
                      });
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  TextField(
                    controller: _subjectController,
                    decoration: InputDecoration(
                      labelText: 'Subject',
                      border: const OutlineInputBorder(),
                      labelStyle: GoogleFonts.poppins(),
                      hintText: 'Brief description of your issue',
                    ),
                    style: GoogleFonts.poppins(),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      labelText: 'Message',
                      border: const OutlineInputBorder(),
                      labelStyle: GoogleFonts.poppins(),
                      hintText: 'Describe your issue or question in detail...',
                      alignLabelWithHint: true,
                    ),
                    style: GoogleFonts.poppins(),
                    maxLines: 5,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          _subjectController.clear();
                          _messageController.clear();
                          setState(() {
                            _selectedCategory = 'General';
                          });
                        },
                        child: Text('Clear', style: GoogleFonts.poppins()),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _sendSupportMessage,
                        icon: const Icon(Icons.send),
                        label: Text('Send Message', style: GoogleFonts.poppins()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickHelpItem(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.blue[700], size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFAQItem(String question, String answer) {
    return ExpansionTile(
      title: Text(
        question,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            answer,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  void _sendSupportMessage() {
    if (_subjectController.text.trim().isEmpty || _messageController.text.trim().isEmpty) {
      _showSnackBar('Please fill in both subject and message fields');
      return;
    }

    final emailBody = '''
Category: $_selectedCategory
Subject: ${_subjectController.text.trim()}

Message:
${_messageController.text.trim()}

---
Sent from CMMS Mobile App
''';

    _launchEmail('support@example.com', _subjectController.text.trim(), emailBody);
  }

  Future<void> _launchEmail(String email, String subject, [String? body]) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=${Uri.encodeComponent(subject)}${body != null ? '&body=${Uri.encodeComponent(body)}' : ''}',
    );
    
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
      _showSnackBar('Opening email client...');
    } else {
      _showSnackBar('Could not open email client');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins())),
      );
    }
  }
}