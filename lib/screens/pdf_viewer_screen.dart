import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:cmms/services/pdf_service.dart';
import 'package:logger/logger.dart';
import 'package:google_fonts/google_fonts.dart';

class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({super.key});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfService _pdfService = PdfService();
  final Logger _logger = Logger();
  String? _pdfPath;
  String? _pdfUrl;
  String _title = 'PDF Viewer';
  bool _isLoading = true;
  String? _errorMessage;
  bool _hasLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasLoaded) {
      _hasLoaded = true;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _pdfUrl = args['url'] as String?;
      _title = args['title'] as String? ?? 'PDF Viewer';
    }

    if (_pdfUrl == null || _pdfUrl!.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No valid PDF URL provided';
      });
      _logger.e('No valid PDF URL provided');
      return;
    }

    await _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      _logger.i('Loading PDF from URL: $_pdfUrl');
      final file = await _pdfService.downloadPdf(_pdfUrl!);
      if (mounted) {
        setState(() {
          _pdfPath = file.path;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      _logger.e('Error loading PDF: $e', stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error loading PDF: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _title,
          style: GoogleFonts.poppins(
            fontSize: isMobile ? 18 : 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.grey[900],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_errorMessage != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.poppins(
                      fontSize: isMobile ? 14 : 16,
                      color: Colors.red,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else if (_pdfPath != null)
              PDFView(
                filePath: _pdfPath!,
                enableSwipe: true,
                swipeHorizontal: false,
                autoSpacing: true,
                pageFling: true,
                onError: (error) {
                  _logger.e('PDFView error: $error');
                  if (mounted) {
                    setState(() {
                      _errorMessage = 'Error rendering PDF: $error';
                    });
                  }
                },
                onRender: (pages) {
                  _logger.i('PDF rendered with $pages pages');
                },
              )
            else
              Center(
                child: Text(
                  'No PDF available',
                  style: GoogleFonts.poppins(
                    fontSize: isMobile ? 14 : 16,
                  ),
                ),
              ),
            if (_errorMessage != null)
              Positioned(
                bottom: 16,
                right: 16,
                child: FloatingActionButton(
                  onPressed: () {
                    setState(() {
                      _errorMessage = null;
                      _isLoading = true;
                    });
                    _loadPdf();
                  },
                  child: const Icon(Icons.refresh),
                ),
              ),
          ],
        ),
      ),
    );
  }
}