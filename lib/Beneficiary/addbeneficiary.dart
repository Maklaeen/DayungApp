import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Palette (matching register.dart vibe)
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);
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

  String? selectedRelationship;
  DateTime? _selectedDob;
  String? birthCertificateFile; // public URL
  String? selectedMaritalStatus;

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
      labelStyle: const TextStyle(color: kSubtleText, fontSize: 16),
      prefixIcon: icon != null ? Icon(icon, color: kSubtleText) : null,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kEdge),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kEdge),
        borderSide: const BorderSide(color: kPrimary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kEdge),
        borderSide: const BorderSide(color: kDanger, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kEdge),
        borderSide: const BorderSide(color: kDanger, width: 2),
      ),
    );
  }

  InputDecoration _dropdownDec(String label) => _dec(label).copyWith(
    contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
  );

  Widget _dobField(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDob ?? DateTime(now.year - 18, 1, 1),
          firstDate: DateTime(now.year - 120),
          lastDate: now,
          helpText: 'Select Date of Birth',
        );
        if (picked != null) setState(() => _selectedDob = picked);
      },
      child: AbsorbPointer(
        child: TextFormField(
          decoration: _dec(
            'Date of Birth',
            icon: Icons.cake,
          ).copyWith(hintText: 'Select birth date'),
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

  // ...existing code...

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
    if (!_formKey.currentState!.validate()) return;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be logged in')));
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

      if (response == null || response['id'] == null) {
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
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isSmall ? 8 : 24,
              vertical: isSmall ? 8 : 16,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 640 : 420),
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: EdgeInsets.only(bottom: isSmall ? 8 : 16),
                    child: Column(
                      children: const [
                        Text(
                          'Add Beneficiary',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: kNeutralText,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Provide beneficiary details below',
                          style: TextStyle(color: kSubtleText),
                        ),
                      ],
                    ),
                  ),

                  Card(
                    elevation: 2,
                    shadowColor: Colors.black12,
                    color: const Color.fromARGB(255, 232, 232, 232),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kEdge),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(isSmall ? 10 : 20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            if (_isSubmitting)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: LinearProgressIndicator(
                                  color: kPrimary,
                                  backgroundColor: Color(0xFFEFF2F7),
                                  minHeight: 3,
                                ),
                              ),

                            // Section: Personal Information
                            Row(
                              children: const [
                                Icon(Icons.person_outline, color: kPrimary),
                                SizedBox(width: 8),
                                Text(
                                  'Personal Information',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: kNeutralText,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Full Name
                            TextFormField(
                              controller: fullNameController,
                              textInputAction: TextInputAction.next,
                              style: TextStyle(
                                fontSize: isWide ? 18 : 16,
                                color: kNeutralText,
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
                            const SizedBox(height: 14),

                            // Date of Birth
                            _dobField(context),
                            const SizedBox(height: 14),

                            // Relationship
                            DropdownButtonFormField<String>(
                              value: selectedRelationship,
                              decoration: _dropdownDec('Relationship'),
                              items: _relationships
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => selectedRelationship = v),
                              validator: (v) =>
                                  v == null ? 'Relationship is required' : null,
                            ),
                            const SizedBox(height: 14),

                            // Marital Status
                            DropdownButtonFormField<String>(
                              value: selectedMaritalStatus,
                              decoration: _dropdownDec('Marital Status'),
                              items: _maritalStatuses
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s),
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
                            // ...existing code...

                            // Section: Documents
                            Row(
                              children: const [
                                Icon(
                                  Icons.insert_drive_file_outlined,
                                  color: kPrimary,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Documents',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: kNeutralText,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Birth Certificate Picker
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    enabled: false,
                                    decoration: _dec(
                                      'Birth Certificate',
                                      hint: 'Upload JPG/PNG/PDF',
                                      icon: Icons.upload_file,
                                    ),
                                    controller: TextEditingController(
                                      text: birthCertificateFile == null
                                          ? ''
                                          : 'Uploaded',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: _isUploadingFile
                                      ? 'Uploading...'
                                      : 'Upload',
                                  child: ElevatedButton.icon(
                                    onPressed: _isUploadingFile
                                        ? null
                                        : _pickAndUploadFile,
                                    icon: _isUploadingFile
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.upload_outlined),
                                    label: const Text('Upload'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kPrimary,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                                if (birthCertificateFile != null) ...[
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message: 'Remove',
                                    child: OutlinedButton.icon(
                                      onPressed: () => setState(
                                        () => birthCertificateFile = null,
                                      ),
                                      icon: const Icon(
                                        Icons.close,
                                        size: 18,
                                        color: kDanger,
                                      ),
                                      label: const Text(
                                        'Clear',
                                        style: TextStyle(color: kDanger),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: kDanger),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Accepted: JPG, PNG, PDF',
                                style: TextStyle(
                                  color: kSubtleText,
                                  fontSize: 12,
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Actions
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _isSubmitting
                                    ? null
                                    : _submitBeneficiary,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimary,
                                  disabledBackgroundColor: kPrimaryDark
                                      .withOpacity(0.5),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(kEdge),
                                  ),
                                  elevation: 0,
                                ),
                                child: _isSubmitting
                                    ? const SizedBox(
                                        width: 26,
                                        height: 26,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 3,
                                        ),
                                      )
                                    : const Text(
                                        'Submit Beneficiary',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: OutlinedButton(
                                onPressed: _isSubmitting
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(kEdge),
                                  ),
                                  side: const BorderSide(
                                    color: kDanger,
                                    width: 1.5,
                                  ),
                                  foregroundColor: kDanger,
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
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
    );
  }
}
