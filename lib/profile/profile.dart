import 'package:capstone_app/Auth/login.dart';
import 'package:capstone_app/Beneficiary/beneficiary.dart';
import 'package:capstone_app/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// import 'package:shared_preferences/shared_preferences.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String fullName = '';
  String mobileNumber = '';
  String address = '';
  String sex = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  Future<void> _fetchUserProfile() async {
    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    final userId = currentUser.id;

    final response = await Supabase.instance.client
        .from('users')
        .select('full_name, mobile_number, address, sex')
        .eq('id', userId)
        .maybeSingle();

    if (response == null) {
      setState(() {
        fullName = 'Unknown';
        mobileNumber = 'Not Available';
        address = 'Not Provided';
        sex = '';
        isLoading = false;
      });
    } else {
      setState(() {
        fullName = response['full_name'] as String? ?? '';
        mobileNumber = response['mobile_number'] as String? ?? '';
        address = response['address'] as String? ?? '';
        sex = response['sex'] as String? ?? '';
        isLoading = false;
      });
    }
  }

  String removeTitle(String name) {
    final titleRegex = RegExp(r'^(Mr\.|Mrs\.)\s');
    return name.replaceAll(titleRegex, '');
  }

  @override
  Widget build(BuildContext context) {
    const headerFont = TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      fontFamily: 'Montserrat',
    );

    const labelStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: Colors.black87,
      fontFamily: 'Montserrat',
    );

    const valueStyle = TextStyle(
      fontSize: 18,
      color: Colors.black54,
      fontFamily: 'Montserrat',
    );

    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFEFFFF),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Stack(
                children: [
                  Container(
                    height: 260,
                    decoration: const BoxDecoration(color: Color(0xFF82BC79)),
                  ),
                  Positioned(
                    top: 16,
                    left: 16,
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        size: 32,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      radius: 24,
                      child: IconButton(
                        icon: const Icon(
                          Icons.settings,
                          size: 24,
                          color: Colors.blue,
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsPage(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 64,
                    left: 0,
                    right: 0,
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.grey.shade300,
                          child: const Icon(
                            Icons.person,
                            size: 64,
                            color: Colors.blueGrey,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(removeTitle(fullName), style: headerFont),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(
                                Icons.edit,
                                size: 24,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                // Implement edit functionality if needed
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 20,
                        ),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.blue.shade400,
                          child: const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        title: const Text('Full Name', style: labelStyle),
                        subtitle: Text(
                          removeTitle(fullName),
                          style: valueStyle,
                        ),
                      ),
                    ),

                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 20,
                        ),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.blue.shade400,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        title: const Text('Address', style: labelStyle),
                        subtitle: Text(address, style: valueStyle),
                      ),
                    ),

                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 20,
                        ),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.blue.shade400,
                          child: const Icon(
                            Icons.phone,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        title: const Text('Mobile Number', style: labelStyle),
                        subtitle: Text(mobileNumber, style: valueStyle),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
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
                          // Logout logic
                          await Supabase.instance.client.auth.signOut();
                          // ignore: use_build_context_synchronously
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const Login()),
                            (route) => false,
                          );
                        },
                        child: const Text(
                          'Logout',
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

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
