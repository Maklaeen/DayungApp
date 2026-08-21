import 'dart:ui';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:capstone_app/profile/dayung_profile.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:capstone_app/utils/supabase_storage.dart';
import 'package:photo_view/photo_view.dart';
import 'package:http/http.dart' as http;
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
const kCardBg = Color(0xFFFFFFFF);
const kBorder = Color(0xFFE5E7EB);
const kSoftBg = Color(0xFFF8FAFC);

class ProfSettingsPage extends StatefulWidget {
  final VoidCallback? onBack;
  final bool showBackButton;

  const ProfSettingsPage({super.key, this.onBack, this.showBackButton = true});

  @override
  State<ProfSettingsPage> createState() => _ProfSettingsPageState();
}

class _ProfSettingsPageState extends State<ProfSettingsPage> {
  final supabase = Supabase.instance.client;
  String? birthCertificateUrl;
  String? marriageCertificateUrl;
  String? proofOfResidencyUrl;
  String? valididUrl;

  bool loading = true;
  bool _uploadingImage = false;

  ThemeData get _theme => Theme.of(context);
  ColorScheme get _colors => _theme.colorScheme;
  bool get _isDark => _theme.brightness == Brightness.dark;
  Color get _pageBackground => _theme.scaffoldBackgroundColor;
  Color get _cardColor => _isDark ? const Color(0xFF162033) : kCardBg;
  Color get _softColor => _isDark ? const Color(0xFF1B2435) : kSoftBg;
  Color get _borderColor =>
      _isDark ? _colors.outline.withValues(alpha: 0.34) : kBorder;
  Color get _textColor => _colors.onSurface;
  Color get _subTextColor => _colors.onSurfaceVariant;
  Color get _primaryColor => _colors.primary;
  Color get _successColor => _isDark ? const Color(0xFF34D399) : kSuccess;
  Color get _warnColor => _isDark ? const Color(0xFFFBBF24) : kWarn;

  int get _availableCertificateCount {
    var count = 0;
    for (final value in [
      birthCertificateUrl,
      marriageCertificateUrl,
      proofOfResidencyUrl,
      valididUrl,
    ]) {
      if (value != null && value.isNotEmpty) {
        count++;
      }
    }
    return count;
  }

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
                    color: color.withValues(alpha: 0.38),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.18),
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
        .select(
          'birth_certificate_url, marriage_certificate_url, proof_of_residency_url, valid_id',
        )
        .eq('id', userId)
        .maybeSingle();
    if (!mounted) return;
    setState(() {
      birthCertificateUrl = response?['birth_certificate_url'] as String?;
      marriageCertificateUrl = response?['marriage_certificate_url'] as String?;
      proofOfResidencyUrl = response?['proof_of_residency_url'] as String?;
      valididUrl = response?['valid_id'] as String?;
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

    final key = encrypt.Key.fromUtf8(
      'capstonedayungappjjm'.padRight(32).substring(0, 32),
    );
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encryptBytes(bytes, iv: iv);
    Uint8List encryptedBytes = Uint8List.fromList(iv.bytes + encrypted.bytes);

    setState(() => _uploadingImage = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      final fileName = '$userId-${type}_certificate.${ext.toLowerCase()}';

      String bucket;
      if (type == 'birth') {
        bucket = 'birth_certificates';
      } else if (type == 'marriage') {
        bucket = 'marriage_certificates';
      } else if (type == 'proof_of_residency') {
        bucket = 'proof_of_residency';
      } else if (type == 'valid_id') {
        bucket = 'valid_ids';
      } else {
        throw Exception('Unknown certificate type');
      }

      await supabase.storage
          .from(bucket)
          .uploadBinary(
            fileName,
            encryptedBytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final storageRef = buildStorageRef(bucket, fileName);

      await supabase
          .from('users')
          .update({
            if (type == 'birth') 'birth_certificate_url': storageRef,
            if (type == 'marriage') 'marriage_certificate_url': storageRef,
            if (type == 'proof_of_residency')
              'proof_of_residency_url': storageRef,
            if (type == 'valid_id') 'valid_id': storageRef,
          })
          .eq('id', userId)
          .select()
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        if (type == 'birth') birthCertificateUrl = storageRef;
        if (type == 'marriage') marriageCertificateUrl = storageRef;
        if (type == 'proof_of_residency') proofOfResidencyUrl = storageRef;
        if (type == 'valid_id') valididUrl = storageRef;
        _uploadingImage = false;
      });
      _showTopPopup(
        'Update image done',
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

  Future<void> _openCertificate(String? url) async {
    if (url == null || url.isEmpty) return;

    final resolved = await resolveSupabaseStorageUrl(url, client: supabase);
    if (resolved == null) return;
    if (!mounted) return;

    String displayUrl = resolved;
    if (!storageLooksLikePdf(resolved)) {
      final separator = resolved.contains('?') ? '&' : '?';
      displayUrl =
          '$resolved${separator}cb=${DateTime.now().millisecondsSinceEpoch}';
    }

    if (storageLooksLikePdf(resolved)) {
      launchUrl(Uri.parse(displayUrl), mode: LaunchMode.externalApplication);
      return;
    }

    // Download and decrypt the image before displaying
    try {
      final response = await http.get(Uri.parse(displayUrl));
      if (response.statusCode != 200) {
        _showTopPopup(
          'Failed to load image',
          color: kWarn,
          icon: Icons.error_outline,
        );
        return;
      }
      final encryptedBytes = response.bodyBytes;
      if (encryptedBytes.length < 16) {
        _showTopPopup(
          'Invalid encrypted image',
          color: kWarn,
          icon: Icons.error_outline,
        );
        return;
      }
      // Extract IV and ciphertext
      final ivBytes = encryptedBytes.sublist(0, 16);
      final cipherBytes = encryptedBytes.sublist(16);
      final key = encrypt.Key.fromUtf8(
        'capstonedayungappjjm'.padRight(32).substring(0, 32),
      );
      final iv = encrypt.IV(ivBytes);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final decryptedBytes = encrypter.decryptBytes(
        encrypt.Encrypted(cipherBytes),
        iv: iv,
      );

      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 64,
          ), // More padding
          child: AspectRatio(
            aspectRatio: 4 / 5, // Or use LayoutBuilder for more control
            child: Stack(
              children: [
                Positioned.fill(
                  child: PhotoView(
                    imageProvider: MemoryImage(
                      Uint8List.fromList(decryptedBytes),
                    ),
                    backgroundDecoration: const BoxDecoration(
                      color: Colors.black,
                    ),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 3,
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 32,
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    tooltip: 'Close',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      _showTopPopup(
        'Error displaying image: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;
    final titleStyle = TextStyle(
      fontSize: isWide ? 20 : 16,
      fontWeight: FontWeight.w700,
      fontFamily: 'Montserrat',
      color: _textColor,
    );
    final bodyStyle = TextStyle(
      fontSize: isWide ? 15 : 13,
      fontFamily: 'OpenSans',
      color: _subTextColor,
      height: 1.4,
    );

    return Scaffold(
      backgroundColor: _pageBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 28 : 18,
                  vertical: isWide ? 24 : 18,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _isDark ? const Color(0xFF1D4ED8) : kPrimary,
                      _isDark ? const Color(0xFF0F766E) : kSuccess,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: _isDark ? 0.28 : 0.08,
                      ),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (widget.showBackButton)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: IconButton(
                              onPressed:
                                  widget.onBack ?? () => Navigator.pop(context),
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        if (widget.showBackButton) const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Profile Settings',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: isWide ? 28 : 22,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              // const SizedBox(height: 4),
                              // Text(
                              //   'Manage certificates and update your Dayung access from one clean dashboard.',
                              //   style: TextStyle(
                              //     color: Colors.white.withValues(alpha: 0.9),
                              //     fontSize: isWide ? 14 : 12,
                              //     height: 1.4,
                              //     fontFamily: 'OpenSans',
                              //   ),
                              // ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.verified_user_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$_availableCertificateCount of 4 profile documents are currently available.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontSize: 12,
                                height: 1.4,
                                fontFamily: 'OpenSans',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _primaryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.folder_open_rounded,
                            color: _primaryColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Certificates', style: titleStyle),
                              // const SizedBox(height: 4),
                              // Text(
                              //   'Upload and review the documents needed for your membership profile.',
                              //   style: bodyStyle,
                              // ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _certificateRow(
                      label: 'Birth Certificate',
                      url: birthCertificateUrl,
                      onUpload: () => _uploadCertificate(type: 'birth'),
                      onView: () => _openCertificate(birthCertificateUrl),
                    ),
                    const SizedBox(height: 10),
                    _certificateRow(
                      label: 'Marriage Certificate',
                      url: marriageCertificateUrl,
                      onUpload: () => _uploadCertificate(type: 'marriage'),
                      onView: () => _openCertificate(marriageCertificateUrl),
                    ),
                    const SizedBox(height: 10),
                    _certificateRow(
                      label: 'Proof of Residency',
                      url: proofOfResidencyUrl,
                      onUpload: () =>
                          _uploadCertificate(type: 'proof_of_residency'),
                      onView: () => _openCertificate(proofOfResidencyUrl),
                    ),
                    const SizedBox(height: 10),
                    _certificateRow(
                      label: 'Valid ID',
                      url: valididUrl,
                      onUpload: () => _uploadCertificate(type: 'valid_id'),
                      onView: () => _openCertificate(valididUrl),
                    ),
                    if (_uploadingImage) ...[
                      const SizedBox(height: 14),
                      const ClipRRect(
                        borderRadius: BorderRadius.all(Radius.circular(99)),
                        child: LinearProgressIndicator(minHeight: 6),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 18),
              
              _buildSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _successColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.groups_rounded,
                            color: _successColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Manage Dayung', style: titleStyle),
                              // const SizedBox(height: 4),
                              // Text(
                              //   'Open your Dayung page to review your current unit, switch, or apply to another one.',
                              //   style: bodyStyle,
                              // ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // const SizedBox(height: 16),
                    // Container(
                    //   width: double.infinity,
                    //   padding: const EdgeInsets.all(14),
                    //   decoration: BoxDecoration(
                    //     color: _softColor,
                    //     borderRadius: BorderRadius.circular(16),
                    //     border: Border.all(color: _borderColor),
                    //   ),
                    //   child: Row(
                    //     children: [
                    //       Icon(Icons.swap_horiz_rounded, color: _primaryColor),
                    //       const SizedBox(width: 10),
                    //       Expanded(
                    //         child: Text(
                    //           'This section includes Change Dayung, recommendations, and map access.',
                    //           style: bodyStyle.copyWith(color: _textColor),
                    //         ),
                    //       ),
                    //     ],
                    //   ),
                    // ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DayungSettingsPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text('Open Dayung Settings'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.20 : 0.07),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _certificateRow({
    required String label,
    required String? url,
    required VoidCallback onUpload,
    required VoidCallback onView,
  }) {
    final hasFile = url != null && url.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _softColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (hasFile ? _successColor : _warnColor).withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hasFile
                      ? Icons.check_circle_rounded
                      : Icons.upload_file_rounded,
                  color: hasFile ? _successColor : _warnColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasFile
                          ? 'Document available and ready to review.'
                          : 'No document uploaded yet.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _subTextColor,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: (hasFile ? _successColor : _warnColor).withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  hasFile ? 'Uploaded' : 'Needed',
                  style: TextStyle(
                    color: hasFile ? _successColor : _warnColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (hasFile)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onView,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('View'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryColor,
                      minimumSize: const Size.fromHeight(46),
                      side: BorderSide(color: _borderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              if (hasFile) const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onUpload,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(hasFile ? 'Update' : 'Add File'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasFile ? _primaryColor : _successColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
