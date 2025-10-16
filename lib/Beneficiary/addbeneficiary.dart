import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/ui/theme/branding.dart';

// Additional colors for add beneficiary specific styling
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimaryLight = Color(0xFF3B82F6);
const kAccentDark = Color(0xFF059669);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);
const double kEdge = 18;

class AddBeneficiaryPage extends StatefulWidget {
  const AddBeneficiaryPage({super.key});

  @override
  State<AddBeneficiaryPage> createState() => _AddBeneficiaryPageState();
}

class _AddBeneficiaryPageState extends State<AddBeneficiaryPage> {
  // Controllers
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController maritalController = TextEditingController();

  // State
  final user = Supabase.instance.client.auth.currentUser;
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  bool _isUploadingFile = false;
  int? _selectedYear;
  int? _selectedMonth;
  int? _selectedDay;

  String? selectedRelationship;

  String? birthCertificateFile; // public URL
  String? selectedMaritalStatus;

  List<int> get _years {
    final now = DateTime.now();
    return List.generate(120, (i) => now.year - i);
  }

  List<int> get _months => List.generate(12, (i) => i + 1);

  List<int> get _days {
    if (_selectedYear != null && _selectedMonth != null) {
      final lastDay = DateTime(_selectedYear!, _selectedMonth! + 1, 0).day;
      return List.generate(lastDay, (i) => i + 1);
    }
    return List.generate(31, (i) => i + 1);
  }

  DateTime? _selectedDob;

  // Optionally, remove the old getter if you want to use only the field.
  // If you want to keep the getter logic, rename it or merge logic as needed.

  // Relationship options
  final List<String> _relationships = const [
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

  final List<String> _maritalStatuses = const [
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
        borderSide: const BorderSide(color: kBorderColor, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kPrimary, width: 1.5),
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

  Widget _dobDropdowns() {
    return Row(
      children: [
        // Month
        Expanded(
          flex: 1,
          child: DropdownButtonFormField<int>(
            initialValue: _selectedMonth,
            decoration: _dropdownDec('Month'),
            items: _months
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(
                      m.toString().padLeft(2, '0'),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() {
              _selectedMonth = v;
              // Check if current day is still valid for new month/year
              if (_selectedYear != null) {
                final lastDay = DateTime(
                  _selectedYear!,
                  _selectedMonth! + 1,
                  0,
                ).day;
                if (_selectedDay != null && _selectedDay! > lastDay) {
                  _selectedDay = null;
                }
              }
            }),
            validator: (v) => v == null ? 'Month' : null,
          ),
        ),
        const SizedBox(width: 2),
        // Day
        Expanded(
          flex: 1,
          child: DropdownButtonFormField<int>(
            initialValue: _selectedDay,
            decoration: _dropdownDec('Day'),
            items: _days
                .map(
                  (d) => DropdownMenuItem(
                    value: d,
                    child: Text(
                      d.toString().padLeft(2, '0'),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _selectedDay = v),
            validator: (v) => v == null ? 'Day' : null,
          ),
        ),
        const SizedBox(width: 2),
        // Year
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<int>(
            initialValue: _selectedYear,
            decoration: _dropdownDec('Year'),
            items: _years
                .map(
                  (y) => DropdownMenuItem(
                    value: y,
                    child: Text(
                      y.toString(),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() {
              _selectedYear = v;
              // Check if current day is still valid for new year/month
              if (_selectedMonth != null) {
                final lastDay = DateTime(
                  _selectedYear!,
                  _selectedMonth! + 1,
                  0,
                ).day;
                if (_selectedDay != null && _selectedDay! > lastDay) {
                  _selectedDay = null;
                }
              }
            }),
            validator: (v) => v == null ? 'Year' : null,
          ),
        ),
      ],
    );
  }

  Future<void> _pickAndUploadFile() async {
    setState(() => _isUploadingFile = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true, // Ensure bytes are available for uploadBinary
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

      final publicUrl = Supabase.instance.client.storage
          .from('birth_certificates')
          .getPublicUrl(filePath);

      setState(() {
        birthCertificateFile = publicUrl;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File uploaded successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('File upload failed: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingFile = false);
    }
  }

  String _formatDob(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submitBeneficiary() async {
    // Compute DOB from dropdowns
    if (_selectedYear != null &&
        _selectedMonth != null &&
        _selectedDay != null) {
      _selectedDob = DateTime(_selectedYear!, _selectedMonth!, _selectedDay!);
    } else {
      _selectedDob = null;
    }

    if (!_formKey.currentState!.validate()) return;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be logged in')));
      return;
    }
    if (_selectedDob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Date of birth is required')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final fullName = fullNameController.text.trim();
    final maritalStatus = maritalController.text.trim();
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
              'status': 'Pending',
            },
          ])
          .select()
          .single();

      // ...existing code...

      if (response['id'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add beneficiary')),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Beneficiary added')));
        fullNameController.clear();
        setState(() {
          selectedRelationship = null;
          selectedMaritalStatus = null;
          _selectedDob = null;
          birthCertificateFile = null;
        });
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // UI
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
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.person_add_rounded,
                            color: kPrimary,
                            size: 32,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Add Beneficiary',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: kText,
                              fontFamily: 'Montserrat',
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Provide beneficiary details below',
                            style: TextStyle(
                              color: kSubText,
                              fontSize: 16,
                              fontFamily: 'OpenSans',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Form Card
                    Container(
                      padding: EdgeInsets.all(isSmall ? 16 : 20),
                      decoration: BoxDecoration(
                        color: kCardBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            if (_isSubmitting)
                              Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: kPrimary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const LinearProgressIndicator(
                                  color: kPrimary,
                                  backgroundColor: Color(0xFFEFF2F7),
                                  minHeight: 4,
                                ),
                              ),

                            // Section: Personal Information
                            Row(
                              children: [
                                const Icon(
                                  Icons.person_rounded,
                                  color: kPrimary,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Personal Information',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: kText,
                                    fontFamily: 'Montserrat',
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Full Name
                            TextFormField(
                              controller: fullNameController,
                              textInputAction: TextInputAction.next,
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
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Full Name is required'
                                  : null,
                            ),
                            const SizedBox(height: 12),

                            // Date of Birth
                            _dobDropdowns(),
                            const SizedBox(height: 12),

                            // Relationship
                            DropdownButtonFormField<String>(
                              initialValue: selectedRelationship,
                              decoration: _dropdownDec('Relationship'),
                              items: _relationships
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(
                                        s,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => selectedRelationship = v),
                              validator: (v) =>
                                  v == null ? 'Relationship is required' : null,
                            ),
                            const SizedBox(height: 12),

                            // Marital Status
                            DropdownButtonFormField<String>(
                              initialValue: selectedMaritalStatus,
                              decoration: _dropdownDec('Marital Status'),
                              items: _maritalStatuses
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(
                                        s,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => selectedMaritalStatus = v),
                              validator: (v) => v == null
                                  ? 'Marital status is required'
                                  : null,
                            ),
                            const SizedBox(height: 24),

                            // Section: Documents
                            Row(
                              children: [
                                const Icon(
                                  Icons.description_rounded,
                                  color: kPrimary,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Documents',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: kText,
                                    fontFamily: 'Montserrat',
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Birth Certificate Picker
                            Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.upload_file_rounded,
                                      color: kPrimary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    const Text(
                                      'Birth Certificate',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: kText,
                                        fontFamily: 'Montserrat',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: kBorderColor,
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          birthCertificateFile == null
                                              ? 'No file selected'
                                              : 'File uploaded successfully',
                                          style: TextStyle(
                                            color: birthCertificateFile == null
                                                ? kSubText
                                                : kSuccess,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: 'OpenSans',
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: _isUploadingFile
                                          ? null
                                          : _pickAndUploadFile,
                                      icon: _isUploadingFile
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.upload_rounded,
                                              size: 18,
                                            ),
                                      label: Text(
                                        _isUploadingFile
                                            ? 'Uploading...'
                                            : 'Upload',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: kPrimary,
                                        foregroundColor: Colors.white,
                                        elevation: 2,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (birthCertificateFile != null) ...[
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        onPressed: () => setState(
                                          () => birthCertificateFile = null,
                                        ),
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                        label: const Text(
                                          'Clear',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: kDanger,
                                          foregroundColor: Colors.white,
                                          elevation: 2,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Accepted: JPG, PNG, PDF',
                                style: TextStyle(color: kSubText, fontSize: 11),
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Actions
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 56,
                                    child: ElevatedButton(
                                      onPressed: _isSubmitting
                                          ? null
                                          : () => Navigator.of(context).pop(),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: kDanger,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        elevation: 2,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 16,
                                        ),
                                      ),
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: SizedBox(
                                    height: 56,
                                    child: ElevatedButton.icon(
                                      onPressed: _isSubmitting
                                          ? null
                                          : _submitBeneficiary,
                                      icon: _isSubmitting
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.person_add_rounded,
                                              size: 18,
                                            ),
                                      label: Text(
                                        _isSubmitting
                                            ? 'Submitting...'
                                            : 'Submit',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: kPrimary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        elevation: 2,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 16,
                                        ),
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
