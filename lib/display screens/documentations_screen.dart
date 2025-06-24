import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/models/documentations.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class DocumentationsScreen extends StatefulWidget {
  final String facilityId;

  const DocumentationsScreen({super.key, required this.facilityId});

  @override
  State<DocumentationsScreen> createState() => _DocumentationsScreenState();
}

class _DocumentationsScreenState extends State<DocumentationsScreen> {
  final logger = Logger(printer: PrettyPrinter());
  final TextEditingController _titleController = TextEditingController();
  double? _uploadProgress;
  String _selectedCategory = 'Building Information';
  String _currentRole = 'User';
  String _organization = '-';

  static const Map<String, String> documentCategories = {
    'Building Information': 'Building Information',
    'Floor Plans': 'Floor Plans',
    'MEP Layouts': 'MEP Layouts',
    'Fire Safety': 'Fire Safety',
    'Compliance': 'Compliance',
    'Maintenance': 'Maintenance',
    'Waste Management': 'Waste Management',
    'Contractors': 'Contractors',
    'Land Rates': 'Land Rates',
  };

  @override
  void initState() {
    super.initState();
    logger.i('DocumentationsScreen initialized with facilityId: ${widget.facilityId}');
    _getCurrentUserRole();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final adminDoc = await FirebaseFirestore.instance.collection('Admins').doc(user.uid).get();
      final developerDoc = await FirebaseFirestore.instance.collection('Developers').doc(user.uid).get();
      final technicianDoc = await FirebaseFirestore.instance.collection('Technicians').doc(user.uid).get();
      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();
      
      String newRole = 'User';
      String newOrg = '-';
      
      if (adminDoc.exists) {
        newRole = 'Admin';
        final adminData = adminDoc.data();
        newOrg = adminData?['organization'] ?? '-';
      } 
      else if (developerDoc.exists) {
        newRole = 'Technician';
        newOrg = 'JV Almacis';
      }
      else if (technicianDoc.exists) {
        newRole = 'Technician';
        final techData = technicianDoc.data();
        newOrg = techData?['organization'] ?? '-';
      }
      else if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData != null && userData['role'] == 'Technician') {
          newRole = 'Technician';
          newOrg = '-';
        } else {
          newRole = 'User';
          newOrg = '-';
        }
      }
      
      if (mounted) {
        setState(() {
          _currentRole = newRole;
          _organization = newOrg;
        });
      }
    } catch (e) {
      logger.e('Error getting user role: $e');
    }
  }

  Future<void> _showUploadDialog() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Upload Documentation', style: GoogleFonts.poppins()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField(16.0),
              const SizedBox(height: 12),
              _buildCategoryDropdown(16.0),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _uploadDocument();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey[800],
              foregroundColor: Colors.white,
            ),
            child: Text('Upload File', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;

      final platformFile = result.files.single;
      final fileName = platformFile.name;
      final user = FirebaseAuth.instance.currentUser;
      
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please log in to upload documents', style: GoogleFonts.poppins())),
          );
        }
        return;
      }

      final title = _titleController.text.trim().isEmpty ? fileName : _titleController.text.trim();
      
      if (!mounted) {
        logger.w('Widget not mounted, skipping confirmation dialog for $fileName');
        return;
      }

      final bool? confirmUpload = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Confirm Upload', style: GoogleFonts.poppins()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kIsWeb) 
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'WEB',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Do you want to upload the file: $fileName?',
                style: GoogleFonts.poppins(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Upload', style: GoogleFonts.poppins()),
            ),
          ],
        ),
      );

      if (confirmUpload != true) {
        logger.i('User cancelled document upload: $fileName');
        return;
      }

      if (!mounted) {
        logger.w('Widget not mounted, skipping progress dialog for $fileName');
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text('Uploading $fileName', style: GoogleFonts.poppins()),
            content: StatefulBuilder(
              builder: (context, setDialogState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: _uploadProgress,
                      backgroundColor: Colors.grey[300],
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueGrey),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _uploadProgress != null
                          ? '${(_uploadProgress! * 100).toStringAsFixed(0)}%'
                          : 'Starting upload...',
                      style: GoogleFonts.poppins(),
                    ),
                    if (kIsWeb) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Web Upload',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.blue[600],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      );

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('facilities/${widget.facilityId}/documentations/${DateTime.now().millisecondsSinceEpoch}_$fileName');

      late UploadTask uploadTask;
      
      if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        if (platformFile.bytes == null) {
          throw 'File bytes not available for web/desktop upload';
        }
        
        final metadata = SettableMetadata(
          contentType: _getContentType(fileName),
          customMetadata: {
            'uploadedBy': user.uid,
            'originalName': fileName,
            'platform': kIsWeb ? 'web' : Platform.operatingSystem,
          },
        );
        
        uploadTask = storageRef.putData(platformFile.bytes!, metadata);
      } else {
        if (platformFile.path == null) {
          throw 'File path not available for mobile upload';
        }
        
        final file = File(platformFile.path!);
        final metadata = SettableMetadata(
          contentType: _getContentType(fileName),
          customMetadata: {
            'uploadedBy': user.uid,
            'originalName': fileName,
            'platform': Platform.operatingSystem,
          },
        );
        
        uploadTask = storageRef.putFile(file, metadata);
      }

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        if (mounted) {
          setState(() {
            _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
          });
        }
      }, onError: (e) {
        logger.e('Upload progress error: $e');
      });

      await uploadTask;
      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('Documentations').add({
        'userId': user.uid,
        'title': title,
        'fileName': fileName,
        'downloadUrl': downloadUrl,
        'uploadedAt': FieldValue.serverTimestamp(),
        'facilityId': widget.facilityId,
        'category': _selectedCategory,
        'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Document uploaded successfully', style: GoogleFonts.poppins())),
        );
        _titleController.clear();
      }
      logger.i('Uploaded document: $fileName, URL: $downloadUrl, facilityId: ${widget.facilityId}');
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading document: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error uploading document: $e');
    } finally {
      if (mounted) {
        setState(() {
          _uploadProgress = null;
        });
      }
    }
  }

  String _getContentType(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _viewDocument(String url, String fileName) async {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Loading document...', style: GoogleFonts.poppins()),
          ],
        ),
      ),
    );

    try {
      if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        Navigator.pop(context);
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not open document in browser';
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        if (fileName.toLowerCase().endsWith('.pdf')) {
          final tempDir = await getTemporaryDirectory();
          final filePath = '${tempDir.path}/$fileName';
          await Dio().download(url, filePath);
          final file = File(filePath);
          if (await file.exists()) {
            if (mounted) {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PDFViewerScreen(filePath: filePath, fileName: fileName),
                ),
              );
            }
          } else {
            throw 'Failed to download PDF';
          }
        } else {
          Navigator.pop(context);
          throw 'Only PDF viewing is supported on mobile';
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error viewing document: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error viewing document: $e');
    }
  }

  Future<void> _downloadDocument(String url, String fileName) async {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Downloading...', style: GoogleFonts.poppins()),
          ],
        ),
      ),
    );

    try {
      if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        Navigator.pop(context);
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not download document';
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        bool permissionGranted = await _requestStoragePermission();
        if (!permissionGranted) {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Storage permission denied', style: GoogleFonts.poppins())),
            );
          }
          return;
        }

        final downloadsDir = await getExternalStorageDirectory();
        final filePath = '${downloadsDir!.path}/$fileName';
        await Dio().download(url, filePath);

        final file = File(filePath);
        if (await file.exists()) {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Document downloaded to $filePath', style: GoogleFonts.poppins()),
                action: SnackBarAction(
                  label: 'Open',
                  onPressed: () => OpenFile.open(filePath),
                ),
              ),
            );
          }
          logger.i('Downloaded document: $fileName to $filePath');
        } else {
          throw 'Failed to download document';
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading document: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error downloading document: $e');
    }
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
        }
      }
      return status.isGranted;
    }
    return true;
  }

  Future<void> _deleteDocument(String downloadUrl, String fileName, String docId) async {
    if (!mounted) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Deletion', style: GoogleFonts.poppins()),
        content: Text('Are you sure you want to delete "$fileName"?', style: GoogleFonts.poppins()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) {
      logger.i('Deletion cancelled for: $fileName');
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Deleting...', style: GoogleFonts.poppins()),
            ],
          ),
        ),
      );
    }

    try {
      await FirebaseStorage.instance.refFromURL(downloadUrl).delete();
      await FirebaseFirestore.instance.collection('Documentations').doc(docId).delete();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Document deleted successfully', style: GoogleFonts.poppins())),
        );
      }
      logger.i('Deleted document: $fileName, docId: $docId');
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting document: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error deleting document: $e');
    }
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Colors.red[600]!;
      case 'doc':
      case 'docx':
        return Colors.blue[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Documentations',
      facilityId: widget.facilityId,
      currentRole: _currentRole,
      organization: _organization,
      floatingActionButton: FloatingActionButton(
        onPressed: _showUploadDialog,
        backgroundColor: Colors.blueGrey[800],
        child: const Icon(Icons.add, color: Colors.white),
      ),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    final isTablet = screenWidth > 600 && screenWidth <= 900;
    final padding = isMobile ? 16.0 : isTablet ? 24.0 : 32.0;
    final fontSizeTitle = isMobile ? 20.0 : isTablet ? 24.0 : 28.0;
    final fontSizeSubtitle = isMobile ? 14.0 : isTablet ? 16.0 : 18.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Uploaded Documents',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: fontSizeTitle,
                  color: Colors.blueGrey[900],
                ),
              ),
              if (kIsWeb) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'WEB',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('Documentations')
                .where('facilityId', isEqualTo: widget.facilityId)
                .orderBy('uploadedAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                logger.e('StreamBuilder error: ${snapshot.error}');
                return Text('Error: ${snapshot.error}', style: GoogleFonts.poppins());
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.description,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No documents uploaded yet',
                          style: GoogleFonts.poppins(
                            fontSize: fontSizeSubtitle,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap the + button to upload your first document',
                          style: GoogleFonts.poppins(
                            fontSize: fontSizeSubtitle - 2,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final documentation = Documentation.fromSnapshot(docs[index]);
                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      leading: Icon(
                        _getFileIcon(documentation.fileName),
                        color: _getFileIconColor(documentation.fileName),
                        size: isMobile ? 32 : 36,
                      ),
                      title: Text(
                        documentation.title,
                        style: GoogleFonts.poppins(
                          color: Colors.blueGrey[900],
                          fontWeight: FontWeight.w500,
                          fontSize: fontSizeSubtitle,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Category: ${documentation.category}',
                            style: GoogleFonts.poppins(
                              fontSize: isMobile ? 12 : 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            'Uploaded: ${documentation.uploadedAt != null ? DateFormat('MMM dd, yyyy').format(documentation.uploadedAt!) : 'Unknown date'}',
                            style: GoogleFonts.poppins(
                              fontSize: isMobile ? 12 : 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'view') {
                            _viewDocument(documentation.downloadUrl, documentation.fileName);
                          } else if (value == 'download') {
                            _downloadDocument(documentation.downloadUrl, documentation.fileName);
                          } else if (value == 'delete') {
                            _deleteDocument(documentation.downloadUrl, documentation.fileName, documentation.id);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'view',
                            child: Row(
                              children: [
                                Icon(Icons.visibility, color: Colors.blue[700], size: 20),
                                const SizedBox(width: 8),
                                Text('View', style: GoogleFonts.poppins()),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'download',
                            child: Row(
                              children: [
                                Icon(Icons.download, color: Colors.green[700], size: 20),
                                const SizedBox(width: 8),
                                Text('Download', style: GoogleFonts.poppins()),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red[700], size: 20),
                                const SizedBox(width: 8),
                                Text('Delete', style: GoogleFonts.poppins()),
                              ],
                            ),
                          ),
                        ],
                        icon: const Icon(Icons.more_vert, color: Colors.blueGrey),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(double fontSize) {
    return TextField(
      controller: _titleController,
      decoration: InputDecoration(
        labelText: 'Document Title (Optional)',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[400]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
        hintStyle: GoogleFonts.poppins(color: Colors.grey[400]),
      ),
      style: GoogleFonts.poppins(fontSize: fontSize),
    );
  }

  Widget _buildCategoryDropdown(double fontSize) {
    return DropdownButtonFormField<String>(
      value: _selectedCategory,
      decoration: InputDecoration(
        labelText: 'Document Category',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[400]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
      ),
      items: documentCategories.entries.map((entry) {
        return DropdownMenuItem<String>(
          value: entry.key,
          child: Text(
            entry.value,
            style: GoogleFonts.poppins(fontSize: fontSize),
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedCategory = value!;
        });
      },
      style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.black),
    );
  }
}

class PDFViewerScreen extends StatelessWidget {
  final String filePath;
  final String fileName;

  const PDFViewerScreen({super.key, required this.filePath, required this.fileName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: Colors.blueGrey[800],
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: PDFView(
          filePath: filePath,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          onError: (error) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error loading PDF: $error', style: GoogleFonts.poppins())),
            );
          },
        ),
      ),
    );
  }
}