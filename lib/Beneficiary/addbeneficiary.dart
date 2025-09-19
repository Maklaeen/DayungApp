import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddBeneficiaryPage extends StatefulWidget {
  const AddBeneficiaryPage({super.key});

  @override
  State<AddBeneficiaryPage> createState() => _AddBeneficiaryPageState();
}

class _AddBeneficiaryPageState extends State<AddBeneficiaryPage> {
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController maritalController = TextEditingController();
  final TextEditingController relationshipController = TextEditingController();
  final user = Supabase.instance.client.auth.currentUser;

  String? birthCertificateFile;
  String? selectedMonth;
  String? selectedDay;
  String? selectedYear;

  final List<String> _months = const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFEFFFF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Dayung',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                  Stack(
                    children: [
                      const Icon(
                        Icons.notifications_none,
                        color: Colors.orange,
                        size: 32,
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: const Text(
                            '1',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(thickness: 1.2),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Add Beneficiary',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ],
              ),

              _overlapLabelField(
                label: 'Full Name',
                child: _customTextField(controller: fullNameController),
              ),

              _overlapLabelField(
                label: 'Date of Birth',
                child: Row(
                  children: [
                    Flexible(
                      flex: 3,
                      child: _customDropdown(
                        hint: 'Month',
                        items: _months,
                        value: selectedMonth,
                        onChanged: (val) => setState(() => selectedMonth = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 2,
                      child: _customDropdown(
                        hint: 'Day',
                        items: List.generate(31, (i) => '${i + 1}'),
                        value: selectedDay,
                        onChanged: (val) => setState(() => selectedDay = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 3,
                      child: _customDropdown(
                        hint: 'Year',
                        items: List.generate(
                          100,
                          (i) => '${DateTime.now().year - i}',
                        ),
                        value: selectedYear,
                        onChanged: (val) => setState(() => selectedYear = val),
                      ),
                    ),
                  ],
                ),
              ),

              _overlapLabelField(
                label: 'Marital Status',
                child: _customTextField(controller: maritalController),
              ),
              _overlapLabelField(
                label: 'Relationship',
                child: _customTextField(controller: relationshipController),
              ),
              _overlapLabelField(
                label: 'Birth Certificate',
                child: _filePickerField(),
              ),

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _submitBeneficiary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565B3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Submit Beneficiary',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.normal,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: const BorderSide(
                      color: Color.fromARGB(255, 179, 21, 21),
                    ),
                  ),
                  onPressed: () async {
                    // ignore: use_build_context_synchronously
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 20,
                      color: Color.fromARGB(255, 179, 21, 21),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null && result.files.single.bytes != null) {
      final file = result.files.single;
      final ext = file.extension ?? 'jpg';
      final fileName =
          '${user?.id}-${DateTime.now().millisecondsSinceEpoch}.$ext';
      final filePath = 'birth_certificates/$fileName';

      try {
        // Upload to Supabase Storage
        await Supabase.instance.client.storage
            .from('birth_certificates')
            .uploadBinary(
              filePath,
              file.bytes!,
              fileOptions: const FileOptions(upsert: true),
            );

        // Get public URL
        final publicUrl = Supabase.instance.client.storage
            .from('birth_certificates')
            .getPublicUrl(filePath);

        setState(() {
          birthCertificateFile = publicUrl;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File uploaded successfully!')),
        );
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('File upload failed: $e')));
      }
    }
  }

  Future<void> _submitBeneficiary() async {
    final fullName = fullNameController.text.trim();
    final maritalStatus = maritalController.text.trim();
    final relationship = relationshipController.text.trim();
    final birthCertificate = birthCertificateFile;

    if (fullName.isEmpty ||
        selectedMonth == null ||
        selectedDay == null ||
        selectedYear == null ||
        maritalStatus.isEmpty ||
        relationship.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all fields')),
      );
      return;
    }

    final dob =
        '$selectedYear-${_months.indexOf(selectedMonth!) + 1}-$selectedDay';
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be logged in')));
      return;
    }

    final response = await Supabase.instance.client
        .from('beneficiaries')
        .insert([
          {
            'user_id': user!.id,
            'full_name': fullName,
            'dob': dob,
            'marital_status': maritalStatus,
            'relationship': relationship,
            'birth_certificate': birthCertificate, // this is the URL
            'status': 'Pending', // default status
          },
        ])
        .select()
        .single();

    // ignore: unnecessary_null_comparison
    if (response == null || response['id'] == null) {
      print('Error inserting beneficiary');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add beneficiary')),
      );
    } else {
      print('Beneficiary added successfully');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Beneficiary added')));
      fullNameController.clear();
      maritalController.clear();
      relationshipController.clear();
      setState(() {
        selectedMonth = null;
        selectedDay = null;
        selectedYear = null;
        birthCertificateFile = null;
      });
      Navigator.pop(context); // Return to previous screen
    }
  }

  Widget _overlapLabelField({required String label, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(top: 25, bottom: 8),
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF3F86BF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w400,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          Positioned(left: 0, right: 0, top: 32, child: child),
        ],
      ),
    );
  }

  Widget _customTextField({required TextEditingController controller}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          hintText: 'Enter here',
          hintStyle: const TextStyle(color: Colors.black54),
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
        ),
        style: const TextStyle(fontSize: 16),
      ),
    );
  }

  Widget _filePickerField() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              enabled: false,
              decoration: InputDecoration(
                hintText: birthCertificateFile ?? 'Choose file',
                hintStyle: const TextStyle(color: Colors.black54),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 16,
                ),
              ),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _pickAndUploadFile,
            icon: const Icon(Icons.upload_outlined, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _customDropdown({
    required String hint,
    required List<String> items,
    required void Function(String?) onChanged,
    String? value,
  }) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 13,
          horizontal: 13,
        ),
      ),
      value: value,
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
