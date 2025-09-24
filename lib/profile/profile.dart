import 'package:capstone_app/Auth/login.dart';
import 'package:capstone_app/Beneficiary/beneficiary.dart';
import 'package:capstone_app/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Senior-friendly color palette (high contrast, softer tones)
const kBg = Color(0xFFFAFAF7); // warm off-white
const kText = Color(0xFF1F2937); // dark neutral
const kSubText = Color(0xFF4B5563); // softer dark gray
const kPrimary = Color(0xFF2F4F4F); // dark slate gray (headers)
const kAccent = Color(0xFF3E8E7E); // muted teal (buttons)
const kAccentDark = Color(0xFF2D6F63); // darker teal (pressed)
const kWarn = Color(0xFFB71C1C); // dark red (logout border)

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
  bool _uploadingImage = false;

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
      setState(() => isLoading = false);
      return;
    }

    try {
      final response = await supabase
          .from('users')
          .select('full_name, mobile_number, address, sex, profile_url')
          .eq('id', currentUser.id)
          .maybeSingle();

      if (!mounted) return;
      if (response == null) {
        setState(() {
          fullName = '';
          mobileNumber = '';
          address = '';
          sex = '';
          profileUrl = null;
          isLoading = false;
        });
      } else {
        setState(() {
          fullName = (response['full_name'] as String?)?.trim() ?? '';
          mobileNumber = (response['mobile_number'] as String?)?.trim() ?? '';
          address = (response['address'] as String?)?.trim() ?? '';
          sex = (response['sex'] as String?)?.trim() ?? '';
          profileUrl = response['profile_url'] as String?;
          _fullNameController.text = fullName;
          _mobileController.text = mobileNumber;
          _addressController.text = address;
          _sexController.text = sex;
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load profile: $e')));
    }
  }

  String removeTitle(String name) {
    final titleRegex = RegExp(r'^(Mr\.|Mrs\.)\s', caseSensitive: false);
    return name.replaceAll(titleRegex, '').trim();
  }

  String _displayName() => removeTitle(fullName);

  String _initialOf(String? name) {
    final t = (name ?? '').trim();
    if (t.isEmpty) return 'M';
    return t.characters.first.toUpperCase();
  }

  Future<void> _pickAndUploadImage() async {
    if (_uploadingImage) return;
    setState(() => _uploadingImage = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null) {
        setState(() => _uploadingImage = false);
        return;
      }

      final userId = supabase.auth.currentUser!.id;
      final fileBytes = result.files.first.bytes;
      final fileName = result.files.first.name;

      if (fileBytes == null) {
        throw Exception('Failed to read file bytes');
      }

      final ext = fileName.split('.').last;
      final uniqueFileName =
          '$userId-${DateTime.now().millisecondsSinceEpoch}.$ext';

      await supabase.storage
          .from('avatars')
          .uploadBinary(
            uniqueFileName,
            fileBytes,
            fileOptions: const FileOptions(upsert: true),
          );
      final publicUrl = supabase.storage
          .from('avatars')
          .getPublicUrl(uniqueFileName);

      final update = await supabase
          .from('users')
          .update({'profile_url': publicUrl})
          .eq('id', userId)
          .select()
          .maybeSingle();

      if (update == null) {
        throw Exception('Failed to update profile image URL');
      }

      if (!mounted) return;
      setState(() {
        profileUrl = publicUrl;
        _uploadingImage = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo updated')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
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

      if (!mounted) return;
      if (res.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No profile found to update')),
        );
      } else {
        final row = res.first;
        setState(() {
          fullName = (row['full_name'] ?? '').toString();
          mobileNumber = (row['mobile_number'] ?? '').toString();
          address = (row['address'] ?? '').toString();
          sex = (row['sex'] ?? '').toString();
          profileUrl = (row['profile_url'] ?? profileUrl)?.toString();
          _editing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating profile: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will be logged out of your account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Supabase.instance.client.auth.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('selectedDayungUnit');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Login()),
        (route) => false,
      );
    }
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kSubText),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;

    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kPrimary,
        elevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
            icon: const Icon(Icons.settings, color: Colors.white),
          ),
        ],
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                // Avatar + Edit toggle
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: isWide ? 56 : 48,
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage:
                                  (profileUrl != null && profileUrl!.isNotEmpty)
                                  ? NetworkImage(profileUrl!)
                                  : null,
                              child: (profileUrl == null || profileUrl!.isEmpty)
                                  ? Text(
                                      _initialOf(fullName),
                                      style: TextStyle(
                                        fontSize: isWide ? 28 : 24,
                                        color: kPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            if (_editing)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: InkWell(
                                  onTap: _pickAndUploadImage,
                                  borderRadius: BorderRadius.circular(24),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: kAccent,
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(8),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayName().isNotEmpty
                                    ? _displayName()
                                    : 'Your name',
                                style: TextStyle(
                                  fontSize: isWide ? 22 : 18,
                                  fontWeight: FontWeight.w700,
                                  color: kText,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                (mobileNumber.isNotEmpty
                                    ? mobileNumber
                                    : 'Mobile not set'),
                                style: const TextStyle(
                                  color: kSubText,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 44,
                                child: OutlinedButton.icon(
                                  icon: Icon(
                                    _editing ? Icons.close : Icons.edit,
                                    size: 20,
                                    color: kAccent,
                                  ),
                                  label: Text(
                                    _editing ? 'Cancel' : 'Edit Profile',
                                    style: const TextStyle(
                                      color: kAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: kAccent),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: () {
                                    if (_editing) {
                                      _fullNameController.text = fullName;
                                      _mobileController.text = mobileNumber;
                                      _addressController.text = address;
                                      _sexController.text = sex;
                                    }
                                    setState(() => _editing = !_editing);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Editable fields
                _ProfileFieldCard(
                  icon: Icons.person,
                  label: 'Full Name',
                  value: _displayName(),
                  editingChild: TextFormField(
                    controller: _fullNameController,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Full name is required'
                        : null,
                    style: const TextStyle(fontSize: 16),
                    decoration: _fieldDecoration('Enter full name'),
                  ),
                ),
                _ProfileFieldCard(
                  icon: Icons.location_on,
                  label: 'Address',
                  value: address.isNotEmpty ? address : 'Not provided',
                  editingChild: TextFormField(
                    controller: _addressController,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 16),
                    decoration: _fieldDecoration('Enter address'),
                  ),
                ),
                _ProfileFieldCard(
                  icon: Icons.phone,
                  label: 'Mobile Number',
                  value: mobileNumber.isNotEmpty
                      ? mobileNumber
                      : 'Not provided',
                  editingChild: TextFormField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Mobile number is required';
                      if (t.length < 7) return 'Enter a valid number';
                      return null;
                    },
                    style: const TextStyle(fontSize: 16),
                    decoration: _fieldDecoration('Enter mobile number'),
                  ),
                ),
                _ProfileFieldCard(
                  icon: Icons.person_outline,
                  label: 'Sex',
                  value: sex.isNotEmpty ? sex : 'Not provided',
                  editingChild: DropdownButtonFormField<String>(
                    value: (_sexController.text.isNotEmpty
                        ? _sexController.text
                        : null),
                    items: const [
                      DropdownMenuItem(value: 'Male', child: Text('Male')),
                      DropdownMenuItem(value: 'Female', child: Text('Female')),
                      DropdownMenuItem(
                        value: 'Prefer not to say',
                        child: Text('Prefer not to say'),
                      ),
                    ],
                    onChanged: (val) => _sexController.text = val ?? '',
                    decoration: _fieldDecoration('Select sex'),
                  ),
                ),

                const SizedBox(height: 16),

                if (_editing) ...[
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Save Changes',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.people),
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BeneficiaryPage(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      label: const Text(
                        'Beneficiaries',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.logout, color: kWarn),
                      onPressed: _confirmLogout,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kWarn),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      label: const Text(
                        'Logout',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: kWarn,
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Manage Dayung entry
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.home, color: kPrimary),
                    title: const Text(
                      'Manage Dayung',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'View current Dayung, apply or change',
                      style: TextStyle(color: kSubText),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Top-right uploading badge
          if (_uploadingImage)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Uploading photo...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileFieldCard extends StatelessWidget {
  const _ProfileFieldCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.editingChild,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget editingChild;

  @override
  Widget build(BuildContext context) {
    final largeText =
        MediaQuery.of(context).textScaleFactor >
        1.2; // support system text scaling

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: largeText ? 30 : 26, color: kPrimary),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: largeText ? 18 : 16,
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _isEditing(context)
                ? editingChild
                : Text(
                    value,
                    style: const TextStyle(color: kSubText, fontSize: 16),
                  ),
          ],
        ),
      ),
    );
  }

  bool _isEditing(BuildContext context) {
    final state = context.findAncestorStateOfType<_ProfilePageState>();
    return state?._editing ?? false;
  }
}
