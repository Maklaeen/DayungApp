import 'package:capstone_app/Auth/login.dart';
import 'package:capstone_app/Beneficiary/beneficiary.dart';
import 'package:capstone_app/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;

  final _fullNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _addressController = TextEditingController();
  final _sexController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String fullName = '';
  String mobileNumber = '';
  String address = '';
  String sex = '';
  String? profileUrl;
  bool isLoading = true;

  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _sexController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserProfile() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    final response = await supabase
        .from('users')
        .select('full_name, mobile_number, address, sex, profile_url')
        .eq('id', currentUser.id)
        .maybeSingle();

    if (response == null) {
      setState(() {
        fullName = 'Unknown';
        mobileNumber = 'Not Available';
        address = 'Not Provided';
        sex = '';
        profileUrl = null;
        isLoading = false;
      });
    } else {
      setState(() {
        fullName = response['full_name'] as String? ?? '';
        mobileNumber = response['mobile_number'] as String? ?? '';
        address = response['address'] as String? ?? '';
        sex = response['sex'] as String? ?? '';
        profileUrl = response['profile_url'] as String?;
        _fullNameController.text = fullName;
        _mobileController.text = mobileNumber;
        _addressController.text = address;
        _sexController.text = sex;
        isLoading = false;
      });
    }
  }

  String removeTitle(String name) {
    final titleRegex = RegExp(r'^(Mr\.|Mrs\.)\s');
    return name.replaceAll(titleRegex, '');
  }

  String _displayName() {
    return removeTitle(fullName);
  }

  Future<void> _pickAndUploadImage() async {
    final supabase = Supabase.instance.client;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (result == null) return;

      final userId = supabase.auth.currentUser!.id;
      final fileBytes = result.files.first.bytes;
      final fileName = result.files.first.name;

      if (fileBytes == null) {
        throw Exception('Failed to read file bytes');
      }

      final ext = fileName.split('.').last;
      final uniqueFileName =
          '$userId-${DateTime.now().millisecondsSinceEpoch}.$ext';

      final filePath = uniqueFileName;
      await supabase.storage
          .from('avatars')
          .uploadBinary(
            filePath,
            fileBytes,
            fileOptions: const FileOptions(upsert: true),
          );
      final publicUrl = supabase.storage.from('avatars').getPublicUrl(filePath);

      final update = await supabase
          .from('users')
          .update({'profile_url': publicUrl})
          .eq('id', userId)
          .select()
          .maybeSingle();

      if (update == null) {
        throw Exception('Failed to update profile image URL');
      }

      setState(() {
        profileUrl = publicUrl;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error uploading image: $e')));
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final userId = supabase.auth.currentUser!.id;

      final updated = {
        'full_name': _fullNameController.text.trim(),
        'mobile_number': _mobileController.text.trim(),
        'address': _addressController.text.trim(),
        'sex': _sexController.text.trim(),
        'profile_url': profileUrl,
      };

      final res = await supabase
          .from('users')
          .update(updated)
          .eq('id', userId)
          .select();

      if (res.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ No profile found to update')),
        );
      } else {
        final row = res.first;
        setState(() {
          fullName = row['full_name'] ?? '';
          mobileNumber = row['mobile_number'] ?? '';
          address = row['address'] ?? '';
          sex = row['sex'] ?? '';
          profileUrl = row['profile_url'] ?? profileUrl;
          _editing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Profile updated successfully')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating profile: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFEFFFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF82BC79),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(width: 8),
            Expanded(child: Container()),
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Stack(
                  children: [
                    Container(
                      height: 160,
                      decoration: const BoxDecoration(color: Color(0xFF82BC79)),
                    ),
                    Positioned(
                      top: 20,
                      right: 16,
                      child: CircleAvatar(
                        backgroundColor: Colors.white,
                        radius: 20,
                        child: IconButton(
                          icon: Icon(
                            _editing ? Icons.close : Icons.edit,
                            color: Colors.blue,
                          ),
                          onPressed: () {
                            if (_editing) {
                              _fullNameController.text = fullName;
                              _mobileController.text = mobileNumber;
                              _addressController.text = address;
                              _sexController.text = sex;
                              setState(() => _editing = false);
                            } else {
                              setState(() => _editing = true);
                            }
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: _editing ? _pickAndUploadImage : null,
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 60,
                                  backgroundColor: Colors.grey.shade300,
                                  backgroundImage:
                                      (profileUrl != null &&
                                          profileUrl!.isNotEmpty)
                                      ? NetworkImage(profileUrl!)
                                      : null,
                                  child:
                                      (profileUrl == null ||
                                          profileUrl!.isEmpty)
                                      ? Icon(
                                          Icons.person,
                                          size: 64,
                                          color: Colors.blueGrey.shade700,
                                        )
                                      : null,
                                ),
                                if (_editing)
                                  Positioned(
                                    bottom: 4,
                                    right: 4,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.blue[800],
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.camera_alt,
                                          size: 22,
                                          color: Colors.white,
                                        ),
                                        onPressed: _pickAndUploadImage,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      _buildProfileCard(
                        icon: Icons.person,
                        label: 'Full Name',
                        controller: _fullNameController,
                        value: _displayName(),
                        editing: _editing,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                        isWide: isWide,
                      ),
                      _buildProfileCard(
                        icon: Icons.location_on,
                        label: 'Address',
                        controller: _addressController,
                        value: address,
                        editing: _editing,
                        isWide: isWide,
                      ),
                      _buildProfileCard(
                        icon: Icons.phone,
                        label: 'Mobile Number',
                        controller: _mobileController,
                        value: mobileNumber,
                        editing: _editing,
                        inputType: TextInputType.phone,
                        isWide: isWide,
                      ),
                      _buildProfileCard(
                        icon: Icons.person_outline,
                        label: 'Sex',
                        controller: _sexController,
                        value: sex,
                        editing: _editing,
                        isWide: isWide,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      if (_editing) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[800],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: _saving
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : const Text(
                                    'Save Changes',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      fontFamily: 'OpenSans',
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton(
                            onPressed: () {
                              _fullNameController.text = fullName;
                              _mobileController.text = mobileNumber;
                              _addressController.text = address;
                              _sexController.text = sex;
                              setState(() => _editing = false);
                            },
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              side: const BorderSide(color: Colors.grey),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'OpenSans',
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[800],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const BeneficiaryPage(),
                                ),
                              );
                            },
                            child: const Text(
                              'Beneficiaries',
                              style: TextStyle(
                                fontSize: 20,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'OpenSans',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
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
                              await Supabase.instance.client.auth.signOut();
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => const Login(),
                                ),
                                (route) => false,
                              );
                            },
                            child: const Text(
                              'Logout',
                              style: TextStyle(
                                fontSize: 20,
                                color: Color.fromARGB(255, 179, 21, 21),
                                fontWeight: FontWeight.w600,
                                fontFamily: 'OpenSans',
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required String value,
    required bool editing,
    TextInputType inputType = TextInputType.text,
    String? Function(String?)? validator,
    required bool isWide,
  }) {
    final labelStyle = TextStyle(
      fontSize: isWide ? 18 : 15,
      fontWeight: FontWeight.w600,
      color: Colors.black87,
      fontFamily: 'Montserrat',
    );

    final valueStyle = TextStyle(
      fontSize: isWide ? 18 : 15,
      color: Colors.black54,
      fontFamily: 'OpenSans',
    );

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: Colors.blueGrey.shade700),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: labelStyle),
                  const SizedBox(height: 6),
                  if (editing)
                    TextFormField(
                      controller: controller,
                      keyboardType: inputType,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      style: valueStyle,
                      validator: validator,
                    )
                  else
                    Text(
                      value.isNotEmpty ? value : 'Not Provided',
                      style: valueStyle,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
