import 'package:flutter/material.dart';
import 'package:capstone_app/Auth/login.dart';

class Reapply extends StatelessWidget {
  final _formKey = GlobalKey<FormState>();

  Reapply({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFEFFFF),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Image.asset(
                  'assets/images/dayunglogo.jpeg',
                  width: 220,
                  height: 80,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tabang sa Kalisud, Sa Isa ka Tap.',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.normal,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 30),

                _overlapLabelField(
                  label: 'Full Name',
                  child: _customTextField(hint: 'Juan Dela Cruz'),
                ),

                _overlapLabelField(
                  label: 'Date of Birth',
                  child: Row(
                    children: [
                      Expanded(
                        child: _customDropdown(hint: 'Month', items: _months),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _customDropdown(
                          hint: 'Day',
                          items: List.generate(31, (i) => '${i + 1}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _customDropdown(
                          hint: 'Year',
                          items: List.generate(
                            100,
                            (i) => '${DateTime.now().year - i}',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Sex
                _overlapLabelField(
                  label: 'Sex',
                  child: _customTextField(hint: 'Male/Female'),
                ),
                _overlapLabelField(
                  label: 'Mobile Number',
                  child: _customTextField(hint: '+63 9XXXXXXXXX'),
                ),
                _overlapLabelField(
                  label: 'Address',
                  child: _customTextField(hint: 'Purok, Barangay, City'),
                ),
                _overlapLabelField(
                  label: 'Create Password',
                  child: _customTextField(hint: '********', obscure: true),
                ),

                _overlapLabelField(
                  label: 'Marriage Certificate',
                  child: _filePickerField(),
                ),

                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => Login()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565B3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Submit',
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.normal,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
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
                color: const Color(0xFF5B8FD7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w400,
                  fontSize: 18,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          Positioned(left: 0, right: 0, top: 32, child: child),
        ],
      ),
    );
  }

  Widget _customTextField({String? hint, bool obscure = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: TextFormField(
        obscureText: obscure,
        decoration: InputDecoration(
          hintText: hint,
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

  Widget _customDropdown({required String hint, required List<String> items}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          hintText: hint,
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
        items: items
            .map(
              (item) =>
                  DropdownMenuItem<String>(value: item, child: Text(item)),
            )
            .toList(),
        onChanged: (value) {},
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
                hintText: 'Choose file',
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
            onPressed: () {},
            icon: const Icon(Icons.upload_outlined, color: Colors.black54),
          ),
        ],
      ),
    );
  }

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
}
