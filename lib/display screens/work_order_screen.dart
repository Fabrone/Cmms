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
import 'package:cmms/models/work_order.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:typed_data';

//import 'package:flutter_app/models/work_order.dart';
//import 'package:flutter_app/providers/work_order_provider.dart';

class WorkOrderScreen extends StatefulWidget {
  final String facilityId;

  const WorkOrderScreen({super.key, required this.facilityId});

  @override
  State<WorkOrderScreen> createState() => _WorkOrderScreenState();
}

class _WorkOrderScreenState extends State<WorkOrderScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  final Logger _logger = Logger(printer: PrettyPrinter());
  final ImagePicker _imagePicker = ImagePicker();
  
  String _priority = 'Medium';
  String _statusFilter = 'All';
  String _priorityFilter = 'All';
  String _workOrderStatusFilter = 'All';
  bool _isClientStatusFilterMode = true;
  bool _isInApprovedSubView = false; // Track if we're in the approved sub-view
  String? _selectedRequestId;
  String? _selectedTechnicianId;
  String? _selectedTechnicianEmail;
  final List<Map<String, String>> _attachmentUrls = [];
  bool _showForm = false;
  String _currentRole = 'User';
  String _organization = '-';
  bool _isJVAlmacisUser = false;
  bool _isAdminClient = false;
  String? _createdByEmail;
  String? _createdByUsername;
  double? _uploadProgress;
  late TabController _tabController;
  bool _isSubmitting = false;

  // Client status counts (removed declined)
  int _allCount = 0;
  int _approvedCount = 0;
  int _toBeReviewedCount = 0;

  // Priority counts
  int _allPriorityCount = 0;
  int _highPriorityCount = 0;
  int _mediumPriorityCount = 0;
  int _lowPriorityCount = 0;

  // Work order status counts (for approved sub-view)
  int _approvedAllCount = 0;
  int _approvedOpenCount = 0;
  int _approvedInProgressCount = 0;
  int _approvedCompletedCount = 0;

  // Cache for all work orders to avoid repeated queries
  List<QueryDocumentSnapshot> _allWorkOrders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _getCurrentUserInfo();
    _logger.i('WorkOrderScreen initialized: facilityId=${widget.facilityId}');
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
      String? username;
      bool isClient = false;
      bool isJVAlmacisUser = false;
      bool isAdminClient = false;

      if (adminDoc.exists) {
        newRole = 'Admin';
        final data = adminDoc.data()!;
        newOrg = data['organization'] ?? '-';
        username = data['username'] ?? data['name'] ?? data['displayName'];
        isClient = newOrg != 'JV Almacis';
        isJVAlmacisUser = newOrg == 'JV Almacis';
        isAdminClient = isClient; // Admin client has special privileges
      } else if (developerDoc.exists) {
        newRole = 'Technician';
        newOrg = 'JV Almacis';
        final data = developerDoc.data()!;
        username = data['username'] ?? data['name'] ?? data['displayName'];
        isJVAlmacisUser = true;
      } else if (technicianDoc.exists) {
        newRole = 'Technician';
        final data = technicianDoc.data()!;
        newOrg = data['organization'] ?? '-';
        username = data['username'] ?? data['name'] ?? data['displayName'];
        isClient = newOrg != 'JV Almacis';
        isJVAlmacisUser = newOrg == 'JV Almacis';
      } else if (userDoc.exists) {
        final userData = userDoc.data()!;
        if (userData['role'] == 'Technician') {
          newRole = 'Technician';
          newOrg = userData['organization'] ?? '-';
        } else {
          newRole = 'User';
          newOrg = userData['organization'] ?? '-';
        }
        username = userData['username'] ?? userData['name'] ?? userData['displayName'];
        isClient = newOrg != 'JV Almacis';
        isJVAlmacisUser = newOrg == 'JV Almacis';
      }

      if (mounted) {
        setState(() {
          _currentRole = newRole;
          _organization = newOrg;
          _isJVAlmacisUser = isJVAlmacisUser;
          _isAdminClient = isAdminClient;
          _createdByEmail = email;
          _createdByUsername = username;
        });
        _logger.i('Updated user info for Work Orders: isJVAlmacis=$isJVAlmacisUser, org=$newOrg, username=$username');
      }
    } catch (e) {
      _logger.e('Error getting user info: $e');
    }
  }

  // Add this method to fetch username from Users collection
  Future<String> _getUsernameFromCollection(String userId) async {
    try {
      // Check Users collection first
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(userId)
          .get();
      
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        final username = userData['username'] ?? userData['name'] ?? userData['displayName'];
        if (username != null && username.isNotEmpty) {
          return username;
        }
      }
      
      // Fallback to other collections if not found in Users
      final adminDoc = await FirebaseFirestore.instance
          .collection('Admins')
          .doc(userId)
          .get();
      
      if (adminDoc.exists) {
        final adminData = adminDoc.data()!;
        final username = adminData['username'] ?? adminData['name'] ?? adminData['displayName'];
        if (username != null && username.isNotEmpty) {
          return username;
        }
      }
      
      final techDoc = await FirebaseFirestore.instance
          .collection('Technicians')
          .doc(userId)
          .get();
      
      if (techDoc.exists) {
        final techData = techDoc.data()!;
        final username = techData['username'] ?? techData['name'] ?? techData['displayName'];
        if (username != null && username.isNotEmpty) {
          return username;
        }
      }
      
      final devDoc = await FirebaseFirestore.instance
          .collection('Developers')
          .doc(userId)
          .get();
      
      if (devDoc.exists) {
        final devData = devDoc.data()!;
        final username = devData['username'] ?? devData['name'] ?? devData['displayName'];
        if (username != null && username.isNotEmpty) {
          return username;
        }
      }
      
      // Final fallback to email from Firebase Auth
      final user = await FirebaseAuth.instance.userChanges().first;
      if (user != null && user.uid == userId) {
        return user.email ?? 'Unknown User';
      }
      
      return 'Unknown User';
    } catch (e) {
      _logger.e('Error fetching username for user $userId: $e');
      return 'Unknown User';
    }
  }

  // Modified method to fetch request title without ID
  Future<String> _getRequestTitleFromId(String requestId) async {
    try {
      final requestDoc = await FirebaseFirestore.instance
          .collection('Work_Requests')
          .doc(requestId)
          .get();
      
      if (requestDoc.exists) {
        final requestData = requestDoc.data()!;
        final title = requestData['title'] ?? 'Untitled Request';
        return title; // Removed ID from display
      }
      
      return 'Untitled Request';
    } catch (e) {
      _logger.e('Error fetching request title for $requestId: $e');
      return 'Untitled Request';
    }
  }

  Future<void> _addWorkOrder() async {
    if (_formKey.currentState!.validate()) {
      if (_isSubmitting) return;
      
      setState(() {
        _isSubmitting = true;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isSubmitting = false;
        });
        if (mounted) _showSnackBar('Please log in to add work orders');
        return;
      }

      try {
        final workOrderId = const Uuid().v4();
        _logger.i('Adding work order: workOrderId=$workOrderId, title=${_titleController.text}');

        final workOrder = WorkOrder(
          id: workOrderId,
          workOrderId: workOrderId,
          requestId: _selectedRequestId,
          title: _titleController.text,
          description: _descriptionController.text,
          status: 'Open',
          priority: _priority,
          assignedTo: _selectedTechnicianId ?? '',
          assignedToEmail: _selectedTechnicianEmail ?? '',
          createdAt: DateTime.now(),
          createdBy: user.uid,
          createdByEmail: _createdByEmail ?? '',
          facilityId: widget.facilityId,
          attachments: List<Map<String, String>>.from(_attachmentUrls),
          history: [
            {
              'action': 'Work Order Created',
              'timestamp': Timestamp.now(),
              'notes': _notesController.text,
              'userId': user.uid,
              'userEmail': _createdByEmail,
              'username': _createdByUsername ?? _createdByEmail ?? 'Unknown User',
            }
          ],
          clientStatus: 'To be Reviewed',
          clientNotes: '',
        );

        await FirebaseFirestore.instance
            .collection('Work_Orders')
            .doc(workOrderId)
            .set(workOrder.toMap());

        // Update the related request if selected
        if (_selectedRequestId != null) {
          await FirebaseFirestore.instance
              .collection('Work_Requests')
              .doc(_selectedRequestId)
              .update({
            'workOrderIds': FieldValue.arrayUnion([workOrderId]),
            'status': 'In Progress',
          });
        }

        if (mounted) {
          setState(() {
            _attachmentUrls.clear();
            _selectedRequestId = null;
            _selectedTechnicianId = null;
            _selectedTechnicianEmail = null;
            _showForm = false;
            _isSubmitting = false;
          });
          _titleController.clear();
          _descriptionController.clear();
          _notesController.clear();
          _showSnackBar('Work Order created successfully');
        }
      } catch (e) {
        _logger.e('Error adding work order: $e');
        setState(() {
          _isSubmitting = false;
        });
        if (mounted) _showSnackBar('Error: $e');
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
        withData: true,
      );
      
      if (result == null || result.files.isEmpty) {
        _logger.w('No document selected');
        return;
      }

      final platformFile = result.files.single;
      Uint8List? fileBytes;
      
      if (platformFile.bytes != null) {
        fileBytes = platformFile.bytes!;
      } else {
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
          .child('facilities/${widget.facilityId}/work_orders/${timestamp}_$fileName');

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

  Future<void> _updateClientStatus(String docId, String newStatus, String notes) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      _logger.i('Updating client status: docId=$docId, newStatus=$newStatus');
      
      // Create history entry with more detailed information
      final historyEntry = {
        'action': 'Client Status: $newStatus',
        'timestamp': Timestamp.now(),
        'notes': notes.isNotEmpty ? notes : 'No additional comments',
        'userId': user.uid,
        'userEmail': _createdByEmail,
        'username': _createdByUsername ?? _createdByEmail ?? 'Unknown User',
        'previousStatus': null, // Will be filled by getting current status first
      };

      // Get current status for history tracking
      final currentDoc = await FirebaseFirestore.instance
          .collection('Work_Orders')
          .doc(docId)
          .get();
      
      if (currentDoc.exists) {
        final currentData = currentDoc.data() as Map<String, dynamic>;
        historyEntry['previousStatus'] = currentData['clientStatus'] ?? 'Unknown';
      }

      await FirebaseFirestore.instance
          .collection('Work_Orders')
          .doc(docId)
          .update({
        'clientStatus': newStatus,
        'clientNotes': notes,
        'clientActionDate': Timestamp.now(),
        'history': FieldValue.arrayUnion([historyEntry]),
      });
    
      if (mounted) {
        _showSnackBar(
          newStatus == 'To be Reviewed' 
            ? 'Work order sent for review'
            : 'Work order $newStatus successfully'
        );
      }
    } catch (e) {
      _logger.e('Error updating client status: $e');
      if (mounted) _showSnackBar('Error updating status: $e');
    }
  }

  Future<void> _updateStatus(String docId, String newStatus, String notes) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      _logger.i('Updating status: docId=$docId, newStatus=$newStatus');
      await FirebaseFirestore.instance
          .collection('Work_Orders')
          .doc(docId)
          .update({
        'status': newStatus,
        'history': FieldValue.arrayUnion([
          {
            'action': 'Status changed to $newStatus',
            'timestamp': Timestamp.now(),
            'notes': notes,
            'userId': user.uid,
            'userEmail': _createdByEmail,
            'username': _createdByUsername ?? _createdByEmail ?? 'Unknown User',
          }
        ]),
      });
      if (mounted) _showSnackBar('Status updated to $newStatus');
    } catch (e) {
      _logger.e('Error updating status: $e');
      if (mounted) _showSnackBar('Error updating status: $e');
    }
  }

  // Update client status counts from all work orders (removed declined)
  void _updateClientStatusCounts(List<QueryDocumentSnapshot> allDocs) {
    final newAllCount = allDocs.length;
    int newApprovedCount = 0;
    int newToBeReviewedCount = 0;

    for (var doc in allDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final clientStatus = data['clientStatus'] ?? 'To be Reviewed';
      switch (clientStatus) {
        case 'Approved':
          newApprovedCount++;
          break;
        case 'To be Reviewed':
          newToBeReviewedCount++;
          break;
        // Handle legacy "Declined" status by treating as "To be Reviewed"
        case 'Declined':
          newToBeReviewedCount++;
          break;
      }
    }

    // Only update if counts actually changed
    if (_allCount != newAllCount || 
        _approvedCount != newApprovedCount || 
        _toBeReviewedCount != newToBeReviewedCount) {
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _allCount = newAllCount;
            _approvedCount = newApprovedCount;
            _toBeReviewedCount = newToBeReviewedCount;
          });
        }
      });
    }
  }

  // Update priority counts from all work orders
  void _updatePriorityCounts(List<QueryDocumentSnapshot> allDocs) {
    final newAllPriorityCount = allDocs.length;
    int newHighPriorityCount = 0;
    int newMediumPriorityCount = 0;
    int newLowPriorityCount = 0;

    for (var doc in allDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final priority = data['priority'] ?? 'Medium';
      switch (priority) {
        case 'High':
          newHighPriorityCount++;
          break;
        case 'Medium':
          newMediumPriorityCount++;
          break;
        case 'Low':
          newLowPriorityCount++;
          break;
      }
    }

    // Only update if counts actually changed
    if (_allPriorityCount != newAllPriorityCount || 
        _highPriorityCount != newHighPriorityCount || 
        _mediumPriorityCount != newMediumPriorityCount || 
        _lowPriorityCount != newLowPriorityCount) {
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _allPriorityCount = newAllPriorityCount;
            _highPriorityCount = newHighPriorityCount;
            _mediumPriorityCount = newMediumPriorityCount;
            _lowPriorityCount = newLowPriorityCount;
          });
        }
      });
    }
  }

  // Update work order status counts for approved items
  void _updateWorkOrderStatusCounts(List<QueryDocumentSnapshot> approvedDocs) {
    final newApprovedAllCount = approvedDocs.length;
    int newApprovedOpenCount = 0;
    int newApprovedInProgressCount = 0;
    int newApprovedCompletedCount = 0;

    for (var doc in approvedDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'] ?? 'Open';
      switch (status) {
        case 'Open':
          newApprovedOpenCount++;
          break;
        case 'In Progress':
          newApprovedInProgressCount++;
          break;
        case 'Completed':
          newApprovedCompletedCount++;
          break;
      }
    }

    // Only update if counts actually changed
    if (_approvedAllCount != newApprovedAllCount || 
        _approvedOpenCount != newApprovedOpenCount || 
        _approvedInProgressCount != newApprovedInProgressCount || 
        _approvedCompletedCount != newApprovedCompletedCount) {
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _approvedAllCount = newApprovedAllCount;
            _approvedOpenCount = newApprovedOpenCount;
            _approvedInProgressCount = newApprovedInProgressCount;
            _approvedCompletedCount = newApprovedCompletedCount;
          });
        }
      });
    }
  }

  // Get filtered work orders from cached data
  List<QueryDocumentSnapshot> _getFilteredWorkOrders() {
    if (_isInApprovedSubView) {
      // Filter approved work orders by work order status
      final approvedDocs = _allWorkOrders.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['clientStatus'] == 'Approved';
      }).toList();
      
      if (_workOrderStatusFilter != 'All') {
        return approvedDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['status'] == _workOrderStatusFilter;
        }).toList();
      }
      return approvedDocs;
    } else if (_isClientStatusFilterMode && _statusFilter != 'All') {
      return _allWorkOrders.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final clientStatus = data['clientStatus'] ?? 'To be Reviewed';
        // Handle legacy "Declined" status by treating as "To be Reviewed"
        if (clientStatus == 'Declined' && _statusFilter == 'To be Reviewed') {
          return true;
        }
        return clientStatus == _statusFilter;
      }).toList();
    } else if (!_isClientStatusFilterMode && _priorityFilter != 'All') {
      return _allWorkOrders.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['priority'] == _priorityFilter;
      }).toList();
    }
    return _allWorkOrders;
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
      title: 'Work Orders',
      facilityId: widget.facilityId,
      currentRole: _currentRole,
      organization: _organization,
      floatingActionButton: _isJVAlmacisUser
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _showForm = !_showForm),
              backgroundColor: Colors.blueGrey[800],
              icon: Icon(_showForm ? Icons.close : Icons.add, color: Colors.white),
              label: Text(
                _showForm ? 'Cancel' : 'New Work Order',
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
          // Enhanced filter tabs with back navigation
          Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back button for approved sub-view
                if (_isInApprovedSubView) ...[
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _isInApprovedSubView = false;
                            _workOrderStatusFilter = 'All';
                          });
                        },
                        icon: const Icon(Icons.arrow_back, color: Colors.blueGrey),
                      ),
                      Text(
                        'Approved Work Orders by Status',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                          color: Colors.blueGrey[800],
                          fontSize: fontSizeSubtitle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildWorkOrderStatusTabBar(isMobile, isTablet),
                ] else ...[
                  // Main filter mode controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _isClientStatusFilterMode ? 'Filter by Client Status:' : 'Filter by Priority:',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                          color: Colors.blueGrey[800],
                          fontSize: fontSizeSubtitle,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isClientStatusFilterMode = !_isClientStatusFilterMode;
                            // Reset filters when switching modes
                            _statusFilter = 'All';
                            _priorityFilter = 'All';
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey[600],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.swap_horiz,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isClientStatusFilterMode ? 'Switch to Priority' : 'Switch to Status',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildResponsiveTabBar(isMobile, isTablet),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_showForm && _isJVAlmacisUser) _buildWorkOrderForm(padding, fontSizeTitle, fontSizeSubtitle),
          const SizedBox(height: 24),
          _buildWorkOrdersList(padding, fontSizeSubtitle, isMobile),
          const SizedBox(height: 80), // Padding to avoid overlap with FAB
        ],
      ),
    );
  }

  Widget _buildResponsiveTabBar(bool isMobile, bool isTablet) {
    if (_isClientStatusFilterMode) {
      // Client status filter tabs (removed declined)
      if (isMobile) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTabButton('All', _allCount, Colors.grey, 0, true),
              const SizedBox(width: 8),
              _buildTabButton('Approved', _approvedCount, Colors.green, 1, true),
              const SizedBox(width: 8),
              _buildTabButton('To be Reviewed', _toBeReviewedCount, Colors.orange, 2, true),
            ],
          ),
        );
      } else {
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _buildTabButton('All', _allCount, Colors.grey, 0, true),
            _buildTabButton('Approved', _approvedCount, Colors.green, 1, true),
            _buildTabButton('To be Reviewed', _toBeReviewedCount, Colors.orange, 2, true),
          ],
        );
      }
    } else {
      // Priority filter tabs
      if (isMobile) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTabButton('All', _allPriorityCount, Colors.grey, 0, false),
              const SizedBox(width: 8),
              _buildTabButton('High', _highPriorityCount, Colors.red, 1, false),
              const SizedBox(width: 8),
              _buildTabButton('Medium', _mediumPriorityCount, Colors.orange, 2, false),
              const SizedBox(width: 8),
              _buildTabButton('Low', _lowPriorityCount, Colors.green, 3, false),
            ],
          ),
        );
      } else {
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _buildTabButton('All', _allPriorityCount, Colors.grey, 0, false),
            _buildTabButton('High', _highPriorityCount, Colors.red, 1, false),
            _buildTabButton('Medium', _mediumPriorityCount, Colors.orange, 2, false),
            _buildTabButton('Low', _lowPriorityCount, Colors.green, 3, false),
          ],
        );
      }
    }
  }

  Widget _buildWorkOrderStatusTabBar(bool isMobile, bool isTablet) {
    if (isMobile) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildWorkOrderStatusTabButton('All', _approvedAllCount, Colors.grey, 0),
            const SizedBox(width: 8),
            _buildWorkOrderStatusTabButton('Open', _approvedOpenCount, Colors.blue, 1),
            const SizedBox(width: 8),
            _buildWorkOrderStatusTabButton('In Progress', _approvedInProgressCount, Colors.orange, 2),
            const SizedBox(width: 8),
            _buildWorkOrderStatusTabButton('Completed', _approvedCompletedCount, Colors.green, 3),
          ],
        ),
      );
    } else {
      return Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _buildWorkOrderStatusTabButton('All', _approvedAllCount, Colors.grey, 0),
          _buildWorkOrderStatusTabButton('Open', _approvedOpenCount, Colors.blue, 1),
          _buildWorkOrderStatusTabButton('In Progress', _approvedInProgressCount, Colors.orange, 2),
          _buildWorkOrderStatusTabButton('Completed', _approvedCompletedCount, Colors.green, 3),
        ],
      );
    }
  }

  Widget _buildTabButton(String label, int count, Color color, int index, bool isStatusMode) {
    final isSelected = isStatusMode 
        ? _statusFilter == (index == 0 ? 'All' : ['Approved', 'To be Reviewed'][index - 1])
        : _priorityFilter == (index == 0 ? 'All' : ['High', 'Medium', 'Low'][index - 1]);
    
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isStatusMode) {
            final newFilter = index == 0 ? 'All' : ['Approved', 'To be Reviewed'][index - 1];
            _statusFilter = newFilter;
            
            // Enter approved sub-view if Approved is selected
            if (newFilter == 'Approved') {
              _isInApprovedSubView = true;
              _workOrderStatusFilter = 'All';
            }
          } else {
            _priorityFilter = index == 0 ? 'All' : ['High', 'Medium', 'Low'][index - 1];
          }
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

  Widget _buildWorkOrderStatusTabButton(String label, int count, Color color, int index) {
    final statuses = ['All', 'Open', 'In Progress', 'Completed'];
    final isSelected = _workOrderStatusFilter == statuses[index];
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _workOrderStatusFilter = statuses[index];
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

  Widget _buildWorkOrdersList(double padding, double fontSizeSubtitle, bool isMobile) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Work_Orders')
          .where('facilityId', isEqualTo: widget.facilityId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _isLoading) {
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
                    'Error loading work orders',
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
        
        // Cache all work orders for better performance
        _allWorkOrders = snapshot.data!.docs;
        _isLoading = false;
        
        // Update counts based on all work orders (not filtered)
        if (_isClientStatusFilterMode) {
          _updateClientStatusCounts(_allWorkOrders);
        } else {
          _updatePriorityCounts(_allWorkOrders);
        }

        // Update work order status counts for approved items
        final approvedDocs = _allWorkOrders.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['clientStatus'] == 'Approved';
        }).toList();
        _updateWorkOrderStatusCounts(approvedDocs);

        // Get filtered work orders
        final filteredWorkOrders = _getFilteredWorkOrders();

        if (filteredWorkOrders.isEmpty) {
          String filterText;
          if (_isInApprovedSubView) {
            filterText = _workOrderStatusFilter == 'All' 
                ? 'No approved work orders found' 
                : 'No $_workOrderStatusFilter approved work orders';
          } else if (_isClientStatusFilterMode) {
            filterText = _statusFilter == 'All' 
                ? 'No work orders found' 
                : 'No $_statusFilter work orders';
          } else {
            filterText = _priorityFilter == 'All' 
                ? 'No work orders found' 
                : 'No $_priorityFilter priority work orders';
          }
          
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Icon(
                    Icons.work_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    filterText,
                    style: GoogleFonts.poppins(
                      fontSize: fontSizeSubtitle,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_isJVAlmacisUser) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Tap the + button to create your first work order',
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
          itemCount: filteredWorkOrders.length,
          itemBuilder: (context, index) {
            final data = filteredWorkOrders[index].data() as Map<String, dynamic>;
            final workOrder = WorkOrder.fromMap(data, filteredWorkOrders[index].id);
            return _buildWorkOrderCard(workOrder, fontSizeSubtitle, isMobile);
          },
        );
      },
    );
  }

  Widget _buildWorkOrderCard(WorkOrder workOrder, double fontSize, bool isMobile) {
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
                  backgroundColor: _getClientStatusColor(workOrder.clientStatus),
                  child: Icon(
                    _getClientStatusIcon(workOrder.clientStatus),
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
                        workOrder.title,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: Colors.blueGrey[900],
                          fontSize: fontSize,
                        ),
                      ),
                      Text(
                        'Priority: ${workOrder.priority} | Status: ${workOrder.status} | Created: ${workOrder.createdAt != null ? DateFormat.yMMMd().format(workOrder.createdAt!) : 'Unknown'}',
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
                    color: _getClientStatusColor(workOrder.clientStatus),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    workOrder.clientStatus,
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
            _buildDetailRow('Description', workOrder.description, fontSize, isMobile),
            
            // Show "Assigned To" and "Created By" only to JV Almacis users
            if (_isJVAlmacisUser) ...[
              // Use FutureBuilder to fetch username for Assigned To
              if (workOrder.assignedTo.isNotEmpty)
                FutureBuilder<String>(
                  future: _getUsernameFromCollection(workOrder.assignedTo),
                  builder: (context, snapshot) {
                    final displayName = snapshot.data ?? (workOrder.assignedToEmail.isNotEmpty ? workOrder.assignedToEmail : 'Loading...');
                    return _buildDetailRow('Assigned To', displayName, fontSize, isMobile);
                  },
                ),
              if (workOrder.assignedTo.isEmpty)
                _buildDetailRow('Assigned To', 'Unassigned', fontSize, isMobile),
              // Use FutureBuilder to fetch username for Created By
              FutureBuilder<String>(
                future: _getUsernameFromCollection(workOrder.createdBy),
                builder: (context, snapshot) {
                  final displayName = snapshot.data ?? (workOrder.createdByEmail.isNotEmpty ? workOrder.createdByEmail : 'Loading...');
                  return _buildDetailRow('Created By', displayName, fontSize, isMobile);
                },
              ),
            ],
            
            // Use FutureBuilder to fetch request title for Related Request (without ID)
            if (workOrder.requestId != null)
              FutureBuilder<String>(
                future: _getRequestTitleFromId(workOrder.requestId!),
                builder: (context, snapshot) {
                  final displayTitle = snapshot.data ?? 'Loading request...';
                  return _buildDetailRow('Related Request', displayTitle, fontSize, isMobile);
                },
              ),
            if (workOrder.clientNotes.isNotEmpty)
              _buildDetailRow('Client Notes', workOrder.clientNotes, fontSize, isMobile),
            if (workOrder.attachments.isNotEmpty)
              _buildAttachmentsSection(workOrder.attachments, fontSize),
            if (workOrder.history.isNotEmpty)
              _buildHistorySection(workOrder.history, fontSize),
            const SizedBox(height: 12),
            _buildActionButtons(workOrder, fontSize),
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

  Widget _buildHistorySection(List<Map<String, dynamic>> history, double fontSize) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'History:',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
              color: Colors.blueGrey[700],
              fontSize: fontSize,
            ),
          ),
          const SizedBox(height: 4),
          ...history.map((entry) => Container(
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
                      entry['action'] ?? 'Action',
                      style: GoogleFonts.poppins(fontSize: fontSize - 2, fontWeight: FontWeight.w500),
                    ),
                    // Show different history format based on user type
                    if (_isJVAlmacisUser) ...[
                      // JV Almacis users see full history with actors
                      FutureBuilder<String>(
                        future: entry['userId'] != null && entry['userId'] != 'system' 
                            ? _getUsernameFromCollection(entry['userId'])
                            : Future.value(entry['username'] ?? entry['userEmail'] ?? 'Unknown'),
                        builder: (context, snapshot) {
                          final displayName = snapshot.data ?? 'Loading...';
                          return Text(
                            'by $displayName at ${entry['timestamp'] != null ? DateFormat.yMMMd().format((entry['timestamp'] as Timestamp).toDate()) : 'Unknown date'}',
                            style: GoogleFonts.poppins(
                              fontSize: fontSize - 4,
                              color: Colors.grey[600],
                            ),
                          );
                        },
                      ),
                    ] else ...[
                      // Client users see only date without actor
                      Text(
                        'on ${entry['timestamp'] != null ? DateFormat.yMMMd().format((entry['timestamp'] as Timestamp).toDate()) : 'Unknown date'}',
                        style: GoogleFonts.poppins(
                          fontSize: fontSize - 4,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                    if (entry['notes'] != null && entry['notes'].isNotEmpty)
                      Text(
                        entry['notes'],
                        style: GoogleFonts.poppins(fontSize: fontSize - 3),
                      ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildActionButtons(WorkOrder workOrder, double fontSize) {
    if (_isAdminClient) {
      // Admin client gets only approve and review buttons (removed decline)
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Client Actions:',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey[800],
                fontSize: fontSize,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Current Status: ${workOrder.clientStatus}',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                color: _getClientStatusColor(workOrder.clientStatus),
                fontSize: fontSize - 1,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // REORDERED: Review button first, then Approve button
                _buildActionButton(
                  workOrder, 
                  'To be Reviewed', 
                  Icons.rate_review, 
                  Colors.orange[700]!, 
                  fontSize,
                  isCurrentStatus: workOrder.clientStatus == 'To be Reviewed',
                ),
                _buildActionButton(
                  workOrder, 
                  'Approved', 
                  Icons.check_circle, 
                  Colors.green[700]!, 
                  fontSize,
                  isCurrentStatus: workOrder.clientStatus == 'Approved',
                ),
              ],
            ),
          ],
        ),
      );
    } else if (_isJVAlmacisUser) {
      // JV Almacis users can update work order status with enhanced colorful dialog
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Work Order Actions:',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey[800],
                fontSize: fontSize,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Current Status: ${workOrder.status}',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                color: _getWorkOrderStatusColor(workOrder.status),
                fontSize: fontSize - 1,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildWorkOrderStatusButton(
                  workOrder, 
                  'Open', 
                  Icons.radio_button_unchecked, 
                  Colors.blue[700]!, 
                  fontSize,
                  isCurrentStatus: workOrder.status == 'Open',
                ),
                _buildWorkOrderStatusButton(
                  workOrder, 
                  'In Progress', 
                  Icons.hourglass_empty, 
                  Colors.orange[700]!, 
                  fontSize,
                  isCurrentStatus: workOrder.status == 'In Progress',
                ),
                _buildWorkOrderStatusButton(
                  workOrder, 
                  'Completed', 
                  Icons.check_circle, 
                  Colors.green[700]!, 
                  fontSize,
                  isCurrentStatus: workOrder.status == 'Completed',
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      // Client technicians can only view
      return const SizedBox.shrink();
    }
  }

  Widget _buildActionButton(
    WorkOrder workOrder, 
    String action, 
    IconData icon, 
    Color color, 
    double fontSize, {
    bool isCurrentStatus = false,
  }) {
    return ElevatedButton.icon(
      onPressed: isCurrentStatus ? null : () => _showEnhancedClientActionDialog(workOrder, action, fontSize),
      icon: Icon(icon, size: 16, color: Colors.white),
      label: Text(
        action == 'To be Reviewed' ? 'Review' : action == 'Approved' ? 'Approve' : action,
        style: GoogleFonts.poppins(
          fontSize: fontSize - 1,
          color: Colors.white,
          fontWeight: isCurrentStatus ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isCurrentStatus ? color.withValues(alpha: 0.5) : color,
        elevation: isCurrentStatus ? 1 : 3,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: isCurrentStatus 
            ? BorderSide(color: color, width: 2)
            : BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildWorkOrderStatusButton(
    WorkOrder workOrder, 
    String status, 
    IconData icon, 
    Color color, 
    double fontSize, {
    bool isCurrentStatus = false,
  }) {
    return ElevatedButton.icon(
      onPressed: isCurrentStatus ? null : () => _showEnhancedUpdateStatusDialog(workOrder, status, fontSize),
      icon: Icon(icon, size: 16, color: Colors.white),
      label: Text(
        status,
        style: GoogleFonts.poppins(
          fontSize: fontSize - 1,
          color: Colors.white,
          fontWeight: isCurrentStatus ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isCurrentStatus ? color.withValues(alpha: 0.5) : color,
        elevation: isCurrentStatus ? 1 : 3,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: isCurrentStatus 
            ? BorderSide(color: color, width: 2)
            : BorderSide.none,
        ),
      ),
    );
  }

  void _showEnhancedClientActionDialog(WorkOrder workOrder, String action, double fontSize) {
    final notesController = TextEditingController();
    
    // Pre-fill with existing notes if updating the same status
    if (workOrder.clientStatus == action && workOrder.clientNotes.isNotEmpty) {
      notesController.text = workOrder.clientNotes;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                action == 'Approved' ? Colors.green[700]! : Colors.orange[700]!,
                action == 'Approved' ? Colors.green[500]! : Colors.orange[500]!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              Icon(
                action == 'Approved' ? Icons.check_circle : Icons.rate_review,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${action == 'To be Reviewed' ? 'Review' : action == 'Approved' ? 'Approve' : action} Work Order',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold, 
                    fontSize: fontSize,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        titlePadding: EdgeInsets.zero,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current status indicator
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Text(
                      'Current Status: ',
                      style: GoogleFonts.poppins(
                        fontSize: fontSize - 1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getClientStatusColor(workOrder.clientStatus),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        workOrder.clientStatus,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: fontSize - 2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Action confirmation
              RichText(
                text: TextSpan(
                  style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.black87),
                  children: [
                    const TextSpan(text: 'Change status to '),
                    TextSpan(
                      text: action,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: action == 'Approved' ? Colors.green[700] : Colors.orange[700],
                      ),
                    ),
                    const TextSpan(text: '?'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Notes input
              TextFormField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: 'Comments (Optional)',
                  hintText: 'Add your comments about this ${action.toLowerCase()} action...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey[400]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: action == 'Approved' ? Colors.green : Colors.orange,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
                  prefixIcon: Icon(
                    Icons.comment,
                    color: Colors.grey[600],
                  ),
                ),
                style: GoogleFonts.poppins(fontSize: fontSize),
                maxLines: 4,
                minLines: 2,
              ),
              
              // Show previous notes if they exist
              if (workOrder.clientNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Previous Notes:',
                        style: GoogleFonts.poppins(
                          fontSize: fontSize - 2,
                          fontWeight: FontWeight.w500,
                          color: Colors.blue[800],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        workOrder.clientNotes,
                        style: GoogleFonts.poppins(
                          fontSize: fontSize - 2,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel', 
              style: GoogleFonts.poppins(
                fontSize: fontSize,
                color: Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _updateClientStatus(workOrder.id, action, notesController.text);
              Navigator.pop(context);
            },
            icon: Icon(
              action == 'Approved' ? Icons.check : Icons.rate_review,
              size: 16,
              color: Colors.white,
            ),
            label: Text(
              action == 'To be Reviewed' ? 'Review' : action == 'Approved' ? 'Approve' : action,
              style: GoogleFonts.poppins(
                color: Colors.white, 
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: action == 'Approved' ? Colors.green[700] : Colors.orange[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 3,
            ),
          ),
        ],
      ),
    );
  }

  void _showEnhancedUpdateStatusDialog(WorkOrder workOrder, String selectedStatus, double fontSize) {
    final notesController = TextEditingController();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blueGrey[700]!, Colors.blueGrey[500]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.work_outline,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Update Work Order Status',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold, 
                    fontSize: fontSize,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        titlePadding: EdgeInsets.zero,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current status indicator
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Text(
                      'Current Status: ',
                      style: GoogleFonts.poppins(
                        fontSize: fontSize - 1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getWorkOrderStatusColor(workOrder.status),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        workOrder.status,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: fontSize - 2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Action confirmation
              RichText(
                text: TextSpan(
                  style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.black87),
                  children: [
                    const TextSpan(text: 'Change status to '),
                    TextSpan(
                      text: selectedStatus,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: _getWorkOrderStatusColor(selectedStatus),
                      ),
                    ),
                    const TextSpan(text: '?'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Notes input
              TextFormField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: 'Notes (Optional)',
                  hintText: 'Add notes about this status update...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey[400]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.blueGrey[700]!, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
                  prefixIcon: Icon(
                    Icons.note_add,
                    color: Colors.grey[600],
                  ),
                ),
                style: GoogleFonts.poppins(fontSize: fontSize),
                maxLines: 3,
                minLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel', 
              style: GoogleFonts.poppins(
                fontSize: fontSize,
                color: Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _updateStatus(workOrder.id, selectedStatus, notesController.text);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.update, size: 16, color: Colors.white),
            label: Text(
              'Update',
              style: GoogleFonts.poppins(
                color: Colors.white, 
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _getWorkOrderStatusColor(selectedStatus),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 3,
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to get work order status colors
  Color _getWorkOrderStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Colors.blue[600]!;
      case 'in progress':
        return Colors.orange[600]!;
      case 'completed':
        return Colors.green[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  Color _getClientStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'to be reviewed':
        return Colors.orange;
      // Handle legacy "Declined" status
      case 'declined':
        return Colors.orange; 
      default:
        return Colors.grey;
    }
  }

  IconData _getClientStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Icons.check_circle;
      case 'to be reviewed':
        return Icons.rate_review;
      // Handle legacy "Declined" status
      case 'declined':
        return Icons.rate_review; 
      default:
        return Icons.help;
    }
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

  Widget _buildWorkOrderForm(double padding, double fontSizeTitle, double fontSizeSubtitle) {
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
                    'Create Work Order',
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
                        _buildRequestField(fontSizeSubtitle),
                        const SizedBox(height: 16),
                        _buildTextField(_titleController, 'Title', fontSizeSubtitle, validator: (value) => value!.isEmpty ? 'Enter a title' : null),
                        const SizedBox(height: 16),
                        _buildTextField(_descriptionController, 'Description', fontSizeSubtitle, maxLines: 3),
                        const SizedBox(height: 16),
                        _buildTechnicianField(fontSizeSubtitle),
                        const SizedBox(height: 16),
                        _buildDropdown('Priority', _priority, ['Low', 'Medium', 'High'], (value) => setState(() => _priority = value!), fontSizeSubtitle),
                        const SizedBox(height: 16),
                        _buildTextField(_notesController, 'Notes', fontSizeSubtitle, maxLines: 2),
                      ],
                    )
                  : Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildRequestField(fontSizeSubtitle)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildTextField(_titleController, 'Title', fontSizeSubtitle, validator: (value) => value!.isEmpty ? 'Enter a title' : null)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildTextField(_descriptionController, 'Description', fontSizeSubtitle, maxLines: 3)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildTechnicianField(fontSizeSubtitle)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildDropdown('Priority', _priority, ['Low', 'Medium', 'High'], (value) => setState(() => _priority = value!), fontSizeSubtitle)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildTextField(_notesController, 'Notes', fontSizeSubtitle, maxLines: 2)),
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
                      onPressed: _isSubmitting ? null : _addWorkOrder,
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
                              'Create Work Order',
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

  Widget _buildRequestField(double fontSize) {
    return TextFormField(
      controller: TextEditingController(text: _selectedRequestId != null ? "Selected Request" : ""),
      decoration: InputDecoration(
        labelText: 'Related Request (Optional)',
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
        hintText: 'Tap to select from open requests',
        hintStyle: GoogleFonts.poppins(color: Colors.grey),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedRequestId != null)
              IconButton(
                icon: Icon(Icons.visibility, color: Colors.blue[600]),
                onPressed: () => _showRequestDetails(_selectedRequestId!),
              ),
            Icon(Icons.assignment, color: Colors.blueGrey[600]),
          ],
        ),
      ),
      style: GoogleFonts.poppins(fontSize: fontSize),
      readOnly: true,
      onTap: () => _showRequestSelectionDialog(fontSize),
    );
  }

  Future<void> _showRequestSelectionDialog(double fontSize) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('Work_Requests')
        .where('facilityId', isEqualTo: widget.facilityId)
        .where('status', isEqualTo: 'Open')
        .orderBy('createdAt', descending: true)
        .get();

    if (snapshot.docs.isEmpty) {
      if (mounted) _showSnackBar('No open requests available.');
      return;
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select a Request', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: fontSize)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: snapshot.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.docs[index];
              final data = doc.data();
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(data['title'] ?? 'Untitled', style: GoogleFonts.poppins(fontSize: fontSize, fontWeight: FontWeight.w500)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (data['description'] ?? '').length > 100 
                            ? '${(data['description'] ?? '').substring(0, 100)}...' 
                            : (data['description'] ?? ''),
                        style: GoogleFonts.poppins(fontSize: fontSize - 2),
                      ),
                      Text(
                        'Priority: ${data['priority'] ?? 'Medium'} | Created: ${data['createdAt'] != null ? DateFormat.yMMMd().format((data['createdAt'] as Timestamp).toDate()) : 'Unknown'}',
                        style: GoogleFonts.poppins(fontSize: fontSize - 3, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.visibility, color: Colors.blue[600]),
                        onPressed: () => _showRequestDetails(doc.id),
                      ),
                      IconButton(
                        icon: Icon(Icons.check, color: Colors.green[600]),
                        onPressed: () {
                          setState(() {
                            _selectedRequestId = doc.id;
                            _titleController.text = data['title'] ?? '';
                            _descriptionController.text = data['description'] ?? '';
                            _priority = data['priority'] ?? 'Medium';
                          });
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                  isThreeLine: true,
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: GoogleFonts.poppins(fontSize: fontSize)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showRequestDetails(String requestId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Work_Requests')
          .doc(requestId)
          .get();
      if (!doc.exists) {
        _showSnackBar('Request not found');
        return;
      }

      final data = doc.data() as Map<String, dynamic>;

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Request Details', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDetailRow('Title', data['title'] ?? 'Untitled', 14, false),
                  _buildDetailRow('Description', data['description'] ?? '', 14, false),
                  _buildDetailRow('Priority', data['priority'] ?? 'Medium', 14, false),
                  _buildDetailRow('Status', data['status'] ?? 'Open', 14, false),
                  FutureBuilder<String>(
                    future: _getUsernameFromCollection(data['createdBy'] ?? ''),
                    builder: (context, snapshot) {
                      final displayName = snapshot.data ?? (data['createdByEmail'] ?? 'Loading...');
                      return _buildDetailRow('Created By', displayName, 14, false);
                    },
                  ),
                  _buildDetailRow('Created', data['createdAt'] != null ? DateFormat.yMMMd().format((data['createdAt'] as Timestamp).toDate()) : 'Unknown', 14, false),
                  if (data['attachments'] != null && (data['attachments'] as List).isNotEmpty)
                    _buildAttachmentsSection(List<Map<String, String>>.from((data['attachments'] as List).map((item) => Map<String, String>.from(item))), 14),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              child: Text('Close', style: GoogleFonts.poppins()),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    } catch (e) {
      _logger.e('Error showing request details: $e');
      _showSnackBar('Error loading request details');
    }
  }

  Widget _buildTechnicianField(double fontSize) {
    return TextFormField(
      controller: TextEditingController(
        text: _selectedTechnicianEmail != null
            ? _selectedTechnicianEmail!
            : ""
      ),
      decoration: InputDecoration(
        labelText: 'Assign To (Optional)',
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
        hintText: 'Select JV Almacis technician',
        hintStyle: GoogleFonts.poppins(color: Colors.grey),
        suffixIcon: Icon(Icons.person, color: Colors.blueGrey[600]),
      ),
      style: GoogleFonts.poppins(fontSize: fontSize),
      readOnly: true,
      onTap: () => _showTechnicianSelectionDialog(fontSize),
    );
  }

  Future<void> _showTechnicianSelectionDialog(double fontSize) async {
    try {
      // Get JV Almacis technicians from multiple collections with proper deduplication
      final Map<String, Map<String, dynamic>> uniqueTechnicians = {};
      
      // Get from Technicians collection
      final techSnapshot = await FirebaseFirestore.instance
          .collection('Technicians')
          .where('organization', isEqualTo: 'JV Almacis')
          .get();
      
      for (var doc in techSnapshot.docs) {
        final data = doc.data();
        final email = data['email'];
        if (email != null && email.isNotEmpty) {
          uniqueTechnicians[email] = {
            'id': doc.id,
            'email': email,
            'username': data['username'] ?? data['name'] ?? data['displayName'] ?? 'Unknown User',
            'source': 'Technicians'
          };
        }
      }
      
      // Get from Developers collection (they are JV Almacis by default)
      final devSnapshot = await FirebaseFirestore.instance
          .collection('Developers')
          .get();
      
      for (var doc in devSnapshot.docs) {
        final data = doc.data();
        final email = data['email'];
        if (email != null && email.isNotEmpty) {
          // Only add if not already present (avoid duplicates)
          if (!uniqueTechnicians.containsKey(email)) {
            uniqueTechnicians[email] = {
              'id': doc.id,
              'email': email,
              'username': data['username'] ?? data['name'] ?? data['displayName'] ?? 'Developer',
              'source': 'Developers'
            };
          }
        }
      }

      // Get from Users collection where role is Technician and organization is JV Almacis
      final userSnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('role', isEqualTo: 'Technician')
          .where('organization', isEqualTo: 'JV Almacis')
          .get();
      
      for (var doc in userSnapshot.docs) {
        final data = doc.data();
        final email = data['email'];
        if (email != null && email.isNotEmpty) {
          // Only add if not already present (avoid duplicates)
          if (!uniqueTechnicians.containsKey(email)) {
            uniqueTechnicians[email] = {
              'id': doc.id,
              'email': email,
              'username': data['username'] ?? data['name'] ?? data['displayName'] ?? 'User',
              'source': 'Users'
            };
          }
        }
      }

      final techniciansList = uniqueTechnicians.values.toList();

      if (techniciansList.isEmpty) {
        if (mounted) _showSnackBar('No JV Almacis technicians available.');
        return;
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Select a Technician', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: fontSize)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: techniciansList.length,
              itemBuilder: (context, index) {
                final technician = techniciansList[index];
                final email = technician['email'] ?? 'Unknown Email';
                final username = technician['username'] ?? 'Unknown User';
                final source = technician['source'] ?? '';
                
                return ListTile(
                  title: Text(username, style: GoogleFonts.poppins(fontSize: fontSize, fontWeight: FontWeight.w500)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(email, style: GoogleFonts.poppins(fontSize: fontSize - 2)),
                      Text('Source: $source', style: GoogleFonts.poppins(fontSize: fontSize - 3, color: Colors.grey[600])),
                    ],
                  ),
                  onTap: () {
                    setState(() {
                      _selectedTechnicianId = technician['id'];
                      _selectedTechnicianEmail = email;
                    });
                    Navigator.pop(context);
                  },
                  isThreeLine: true,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              child: Text('Cancel', style: GoogleFonts.poppins(fontSize: fontSize)),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    } catch (e) {
      _logger.e('Error loading technicians: $e');
      if (mounted) _showSnackBar('Error loading technicians');
    }
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