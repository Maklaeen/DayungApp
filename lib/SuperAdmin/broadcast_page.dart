import 'package:flutter/material.dart';

const kPrimary = Color(0xFF1E40AF);
const kCardBg = Color(0xFFFFFFFF);
const kSubText = Color(0xFF6B7280);

class SuperAdminBroadcastPage extends StatefulWidget {
  const SuperAdminBroadcastPage({super.key});

  @override
  State<SuperAdminBroadcastPage> createState() =>
      _SuperAdminBroadcastPageState();
}

class _SuperAdminBroadcastPageState extends State<SuperAdminBroadcastPage> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final themeBg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF18181B)
        : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: themeBg,
      appBar: AppBar(
        title: const Text('Broadcast Announcement'),
        backgroundColor: kPrimary,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Material(
                color: kCardBg,
                borderRadius: BorderRadius.circular(16),
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Send Announcement',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: kPrimary,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _controller,
                        maxLines: 5,
                        decoration: InputDecoration(
                          labelText: 'Announcement',
                          hintText: 'Type your announcement here...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.send),
                        label: const Text('Send Announcement'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: () {
                          // TODO: Implement broadcast logic
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Announcement sent!')),
                          );
                          _controller.clear();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
