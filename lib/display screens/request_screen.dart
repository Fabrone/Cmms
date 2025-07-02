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
  String _priorityFilter = 'All';
  bool _isStatusFilterMode = true;
  final List<Map<String, String>> _attachmentUrls = [];
  bool _showForm = false;
  String _currentRole = 'User';
  String _organization = '-';
  bool _isClient = false;
  String? _createdByEmail;
  String? _createdByUsername;
  double? _uploadProgress;
  late TabController _tabController;
  bool _isSubmitting = false;

  // Status counts for tabs - Fixed to maintain counts during filtering
  int _allCount = 0;
  int _openCount = 0;
  int _inProgressCount = 0;
  int _closedCount = 0;

  // Priority counts for tabs
  int _allPriorityCount = 0;
  int _highPriorityCount = 0;
  int _mediumPriorityCount = 0;
  int _lowPriorityCount = 0;

  // Cache for all requests to avoid repeated queries
  List<QueryDocumentSnapshot> _allRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _getCurrentUserInfo();
    _setupAutomaticStatusUpdates();
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
      String? username;
      bool isClient = false;

      if (adminDoc.exists) {
        newRole = 'Admin';
        final data = adminDoc.data()!;
        newOrg = data['organization'] ?? '-';
        username = data['username'] ?? data['name'] ?? data['displayName'];
      } else if (developerDoc.exists) {
        newRole = 'Technician';
        newOrg = 'JV Almacis';
        final data = developerDoc.data()!;
        username = data['username'] ?? data['name'] ?? data['displayName'];
      } else if (technicianDoc.exists) {
        newRole = 'Technician';
        final data = technicianDoc.data()!;
        newOrg = data['organization'] ?? '-';
        username = data['username'] ?? data['name'] ?? data['displayName'];
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
      }

      // Determine if user is client (organization != 'JV Almacis')
      isClient = newOrg != 'JV Almacis';

      if (mounted) {
        setState(() {
          _currentRole = newRole;
          _organization = newOrg;
          _isClient = isClient;
          _createdByEmail = email;
          _createdByUsername = username;
        });
        _logger.i('Updated client status for Work Requests: isClient=$isClient, org=$newOrg, username=$username');
      }
    } catch (e) {
      _logger.e('Error getting user info: $e');
    }
  }

  // Add this method after _getCurrentUserInfo()
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

  // Enhanced automatic status update system
  void _setupAutomaticStatusUpdates() {
    // Listen to work orders changes to update request statuses
    FirebaseFirestore.instance
        .collection('Work_Orders')
        .where('facilityId', isEqualTo: widget.facilityId)
        .snapshots()
        .listen((snapshot) {
      _processWorkOrderChanges(snapshot);
    });

    // Also listen to requests to update statuses based on work order existence
    FirebaseFirestore.instance
        .collection('Work_Requests')
        .where('facilityId', isEqualTo: widget.facilityId)
        .snapshots()
        .listen((snapshot) {
      _processRequestStatusUpdates(snapshot);
    });
  }

  Future<void> _processWorkOrderChanges(QuerySnapshot workOrderSnapshot) async {
    for (var change in workOrderSnapshot.docChanges) {
      if (change.type == DocumentChangeType.modified || change.type == DocumentChangeType.added) {
        final data = change.doc.data() as Map<String, dynamic>;
        final workOrderStatus = data['status'];
        final requestId = data['requestId'];
        
        if (requestId != null) {
          await _updateRequestStatusBasedOnWorkOrder(requestId, workOrderStatus);
        }
      }
    }
  }

  Future<void> _processRequestStatusUpdates(QuerySnapshot requestSnapshot) async {
    for (var doc in requestSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final requestId = doc.id;
      final workOrderIds = List<String>.from(data['workOrderIds'] ?? []);
      
      await _updateRequestStatusBasedOnWorkOrders(requestId, workOrderIds);
    }
  }

  Future<void> _updateRequestStatusBasedOnWorkOrder(String requestId, String workOrderStatus) async {
  try {
    String newRequestStatus;
    
    switch (workOrderStatus) {
      case 'Completed':
        newRequestStatus = 'Closed';
        break;
      case 'Open':
      case 'In Progress':
        newRequestStatus = 'In Progress';
        break;
      default:
        return; // Don't update for other statuses
    }

    // Update status ONLY - no comments added
    await FirebaseFirestore.instance
        .collection('Work_Requests')
        .doc(requestId)
        .update({'status': newRequestStatus});
    
    _logger.i('Request $requestId status updated to $newRequestStatus based on work order status: $workOrderStatus');
  } catch (e) {
    _logger.e('Error updating request status: $e');
  }
}

  Future<void> _updateRequestStatusBasedOnWorkOrders(String requestId, List<String> workOrderIds) async {
    try {
      String newStatus;
      
      if (workOrderIds.isEmpty) {
        newStatus = 'Open';
      } else {
        // Check work order statuses
        final workOrdersQuery = await FirebaseFirestore.instance
            .collection('Work_Orders')
            .where('requestId', isEqualTo: requestId)
            .get();
        
        if (workOrdersQuery.docs.isEmpty) {
          newStatus = 'Open';
        } else {
          bool hasCompleted = false;
          bool hasInProgress = false;
          
          for (var doc in workOrdersQuery.docs) {
            final status = doc.data()['status'] ?? 'Open';
            if (status == 'Completed') {
              hasCompleted = true;
            } else if (status == 'In Progress' || status == 'Open') {
              hasInProgress = true;
            }
          }
          
          if (hasCompleted && !hasInProgress) {
            newStatus = 'Closed';
          } else if (hasInProgress || hasCompleted) {
            newStatus = 'In Progress';
          } else {
            newStatus = 'Open';
          }
        }
      }

      // Only update if status actually changed
      final currentDoc = await FirebaseFirestore.instance
          .collection('Work_Requests')
          .doc(requestId)
          .get();
      
      if (currentDoc.exists) {
        final currentStatus = currentDoc.data()?['status'] ?? 'Open';
        if (currentStatus != newStatus) {
          await FirebaseFirestore.instance
              .collection('Work_Requests')
              .doc(requestId)
              .update({'status': newStatus});
          
          _logger.i('Request $requestId status updated to $newStatus');
        }
      }
    } catch (e) {
      _logger.e('Error updating request status based on work orders: $e');
    }
  }

  Future<void> _addRequest() async {
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
          status: 'Open', // Always start as Open
          priority: _priority,
          createdAt: DateTime.now(),
          createdBy: user.uid,
          createdByEmail: _createdByEmail,
          createdByUsername: _createdByUsername,
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
                'username': _createdByUsername ?? _createdByEmail ?? 'Unknown User',
              }
          ],
          workOrderIds: [],
          clientStatus: 'Pending',
        );

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

  // Fixed: Update status counts from all requests, not filtered ones
  void _updateStatusCounts(List<QueryDocumentSnapshot> allDocs) {
    final newAllCount = allDocs.length;
    int newOpenCount = 0;
    int newInProgressCount = 0;
    int newClosedCount = 0;

    for (var doc in allDocs) {
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

  // Update priority counts from all requests, not filtered ones
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

  // Get filtered requests from cached data
  List<QueryDocumentSnapshot> _getFilteredRequests() {
    if (_isStatusFilterMode && _statusFilter != 'All') {
      return _allRequests.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['status'] == _statusFilter;
      }).toList();
    } else if (!_isStatusFilterMode && _priorityFilter != 'All') {
      return _allRequests.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['priority'] == _priorityFilter;
      }).toList();
    }
    return _allRequests;
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
          // Filter tabs with toggle switch
          Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isStatusFilterMode ? 'Filter by Status:' : 'Filter by Priority:',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w500,
                        color: Colors.blueGrey[800],
                        fontSize: fontSizeSubtitle,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isStatusFilterMode = !_isStatusFilterMode;
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
                            Icon(
                              _isStatusFilterMode ? Icons.swap_horiz : Icons.swap_horiz,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isStatusFilterMode ? 'Switch to Priority' : 'Switch to Status',
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
    if (_isStatusFilterMode) {
      // Status filter tabs
      if (isMobile) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTabButton('All', _allCount, Colors.grey, 0, true),
              const SizedBox(width: 8),
              _buildTabButton('Open', _openCount, Colors.blue, 1, true),
              const SizedBox(width: 8),
              _buildTabButton('In Progress', _inProgressCount, Colors.orange, 2, true),
              const SizedBox(width: 8),
              _buildTabButton('Closed', _closedCount, Colors.green, 3, true),
            ],
          ),
        );
      } else {
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _buildTabButton('All', _allCount, Colors.grey, 0, true),
            _buildTabButton('Open', _openCount, Colors.blue, 1, true),
            _buildTabButton('In Progress', _inProgressCount, Colors.orange, 2, true),
            _buildTabButton('Closed', _closedCount, Colors.green, 3, true),
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

  Widget _buildTabButton(String label, int count, Color color, int index, bool isStatusMode) {
    final isSelected = isStatusMode 
        ? _statusFilter == (index == 0 ? 'All' : ['Open', 'In Progress', 'Closed'][index - 1])
        : _priorityFilter == (index == 0 ? 'All' : ['High', 'Medium', 'Low'][index - 1]);
    
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isStatusMode) {
            _statusFilter = index == 0 ? 'All' : ['Open', 'In Progress', 'Closed'][index - 1];
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

  Widget _buildRequestsList(double padding, double fontSizeSubtitle, bool isMobile) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Work_Requests')
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
        
        // Cache all requests for better performance
        _allRequests = snapshot.data!.docs;
        _isLoading = false;
        
        // Update counts based on all requests (not filtered)
        if (_isStatusFilterMode) {
          _updateStatusCounts(_allRequests);
        } else {
          _updatePriorityCounts(_allRequests);
        }

        // Get filtered requests
        final filteredRequests = _getFilteredRequests();

        if (filteredRequests.isEmpty) {
          final filterText = _isStatusFilterMode 
              ? (_statusFilter == 'All' ? 'No requests found' : 'No $_statusFilter requests')
              : (_priorityFilter == 'All' ? 'No requests found' : 'No $_priorityFilter priority requests');
          
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
                    filterText,
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
          itemCount: filteredRequests.length,
          itemBuilder: (context, index) {
            final data = filteredRequests[index].data() as Map<String, dynamic>;
            final request = Request.fromMap(data, filteredRequests[index].id);
            return _buildRequestCard(request, fontSizeSubtitle, isMobile);
          },
        );
      },
    );
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
          // Use FutureBuilder to fetch username from Users collection
          FutureBuilder<String>(
            future: _getUsernameFromCollection(request.createdBy),
            builder: (context, snapshot) {
              final displayName = snapshot.data ?? (request.createdByEmail ?? 'Loading...');
              return _buildDetailRow('Created By', displayName, fontSize, isMobile);
            },
          ),
          if (request.attachments.isNotEmpty)
            _buildAttachmentsSection(request.attachments, fontSize),
          _buildCommentsSection(request.comments, fontSize),
          if (request.workOrderIds.isNotEmpty)
            _buildWorkOrdersSection(request.workOrderIds, fontSize),
          const SizedBox(height: 12),
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
                  // Use FutureBuilder to fetch username for each comment
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
