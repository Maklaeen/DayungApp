import 'dart:ui';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cupertino_calendar_picker/cupertino_calendar_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:capstone_app/utils/supabase_storage.dart';
import 'package:capstone_app/utils/input_safety.dart';
import 'dart:convert';

// Modern palette
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);
const kPrimary = Color(0xFF0D47A1);
const kWarn = Color(0xFFF57C00);
const kDanger = Color(0xFFC62828);
const kSuccess = Color(0xFF10B981);
const kCardBg = Color(0xFFFFFFFF);

class AddBeneficiaryPage extends StatefulWidget {
  const AddBeneficiaryPage({super.key});

  @override
  State<AddBeneficiaryPage> createState() => _AddBeneficiaryPageState();
}

class _AddBeneficiaryPageState extends State<AddBeneficiaryPage> {
  final TextEditingController fullNameController = TextEditingController();
  final user = Supabase.instance.client.auth.currentUser;
  final _formKey = GlobalKey<FormState>();

  bool _isSubmitting = false;
  bool _isUploadingFile = false;
  bool _isUploadingValidId = false;

  String? selectedRelationship;
  String? birthCertificateFile;
  String? validIdFile;
  String? selectedMaritalStatus;

  DateTime? _selectedDob;

  final List<String> _relationships = [
    'Spouse',
    'Child',
    'Parent',
    'Sibling',
    'Grandparent',
    'Grandchild',
    'Aunt/Uncle',
    'Niece/Nephew',
    'Cousin',
    'Other',
  ];

  final List<String> _maritalStatuses = [
    'Single',
    'Married',
    'Widowed',
    'Separated',
  ];

  @override
  void dispose() {
    fullNameController.dispose();
    super.dispose();
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

    Future.delayed(const Duration(seconds: 3), () async {
      await animationController.reverse();
      entry.remove();
      animationController.dispose();
    });
  }

  InputDecoration _dec(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: kSubText, fontSize: 14),
      prefixIcon: icon != null ? Icon(icon, color: kSubText, size: 18) : null,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kSubText, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kDanger, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kDanger, width: 1.5),
      ),
    );
  }

  InputDecoration _dropdownDec(String label) => _dec(label).copyWith(
    contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
  );

  Future<void> _showCalendarDialog(BuildContext context) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 120, 1, 1);
    final lastDate = now;
    final initialDate = _selectedDob ?? DateTime(now.year - 18, 1, 1);

    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        DateTime temp = initialDate;
        final size = MediaQuery.of(ctx).size;

        return SafeArea(
          child: CupertinoTheme(
            data: const CupertinoThemeData(
              brightness: Brightness.light,
              primaryColor: kAccent,
            ),
            child: SizedBox(
              height: size.height * 0.50,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: kDanger,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Select Date of Birth',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: kText,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, temp),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              color: kAccent,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: CupertinoCalendar(
                        minimumDateTime: firstDate,
                        maximumDateTime: lastDate,
                        initialDateTime: temp,
                        currentDateTime: _selectedDob ?? DateTime.now(),
                        mode: CupertinoCalendarMode.date,
                        onDateTimeChanged: (d) => temp = d,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDob = picked);
    }
  }

  Widget _dobField(BuildContext rootContext) {
    return GestureDetector(
      onTap: () => _showCalendarDialog(rootContext),
      child: AbsorbPointer(
        child: TextFormField(
          readOnly: true,
          style: const TextStyle(
            fontSize: 14,
            color: kText,
            fontWeight: FontWeight.w500,
          ),
          decoration: _dec(
            'Date of Birth',
            hint: 'YYYY-MM-DD',
            icon: Icons.calendar_today_rounded,
          ),
          controller: TextEditingController(
            text: _selectedDob == null
                ? ''
                : '${_selectedDob!.year}-${_selectedDob!.month.toString().padLeft(2, '0')}-${_selectedDob!.day.toString().padLeft(2, '0')}',
          ),
          validator: (v) =>
              _selectedDob == null ? 'Date of birth is required' : null,
        ),
      ),
    );
  }

  Future<void> _pickAndUploadFile() async {
    setState(() => _isUploadingFile = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) {
        setState(() => _isUploadingFile = false);
        return;
      }

      final file = result.files.single;
      final ext = (file.extension ?? 'jpg').toLowerCase();
      final fileName =
          '${user?.id}-${DateTime.now().millisecondsSinceEpoch}.$ext';
      final filePath = 'birth_certificates/$fileName';

      await Supabase.instance.client.storage
          .from('birth_certificates')
          .uploadBinary(
            filePath,
            file.bytes!,
            fileOptions: const FileOptions(upsert: true),
          );

      setState(() {
        birthCertificateFile = buildStorageRef('birth_certificates', filePath);
      });

      if (!mounted) return;
      _showTopPopup(
        'File uploaded successfully',
        color: kSuccess,
        icon: Icons.check_circle,
      );
    } catch (e) {
      if (!mounted) return;
      _showTopPopup(
        'File upload failed: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _isUploadingFile = false);
    }
  }

  Future<void> _pickAndUploadValidId() async {
    setState(() => _isUploadingValidId = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) {
        setState(() => _isUploadingValidId = false);
        return;
      }

      final file = result.files.single;
      final ext = (file.extension ?? 'jpg').toLowerCase();
      final fileName =
          '${user?.id}-${DateTime.now().millisecondsSinceEpoch}.$ext';
      final filePath = 'valid_ids/$fileName';

      await Supabase.instance.client.storage
          .from('valid_ids')
          .uploadBinary(
            filePath,
            file.bytes!,
            fileOptions: const FileOptions(upsert: true),
          );

      setState(() {
        validIdFile = buildStorageRef('valid_ids', filePath);
      });

      if (!mounted) return;
      _showTopPopup(
        'Valid ID uploaded successfully',
        color: kSuccess,
        icon: Icons.check_circle,
      );
    } catch (e) {
      if (!mounted) return;
      _showTopPopup(
        'Valid ID upload failed: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _isUploadingValidId = false);
    }
  }

  String _formatDob(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submitBeneficiary() async {
    if (!_formKey.currentState!.validate()) return;
    if (user == null) {
      _showTopPopup(
        'You must be logged in',
        color: kWarn,
        icon: Icons.error_outline,
      );
      return;
    }
    if (_selectedDob == null) {
      _showTopPopup(
        'Date of birth is required',
        color: kWarn,
        icon: Icons.error_outline,
      );
      return;
    }
    if (validIdFile == null) {
      _showTopPopup(
        'Valid ID is required',
        color: kWarn,
        icon: Icons.error_outline,
      );
      return;
    }
    int? unitFromPrefs;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('selectedDayungUnit');
      if (raw != null) {
        final map = Map<String, dynamic>.from(jsonDecode(raw));
        unitFromPrefs = map['id'] is int
            ? map['id'] as int
            : int.tryParse('${map['id']}');
      }
    } catch (_) {}

    final String? unitText = unitFromPrefs?.toString();
    setState(() => _isSubmitting = true);

    final fullName = AppInputSecurity.sanitizePlainText(
      fullNameController.text,
      maxLength: 120,
    );
    final maritalStatus = selectedMaritalStatus?.trim();
    final relationship = selectedRelationship!.trim();
    final dob = _formatDob(_selectedDob!);
    final birthCertificate = birthCertificateFile;

    try {
      final response = await Supabase.instance.client
          .from('beneficiaries')
          .insert([
            {
              'user_id': user!.id,
              'full_name': fullName,
              'dob': dob,
              'marital_status': maritalStatus,
              'relationship': relationship,
              'birth_certificate': birthCertificate,
              'valid_id': validIdFile,
              'status': 'Pending',
              'dayung_unit_id': unitText,
            },
          ])
          .select()
          .single();

      if (response['id'] == null) {
        _showTopPopup(
          'Failed to add beneficiary',
          color: kWarn,
          icon: Icons.error_outline,
        );
      } else {
        _showTopPopup(
          'Beneficiary added',
          color: kSuccess,
          icon: Icons.check_circle,
        );
        fullNameController.clear();
        setState(() {
          selectedRelationship = null;
          selectedMaritalStatus = null;
          _selectedDob = null;
          birthCertificateFile = null;
          validIdFile = null;
        });
        Navigator.pop(context);
      }
    } catch (e) {
      _showTopPopup('Error: $e', color: kWarn, icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 720;
    final isSmall = width < 350;

    return Scaffold(
      backgroundColor: kBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isSmall ? 16 : 24,
                vertical: isSmall ? 16 : 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 640 : 420),
                child: Column(
                  children: [
                    // Modern Curved Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.chevron_left,
                                  color: kAccent,
                                  size: 28,
                                ),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.person_add_rounded,
                                color: kAccent,
                                size: 32,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Add Beneficiary',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: kText,
                                    fontFamily: 'Montserrat',
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Provide beneficiary details below',
                              style: TextStyle(
                                color: kSubText,
                                fontSize: 16,
                                fontFamily: 'OpenSans',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Modern Card Form
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(isSmall ? 14 : 24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              if (_isSubmitting)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 20),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: kAccent.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const LinearProgressIndicator(
                                    color: kAccent,
                                    backgroundColor: Color(0xFFEFF2F7),
                                    minHeight: 4,
                                  ),
                                ),
                              TextFormField(
                                controller: fullNameController,
                                textInputAction: TextInputAction.next,
                                inputFormatters:
                                    AppInputSecurity.singleLineFormatters(
                                      maxLength: 120,
                                    ),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: kText,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: _dec(
                                  'Full Name',
                                  hint: 'e.g., Jane Doe',
                                  icon: Icons.badge_outlined,
                                ),
                                validator: (v) =>
                                    AppInputSecurity.validateSafeText(
                                      v,
                                      fieldName: 'Full Name',
                                      minLength: 2,
                                      maxLength: 120,
                                    ),
                              ),
                              const SizedBox(height: 14),
                              _dobField(context),
                              const SizedBox(height: 14),
                              DropdownButtonFormField2<String>(
                                isExpanded: true,
                                decoration: _dropdownDec('Relationship'),
                                value: selectedRelationship,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: kText,
                                  fontWeight: FontWeight.w500,
                                ),
                                items: _relationships
                                    .map(
                                      (rel) => DropdownMenuItem<String>(
                                        value: rel,
                                        child: Text(rel),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) => setState(
                                  () => selectedRelationship = value,
                                ),
                                validator: (value) => value == null
                                    ? 'Relationship is required'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              DropdownButtonFormField2<String>(
                                isExpanded: true,
                                decoration: _dropdownDec('Marital Status'),
                                value: selectedMaritalStatus,
                                style: const TextStyle(
                                  color: kText,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                                items: _maritalStatuses
                                    .map(
                                      (status) => DropdownMenuItem<String>(
                                        value: status,
                                        child: Text(status),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) => setState(
                                  () => selectedMaritalStatus = value,
                                ),
                                validator: (value) => value == null
                                    ? 'Marital status is required'
                                    : null,
                              ),
                              const SizedBox(height: 24),
                              // Birth Certificate Upload
                              _fileUploadSection(
                                label: 'Birth Certificate (optional)',
                                isUploading: _isUploadingFile,
                                fileUrl: birthCertificateFile,
                                onUpload: _pickAndUploadFile,
                                onClear: () =>
                                    setState(() => birthCertificateFile = null),
                              ),
                              const SizedBox(height: 18),
                              // Valid ID Upload
                              _fileUploadSection(
                                label: 'Valid ID (required)',
                                isUploading: _isUploadingValidId,
                                fileUrl: validIdFile,
                                onUpload: _pickAndUploadValidId,
                                onClear: () =>
                                    setState(() => validIdFile = null),
                                required: true,
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton.icon(
                                  icon: const Icon(
                                    Icons.check_circle,
                                    size: 20,
                                  ),
                                  label: const Text(
                                    'Submit',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kAccent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 2,
                                  ),
                                  onPressed: _isSubmitting
                                      ? null
                                      : _submitBeneficiary,
                                ),
                              ),
                            ],
                          ),
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
    );
  }

  Widget _fileUploadSection({
    required String label,
    required bool isUploading,
    required String? fileUrl,
    required VoidCallback onUpload,
    required VoidCallback onClear,
    bool required = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label + (required ? ' *' : ''),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: kText,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: fileUrl == null
                  ? OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file, color: kAccent),
                      label: Text(isUploading ? 'Uploading...' : 'Upload File'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kAccent,
                        side: const BorderSide(color: kAccent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: isUploading ? null : onUpload,
                    )
                  : Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: kSuccess,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'File uploaded',
                            style: const TextStyle(
                              color: kSuccess,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: kDanger,
                            size: 20,
                          ),
                          onPressed: onClear,
                        ),
                      ],
                    ),
            ),
            if (fileUrl != null)
              IconButton(
                icon: const Icon(Icons.visibility, color: kAccent),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.network(
                              fileUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Text('Could not load image'),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.close, size: 18),
                              label: const Text('Close'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Accepted: JPG, PNG, PDF',
          style: TextStyle(color: kSubText, fontSize: 11),
        ),
      ],
    );
  }
}
