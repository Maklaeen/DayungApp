import 'dart:ui';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:capstone_app/profile/dayung_profile.dart';
import 'package:photo_view/photo_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Color palette
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);
const kPrimary = Color(0xFF0D47A1);
const kSuccess = Color(0xFF059669);
const kWarn = Color(0xFFF57C00);

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
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }

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
    final themeText = kText;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Curved Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 36, 20, 28),
              decoration: const BoxDecoration(
                color: kAccent,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: kAccent,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Profile Settings',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFamily: 'Montserrat',
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Certificates Card
            Card(
              elevation: 3,
              color: themeCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Certificates',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: kText,
                      ),
                    ),
                    const SizedBox(height: 12),
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
                    if (_uploadingImage)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Center(
                          child: CircularProgressIndicator(color: kAccent),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Manage Dayung Card
            Card(
              elevation: 3,
              color: themeCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DayungProfile()),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: kAccent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.home_rounded,
                          color: kAccent,
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
                        color: kAccent,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
          color: url != null && url.isNotEmpty ? kSuccess : kWarn,
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
            icon: const Icon(Icons.open_in_new, color: kSuccess),
            tooltip: 'View',
            onPressed: onView,
          )
        else
          ElevatedButton.icon(
            icon: const Icon(Icons.upload_file),
            label: const Text('Add'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kSuccess,
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
