import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/models/request.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:typed_data';

class RequestScreen extends StatefulWidget {
  final String facilityId;

  const RequestScreen({super.key, required this.facilityId});

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  final Logger _logger = Logger(printer: PrettyPrinter());
  final ImagePicker _imagePicker = ImagePicker();
  
  String _priority = 'Medium';
  String _statusFilter = 'All';
  final List<Map<String, String>> _attachmentUrls = [];
  bool _showForm = false;
  String _currentRole = 'User';
  String _organization = '-';
  bool _isClient = false;
  String? _createdByEmail;
  double? _uploadProgress;
  late TabController _tabController;
  bool _isSubmitting = false;

  // Status counts for tabs - using individual variables to prevent rebuild issues
  int _allCount = 0;
  int _openCount = 0;
  int _inProgressCount = 0;
  int _closedCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _getCurrentUserInfo();
    _logger.i('RequestScreen initialized: facilityId=${widget.facilityId}');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final adminDoc = await FirebaseFirestore.instance.collection('Admins').doc(user.uid).get();
      final developerDoc = await FirebaseFirestore.instance.collection('Developers').doc(user.uid).get();
      final technicianDoc = await FirebaseFirestore.instance.collection('Technicians').doc(user.uid).get();
      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();

      String newRole = 'User';
      String newOrg = '-';
      String? email = user.email;
      bool isClient = false;

      if (adminDoc.exists) {
        newRole = 'Admin';
        newOrg = adminDoc.data()?['organization'] ?? '-';
      } else if (developerDoc.exists) {
        newRole = 'Technician';
        newOrg = 'JV Almacis';
      } else if (technicianDoc.exists) {
        newRole = 'Technician';
        newOrg = technicianDoc.data()?['organization'] ?? '-';
      } else if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData != null && userData['role'] == 'Technician') {
          newRole = 'Technician';
          newOrg = userData['organization'] ?? '-';
        } else {
          newRole = 'User';
          newOrg = userData?['organization'] ?? '-';
        }
      }

      // Determine if user is client (organization != 'JV Almacis')
      isClient = newOrg != 'JV Almacis';

      if (mounted) {
        setState(() {
          _currentRole = newRole;
          _organization = newOrg;
          _isClient = isClient;
          _createdByEmail = email;
        });
        _logger.i('Updated client status for Work Requests: isClient=$isClient, org=$newOrg');
      }
    } catch (e) {
      _logger.e('Error getting user info: $e');
    }
  }

  Future<void> _addRequest() async {
    if (_formKey.currentState!.validate()) {
      if (_isSubmitting) return; // Prevent double submission
      
      setState(() {
        _isSubmitting = true;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isSubmitting = false;
        });
        if (mounted) _showSnackBar('Please log in to add requests');
        return;
      }

      try {
        final requestId = const Uuid().v4();
        _logger.i('Adding request: requestId=$requestId, title=${_titleController.text}');

        final request = Request(
          id: requestId,
          requestId: requestId,
          title: _titleController.text,
          description: _descriptionController.text,
          status: 'Open',
          priority: _priority,
          createdAt: DateTime.now(),
          createdBy: user.uid,
          createdByEmail: _createdByEmail,
          facilityId: widget.facilityId,
          attachments: List<Map<String, String>>.from(_attachmentUrls),
          comments: [
            if (_notesController.text.isNotEmpty)
              {
                'action': 'Comment',
                'timestamp': Timestamp.now(),
                'comment': _notesController.text,
                'userId': user.uid,
                'userEmail': _createdByEmail,
              }
          ],
          workOrderIds: [],
          clientStatus: 'Pending',
        );

        // Use batch write to ensure atomicity
        final batch = FirebaseFirestore.instance.batch();
        final docRef = FirebaseFirestore.instance.collection('Work_Requests').doc(requestId);
        
        batch.set(docRef, request.toMap());
        await batch.commit();

        if (mounted) {
          setState(() {
            _attachmentUrls.clear();
            _showForm = false;
            _isSubmitting = false;
          });
          _titleController.clear();
          _descriptionController.clear();
          _notesController.clear();
          _showSnackBar('Request submitted successfully');
        }
      } catch (e) {
        _logger.e('Error adding request: $e');
        setState(() {
          _isSubmitting = false;
        });
        if (mounted) _showSnackBar('Error submitting request. Please try again.');
      }
    } else {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _uploadImageAttachment() async {
    try {
      _logger.i('Picking image attachment');
      
      XFile? pickedFile;
      if (kIsWeb) {
        pickedFile = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );
      } else {
        // Show source selection for mobile
        final ImageSource? source = await showDialog<ImageSource>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Select Image Source', style: GoogleFonts.poppins()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: Text('Camera', style: GoogleFonts.poppins()),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: Text('Gallery', style: GoogleFonts.poppins()),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
        
        if (source != null) {
          pickedFile = await _imagePicker.pickImage(
            source: source,
            maxWidth: 1920,
            maxHeight: 1080,
            imageQuality: 85,
          );
        }
      }

      if (pickedFile == null) {
        _logger.w('No image selected');
        return;
      }

      await _processAndUploadFile(pickedFile.name, await pickedFile.readAsBytes());
    } catch (e) {
      _logger.e('Error picking image: $e');
      if (mounted) _showSnackBar('Error selecting image: $e');
    }
  }

  Future<void> _uploadDocumentAttachment() async {
    try {
      _logger.i('Picking document attachment');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'doc', 'txt'],
        withData: true, // Always get bytes for cross-platform compatibility
      );
      
      if (result == null || result.files.isEmpty) {
        _logger.w('No document selected');
        return;
      }

      final platformFile = result.files.single;
      Uint8List? fileBytes;
      
      // Always use bytes for cross-platform compatibility
      if (platformFile.bytes != null) {
        fileBytes = platformFile.bytes!;
      } else {
        // Fallback for mobile platforms
        if (!kIsWeb && platformFile.path != null) {
          final file = File(platformFile.path!);
          fileBytes = await file.readAsBytes();
        }
      }

      if (fileBytes == null) {
        throw 'Could not read file data';
      }

      await _processAndUploadFile(platformFile.name, fileBytes);
    } catch (e) {
      _logger.e('Error picking document: $e');
      if (mounted) _showSnackBar('Error selecting document: $e');
    }
  }

  Future<void> _processAndUploadFile(String fileName, Uint8List fileBytes) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) _showSnackBar('Please sign in to upload attachments');
      return;
    }

    if (!mounted) return;

    final bool? confirmUpload = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Upload', style: GoogleFonts.poppins()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getFileIcon(fileName),
              size: 48,
              color: _getFileIconColor(fileName),
            ),
            const SizedBox(height: 16),
            Text(
              'Upload: $fileName?',
              style: GoogleFonts.poppins(),
              textAlign: TextAlign.center,
            ),
            Text(
              'Size: ${(fileBytes.length / 1024 / 1024).toStringAsFixed(2)} MB',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Upload', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );

    if (confirmUpload != true) return;

    if (!mounted) return;

    // Show upload progress dialog
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
                  const SizedBox(height: 16),
                  Text(
                    _uploadProgress != null
                        ? '${(_uploadProgress! * 100).toStringAsFixed(0)}%'
                        : 'Starting upload...',
                    style: GoogleFonts.poppins(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('facilities/${widget.facilityId}/work_requests/${timestamp}_$fileName');

      final metadata = SettableMetadata(
        contentType: _getContentType(fileName),
        customMetadata: {
          'uploadedBy': user.uid,
          'originalName': fileName,
          'platform': kIsWeb ? 'web' : Platform.operatingSystem,
          'facilityId': widget.facilityId,
        },
      );

      final uploadTask = storageRef.putData(fileBytes, metadata);

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        if (mounted) {
          setState(() {
            _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
          });
        }
      }, onError: (e) {
        _logger.e('Upload progress error: $e');
      });

      await uploadTask;
      final downloadUrl = await storageRef.getDownloadURL();

      if (mounted) {
        setState(() {
          _attachmentUrls.add({'name': fileName, 'url': downloadUrl});
          _uploadProgress = null;
        });
        Navigator.pop(context);
        _showSnackBar('Attachment uploaded successfully');
      }
      _logger.i('Attachment uploaded: $fileName, URL: $downloadUrl');
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadProgress = null;
        });
        Navigator.pop(context);
        _showSnackBar('Error uploading attachment: $e');
      }
      _logger.e('Error uploading attachment: $e');
    }
  }

  String _getContentType(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'doc':
        return 'application/msword';
      case 'txt':
        return 'text/plain';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _viewAttachment(String url, String fileName) async {
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
            Text('Loading file...', style: GoogleFonts.poppins()),
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
          throw 'Could not open file in browser';
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        final extension = fileName.toLowerCase().split('.').last;
        if (['jpg', 'jpeg', 'png'].contains(extension)) {
          Navigator.pop(context);
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ImageViewerScreen(
                  imageUrl: url,
                  fileName: fileName,
                ),
              ),
            );
          }
        } else {
          Navigator.pop(context);
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            throw 'Could not open file';
          }
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Error viewing file: $e');
      }
      _logger.e('Error viewing file: $e');
    }
  }

  Future<void> _downloadAttachment(String url, String fileName) async {
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
          throw 'Could not download file';
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        bool permissionGranted = await _requestStoragePermission();
        if (!permissionGranted) {
          if (mounted) {
            Navigator.pop(context);
            _showSnackBar('Storage permission denied');
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
            _showSnackBar('File downloaded to Downloads folder');
          }
          _logger.i('Downloaded file: $fileName to $filePath');
        } else {
          throw 'Failed to download file';
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Error downloading file: $e');
      }
      _logger.e('Error downloading file: $e');
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

  Future<void> _updateStatus(String docId, String newStatus, String comment) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      _logger.i('Updating status: docId=$docId, newStatus=$newStatus');
      
      final updateData = <String, dynamic>{
        'status': newStatus,
      };
      
      if (comment.isNotEmpty) {
        updateData['comments'] = FieldValue.arrayUnion([
          {
            'action': 'Status changed to $newStatus',
            'timestamp': Timestamp.now(),
            'comment': comment,
            'userId': user.uid,
            'userEmail': _createdByEmail,
          }
        ]);
      }
      
      await FirebaseFirestore.instance
          .collection('Work_Requests')
          .doc(docId)
          .update(updateData);
          
      if (mounted) _showSnackBar('Status updated to $newStatus');
    } catch (e) {
      _logger.e('Error updating status: $e');
      if (mounted) _showSnackBar('Error updating status: $e');
    }
  }

  // Fixed: Update status counts without causing rebuilds
  void _updateStatusCounts(List<QueryDocumentSnapshot> docs) {
    final newAllCount = docs.length;
    int newOpenCount = 0;
    int newInProgressCount = 0;
    int newClosedCount = 0;

    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'] ?? 'Open';
      switch (status) {
        case 'Open':
          newOpenCount++;
          break;
        case 'In Progress':
          newInProgressCount++;
          break;
        case 'Closed':
          newClosedCount++;
          break;
      }
    }

    // Only update if counts actually changed
    if (_allCount != newAllCount || 
        _openCount != newOpenCount || 
        _inProgressCount != newInProgressCount || 
        _closedCount != newClosedCount) {
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _allCount = newAllCount;
            _openCount = newOpenCount;
            _inProgressCount = newInProgressCount;
            _closedCount = newClosedCount;
          });
        }
      });
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.poppins()),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Work Requests',
      facilityId: widget.facilityId,
      currentRole: _currentRole,
      organization: _organization,
      floatingActionButton: _isClient
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _showForm = !_showForm),
              backgroundColor: Colors.blueGrey[800],
              icon: Icon(_showForm ? Icons.close : Icons.add, color: Colors.white),
              label: Text(
                _showForm ? 'Cancel' : 'New Request',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            )
          : null,
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
          // Status filter tabs - Fixed position
          Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filter by Status:',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w500,
                    color: Colors.blueGrey[800],
                    fontSize: fontSizeSubtitle,
                  ),
                ),
                const SizedBox(height: 12),
                _buildResponsiveTabBar(isMobile, isTablet),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_showForm && _isClient) _buildRequestForm(padding, fontSizeTitle, fontSizeSubtitle),
          const SizedBox(height: 24),
          _buildRequestsList(padding, fontSizeSubtitle, isMobile),
          const SizedBox(height: 80), // Padding to avoid overlap with FAB
        ],
      ),
    );
  }

  Widget _buildResponsiveTabBar(bool isMobile, bool isTablet) {
    if (isMobile) {
      // For mobile, use horizontal scrollable tabs
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildTabButton('All', _allCount, Colors.grey, 0),
            const SizedBox(width: 8),
            _buildTabButton('Open', _openCount, Colors.blue, 1),
            const SizedBox(width: 8),
            _buildTabButton('In Progress', _inProgressCount, Colors.orange, 2),
            const SizedBox(width: 8),
            _buildTabButton('Closed', _closedCount, Colors.green, 3),
          ],
        ),
      );
    } else {
      // For tablet and desktop, use grid layout
      return Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _buildTabButton('All', _allCount, Colors.grey, 0),
          _buildTabButton('Open', _openCount, Colors.blue, 1),
          _buildTabButton('In Progress', _inProgressCount, Colors.orange, 2),
          _buildTabButton('Closed', _closedCount, Colors.green, 3),
        ],
      );
    }
  }

  Widget _buildTabButton(String label, int count, Color color, int index) {
    final statuses = ['All', 'Open', 'In Progress', 'Closed'];
    final isSelected = _statusFilter == statuses[index];
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _statusFilter = statuses[index];
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? color : Colors.white,
          border: Border.all(
            color: color.withValues(alpha: 0.5),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : color,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.2) : color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                count.toString(),
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsList(double padding, double fontSizeSubtitle, bool isMobile) {
    return StreamBuilder<QuerySnapshot>(
      stream: _buildRequestsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        
        if (snapshot.hasError) {
          _logger.e('Firestore error: ${snapshot.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading requests',
                    style: GoogleFonts.poppins(
                      fontSize: fontSizeSubtitle,
                      color: Colors.red[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please check your connection and try again',
                    style: GoogleFonts.poppins(
                      fontSize: fontSizeSubtitle - 2,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        
        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        
        final docs = snapshot.data!.docs;
        
        // Update status counts
        _updateStatusCounts(docs);

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Icon(
                    Icons.request_page_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _statusFilter == 'All' ? 'No requests found' : 'No $_statusFilter requests',
                    style: GoogleFonts.poppins(
                      fontSize: fontSizeSubtitle,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_isClient) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Tap the + button to create your first request',
                      style: GoogleFonts.poppins(
                        fontSize: fontSizeSubtitle - 2,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
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
            final data = docs[index].data() as Map<String, dynamic>;
            final request = Request.fromMap(data, docs[index].id);
            return _buildRequestCard(request, fontSizeSubtitle, isMobile);
          },
        );
      },
    );
  }

  Stream<QuerySnapshot> _buildRequestsStream() {
    Query query = FirebaseFirestore.instance
        .collection('Work_Requests')
        .where('facilityId', isEqualTo: widget.facilityId);
    
    if (_statusFilter != 'All') {
      query = query.where('status', isEqualTo: _statusFilter);
    }
    
    return query.orderBy('createdAt', descending: true).snapshots();
  }

  Widget _buildRequestCard(Request request, double fontSize, bool isMobile) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _getStatusColor(request.status),
                  child: Icon(
                    _getStatusIcon(request.status),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.title,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: Colors.blueGrey[900],
                          fontSize: fontSize,
                        ),
                      ),
                      Text(
                        'Priority: ${request.priority} | Created: ${request.createdAt != null ? DateFormat.yMMMd().format(request.createdAt!) : 'Unknown'}',
                        style: GoogleFonts.poppins(
                          fontSize: isMobile ? 12 : 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(request.status),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    request.status,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Description', request.description, fontSize, isMobile),
            _buildDetailRow('Created By', request.createdByEmail ?? request.createdBy, fontSize, isMobile),
            if (request.attachments.isNotEmpty)
              _buildAttachmentsSection(request.attachments, fontSize),
            if (request.comments.isNotEmpty)
              _buildCommentsSection(request.comments, fontSize),
            if (request.workOrderIds.isNotEmpty)
              _buildWorkOrdersSection(request.workOrderIds, fontSize),
            const SizedBox(height: 12),
            if (!_isClient) _buildActionButtons(request, fontSize),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, double fontSize, bool isMobile) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: isMobile 
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label:',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w500,
                  color: Colors.blueGrey[700],
                  fontSize: fontSize,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.poppins(
                  color: Colors.grey[800], 
                  fontSize: fontSize,
                ),
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  '$label:',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w500,
                    color: Colors.blueGrey[700],
                    fontSize: fontSize,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: GoogleFonts.poppins(
                    color: Colors.grey[800], 
                    fontSize: fontSize,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildAttachmentsSection(List<Map<String, String>> attachments, double fontSize) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attachments:',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
              color: Colors.blueGrey[700],
              fontSize: fontSize,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: attachments
                .map((attachment) => GestureDetector(
                      onLongPress: () => _showAttachmentOptions(attachment['url']!, attachment['name']!),
                      onTap: () => _viewAttachment(attachment['url']!, attachment['name']!),
                      child: Chip(
                        avatar: Icon(
                          _getFileIcon(attachment['name']!),
                          size: 16,
                          color: _getFileIconColor(attachment['name']!),
                        ),
                        label: Text(
                          attachment['name']!,
                          style: GoogleFonts.poppins(fontSize: fontSize - 2),
                        ),
                        backgroundColor: Colors.blue[50],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  void _showAttachmentOptions(String url, String fileName) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.visibility, color: Colors.blue[700]),
              title: Text('View', style: GoogleFonts.poppins()),
              onTap: () {
                Navigator.pop(context);
                _viewAttachment(url, fileName);
              },
            ),
            ListTile(
              leading: Icon(Icons.download, color: Colors.green[700]),
              title: Text('Download', style: GoogleFonts.poppins()),
              onTap: () {
                Navigator.pop(context);
                _downloadAttachment(url, fileName);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentsSection(List<Map<String, dynamic>> comments, double fontSize) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Comments:',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
              color: Colors.blueGrey[700],
              fontSize: fontSize,
            ),
          ),
          const SizedBox(height: 4),
          ...comments.map((entry) => Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry['action'] ?? 'Comment',
                      style: GoogleFonts.poppins(fontSize: fontSize - 2, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'by ${entry['userEmail'] ?? entry['userId'] ?? 'Unknown'} at ${entry['timestamp'] != null ? DateFormat.yMMMd().format((entry['timestamp'] as Timestamp).toDate()) : 'Unknown date'}',
                      style: GoogleFonts.poppins(
                        fontSize: fontSize - 4,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (entry['comment'] != null && entry['comment'].isNotEmpty)
                      Text(
                        entry['comment'],
                        style: GoogleFonts.poppins(fontSize: fontSize - 3),
                      ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildWorkOrdersSection(List<String> workOrderIds, double fontSize) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Related Work Orders:',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
              color: Colors.blueGrey[700],
              fontSize: fontSize,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: workOrderIds
                .map((id) => Chip(
                      label: Text(
                        'WO-$id',
                        style: GoogleFonts.poppins(fontSize: fontSize - 2),
                      ),
                      backgroundColor: Colors.blue[50],
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(Request request, double fontSize) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: () => _showUpdateStatusDialog(request, fontSize),
          icon: const Icon(Icons.edit, size: 16),
          label: Text('Update Status', style: GoogleFonts.poppins(fontSize: fontSize)),
          style: TextButton.styleFrom(
            foregroundColor: Colors.blueGrey[700],
          ),
        ),
      ],
    );
  }

  void _showUpdateStatusDialog(Request request, double fontSize) {
    final commentController = TextEditingController();
    String selectedStatus = request.status;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Request Status', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: fontSize)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: selectedStatus,
              items: ['Open', 'In Progress', 'Closed']
                  .map((status) => DropdownMenuItem(
                        value: status,
                        child: Text(status, style: GoogleFonts.poppins(color: Colors.blueGrey[900])),
                      ))
                  .toList(),
              onChanged: (value) => selectedStatus = value!,
              decoration: InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[400]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
                labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
              ),
              style: GoogleFonts.poppins(color: Colors.blueGrey[900]),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: commentController,
              decoration: InputDecoration(
                labelText: 'Comment (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[400]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[100],
                labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
              ),
              style: GoogleFonts.poppins(fontSize: fontSize),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(fontSize: fontSize)),
          ),
          ElevatedButton(
            onPressed: () {
              _updateStatus(request.id, selectedStatus, commentController.text);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey[800],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Update', style: GoogleFonts.poppins(color: Colors.white, fontSize: fontSize)),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestForm(double padding, double fontSizeTitle, double fontSizeSubtitle) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.all(padding),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Create Request',
                    style: GoogleFonts.poppins(
                      fontSize: fontSizeTitle,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[900],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.blueGrey),
                    onPressed: () => setState(() => _showForm = false),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              isMobile
                  ? Column(
                      children: [
                        _buildTextField(_titleController, 'Title', fontSizeSubtitle, validator: (value) => value!.isEmpty ? 'Enter a title' : null),
                        const SizedBox(height: 16),
                        _buildTextField(_descriptionController, 'Description', fontSizeSubtitle, maxLines: 3),
                        const SizedBox(height: 16),
                        _buildDropdown('Priority', _priority, ['Low', 'Medium', 'High'], (value) => setState(() => _priority = value!), fontSizeSubtitle),
                        const SizedBox(height: 16),
                        _buildTextField(_notesController, 'Comment', fontSizeSubtitle, maxLines: 2),
                      ],
                    )
                  : Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildTextField(_titleController, 'Title', fontSizeSubtitle, validator: (value) => value!.isEmpty ? 'Enter a title' : null)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildTextField(_descriptionController, 'Description', fontSizeSubtitle, maxLines: 3)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildDropdown('Priority', _priority, ['Low', 'Medium', 'High'], (value) => setState(() => _priority = value!), fontSizeSubtitle)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildTextField(_notesController, 'Comment', fontSizeSubtitle, maxLines: 2)),
                          ],
                        ),
                      ],
                    ),
              const SizedBox(height: 16),
              // Separate buttons for image and document attachments
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _uploadImageAttachment,
                      icon: const Icon(Icons.image, color: Colors.white),
                      label: Text('Add Image', style: GoogleFonts.poppins(color: Colors.white, fontSize: fontSizeSubtitle)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _uploadDocumentAttachment,
                      icon: const Icon(Icons.attach_file, color: Colors.white),
                      label: Text('Add Document', style: GoogleFonts.poppins(color: Colors.white, fontSize: fontSizeSubtitle)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey[600],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 4,
                      ),
                    ),
                  ),
                ],
              ),
              if (_attachmentUrls.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: _attachmentUrls
                      .map((attachment) => Chip(
                            avatar: Icon(
                              _getFileIcon(attachment['name']!),
                              size: 16,
                              color: _getFileIconColor(attachment['name']!),
                            ),
                            label: Text(attachment['name']!, style: GoogleFonts.poppins(fontSize: fontSizeSubtitle - 2)),
                            backgroundColor: Colors.blue[50],
                            onDeleted: () {
                              setState(() {
                                _attachmentUrls.remove(attachment);
                              });
                            },
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => setState(() => _showForm = false),
                      child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.blueGrey[800], fontSize: fontSizeSubtitle)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _addRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey[800],
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 4,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              'Submit Request',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: fontSizeSubtitle,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String labelText,
    double fontSize, {
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: labelText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
      ),
      style: GoogleFonts.poppins(fontSize: fontSize),
      maxLines: maxLines,
      validator: validator,
    );
  }

  Widget _buildDropdown(
    String labelText,
    String value,
    List<String> items,
    Function(String?) onChanged,
    double fontSize,
  ) {
    return DropdownButtonFormField<String>(
      value: value,
      items: items
          .map((item) => DropdownMenuItem(
                value: item,
                child: Text(item, style: GoogleFonts.poppins(color: Colors.blueGrey[900])),
              ))
          .toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: labelText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
      ),
      style: GoogleFonts.poppins(color: Colors.blueGrey[900], fontSize: fontSize),
      dropdownColor: Colors.white,
      icon: Icon(Icons.arrow_drop_down, color: Colors.blueGrey[800]),
    );
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'docx':
      case 'doc':
        return Icons.description;
      case 'txt':
        return Icons.text_snippet;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Colors.red[600]!;
      case 'docx':
      case 'doc':
        return Colors.blueGrey[600]!;
      case 'txt':
        return Colors.grey[600]!;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Colors.green[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Colors.blue;
      case 'in progress':
        return Colors.orange;
      case 'closed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Icons.radio_button_unchecked;
      case 'in progress':
        return Icons.hourglass_empty;
      case 'closed':
        return Icons.check_circle;
      default:
        return Icons.help;
    }
  }
}

// Image viewer screen for viewing attached images
class ImageViewerScreen extends StatelessWidget {
  final String imageUrl;
  final String fileName;

  const ImageViewerScreen({
    super.key,
    required this.imageUrl,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: Colors.blueGrey[800],
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(
            imageUrl,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                      : null,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading image',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}