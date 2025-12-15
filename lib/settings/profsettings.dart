import 'dart:ui';

import 'package:capstone_app/ui/theme/branding.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:capstone_app/profile/dayung_profile.dart';
import 'package:photo_view/photo_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfSettingsPage extends StatefulWidget {
  const ProfSettingsPage({super.key});

  @override
  State<ProfSettingsPage> createState() => _ProfSettingsPageState();
}

class _ProfSettingsPageState extends State<ProfSettingsPage> {
  final supabase = Supabase.instance.client;
  String? birthCertificateUrl;
  String? marriageCertificateUrl;
  bool loading = true;
  bool _uploadingImage = false;

  @override
  void initState() {
    super.initState();
    _fetchCertificates();
  }

  void _showTopPopup(
    String message, {
    Color color = kAccent,
    IconData icon = Icons.check_circle,
  }) {
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    late OverlayEntry entry;
    final animationController = AnimationController(
      vsync: Navigator.of(context),
      duration: const Duration(milliseconds: 350),
    );
    final curved = CurvedAnimation(
      parent: animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 24,
        right: 24,
        child: AnimatedBuilder(
          animation: curved,
          builder: (context, child) {
            return Opacity(
              opacity: curved.value,
              child: Transform.translate(
                offset: Offset(0, -40 * (1 - curved.value)),
                child: child,
              ),
            );
          },
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.38),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.18),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    animationController.forward();

    Future.delayed(const Duration(seconds: 5), () async {
      await animationController.reverse();
      entry.remove();
      animationController.dispose();
    });
  }

  Future<void> _fetchCertificates() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final response = await supabase
        .from('users')
        .select('birth_certificate_url, marriage_certificate_url')
        .eq('id', userId)
        .maybeSingle();
    if (!mounted) return;
    setState(() {
      birthCertificateUrl = response?['birth_certificate_url'] as String?;
      marriageCertificateUrl = response?['marriage_certificate_url'] as String?;
      loading = false;
    });
  }

  Future<void> _uploadCertificate({required String type}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null) return;

    final file = result.files.first;
    final bytes = file.bytes;
    final ext = file.extension ?? 'pdf';
    if (bytes == null) return;

    setState(() => _uploadingImage = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      final fileName = '$userId-${type}_certificate.${ext.toLowerCase()}';

      final bucket = type == 'birth'
          ? 'birth_certificates'
          : 'marriage_certificates';

      await supabase.storage
          .from(bucket)
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl = supabase.storage.from(bucket).getPublicUrl(fileName);

      await supabase
          .from('users')
          .update({
            if (type == 'birth') 'birth_certificate_url': publicUrl,
            if (type == 'marriage') 'marriage_certificate_url': publicUrl,
          })
          .eq('id', userId)
          .select()
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        if (type == 'birth') birthCertificateUrl = publicUrl;
        if (type == 'marriage') marriageCertificateUrl = publicUrl;
        _uploadingImage = false;
      });
      _showTopPopup(
        '${type[0].toUpperCase()}${type.substring(1)} certificate uploaded!',
        color: kAccent,
        icon: Icons.check_circle,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      _showTopPopup(
        'Upload error: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    }
    await _fetchCertificates();
  }

  void _openCertificate(String? url) {
    if (url == null || url.isEmpty) return;

    if (url.endsWith('.pdf')) {
      // For PDF, open in browser
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }

    // For images, show zoomable dialog
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          height: 400,
          child: Stack(
            children: [
              PhotoView(
                imageProvider: NetworkImage(url),
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeCard = Colors.white;
    final themeText = const Color(0xFF111827);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Settings'),
        backgroundColor: const Color(0xFF1E40AF),
      ),
      backgroundColor: const Color(0xFFF8FAFC),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Certificates',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: themeText,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: themeCard,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      _certificateRow(
                        label: 'Birth Certificate',
                        url: birthCertificateUrl,
                        onUpload: () => _uploadCertificate(type: 'birth'),
                        onView: () => _openCertificate(birthCertificateUrl),
                        labelColor: themeText,
                      ),
                      const SizedBox(height: 8),
                      _certificateRow(
                        label: 'Marriage Certificate',
                        url: marriageCertificateUrl,
                        onUpload: () => _uploadCertificate(type: 'marriage'),
                        onView: () => _openCertificate(marriageCertificateUrl),
                        labelColor: themeText,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: themeCard,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DayungProfile(),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E40AF).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.home_rounded,
                            color: Color(0xFF1E40AF),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Manage Dayung',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: themeText,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'View current Dayung, apply or change',
                                style: TextStyle(
                                  color: themeText.withOpacity(0.7),
                                  fontSize: 12,
                                  fontFamily: 'OpenSans',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF1E40AF),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _certificateRow({
    required String label,
    required String? url,
    required VoidCallback onUpload,
    required VoidCallback onView,
    required Color labelColor,
  }) {
    return Row(
      children: [
        Icon(
          url != null && url.isNotEmpty
              ? Icons.check_circle
              : Icons.warning_amber_rounded,
          color: url != null && url.isNotEmpty ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
        ),
        if (url != null && url.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.open_in_new, color: Color(0xFF059669)),
            tooltip: 'View',
            onPressed: onView,
          )
        else
          ElevatedButton.icon(
            icon: const Icon(Icons.upload_file),
            label: const Text('Add'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onUpload,
          ),
      ],
    );
  }
}
