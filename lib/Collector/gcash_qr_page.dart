import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

const kPrimary = Color(0xFF1E40AF);
const kAccent = Color(0xFF059669);
const kCardBg = Color(0xFFFFFFFF);
const kSubText = Color(0xFF6B7280);
const kBorderColor = Color(0xFFE5E7EB);

class GcashQrPage extends StatefulWidget {
  const GcashQrPage({super.key});

  @override
  State<GcashQrPage> createState() => _GcashQrPageState();
}

class _GcashQrPageState extends State<GcashQrPage> {
  File? _qrImage;
  Uint8List? _qrImageBytes;
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchUserNames();
  }

  Map<String, String> _userNames = {};
  Future<void> _fetchUserNames() async {
    final response = await Supabase.instance.client
        .from('users')
        .select('id, full_name');
    setState(() {
      _userNames = {
        for (final user in response)
          user['id'] as String: user['full_name'] as String? ?? 'Unknown',
      };
    });
  }

  Future<void> _pickQrImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _qrImage = File(pickedFile.path);
        _qrImageBytes = bytes;
      });
    }
  }

  void _saveQrCode() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _qrImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a name and select a QR image.'),
        ),
      );
      return;
    }

    try {
      final fileBytes = _qrImageBytes!;
      final fileName = 'gcash_qr_${DateTime.now().millisecondsSinceEpoch}.png';
      await Supabase.instance.client.storage
          .from('gcash_qr_images')
          .uploadBinary(
            fileName,
            fileBytes,
            fileOptions: const FileOptions(contentType: 'image/png'),
          );

      final imageUrl = Supabase.instance.client.storage
          .from('gcash_qr_images')
          .getPublicUrl(fileName);

      await Supabase.instance.client.from('gcash_qr_codes').insert({
        'name': name,
        'image_url': imageUrl,
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('GCash QR saved!')));
      setState(() {
        _nameController.clear();
        _qrImage = null;
        _qrImageBytes = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
    }
  }

  Future<List<Map<String, dynamic>>> _fetchQrCodes() async {
    final response = await Supabase.instance.client
        .from('gcash_qr_codes')
        .select('image_url, name, created_at, uploaded_by, userdeceased')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('GCash QR Codes'),
        backgroundColor: kPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 40 : 16,
            vertical: isWide ? 32 : 20,
          ),
          children: [
            // Modern Card for Upload
            Container(
              margin: const EdgeInsets.only(bottom: 32),
              decoration: BoxDecoration(
                color: kCardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kBorderColor.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: kPrimary.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: EdgeInsets.all(isWide ? 32 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upload GCash QR',
                    style: TextStyle(
                      fontSize: isWide ? 22 : 18,
                      fontWeight: FontWeight.w800,
                      color: kPrimary,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: _qrImageBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.memory(
                              _qrImageBytes!,
                              width: isWide ? 220 : 160,
                              height: isWide ? 220 : 160,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Container(
                            width: isWide ? 220 : 160,
                            height: isWide ? 220 : 160,
                            decoration: BoxDecoration(
                              color: kPrimary.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.qr_code_2_rounded,
                              size: 90,
                              color: kPrimary,
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'GCash Name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _pickQrImage,
                          icon: const Icon(Icons.add_photo_alternate),
                          label: const Text('Add QR Image'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saveQrCode,
                          icon: const Icon(Icons.save),
                          label: const Text('Save'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Modern Card for Saved QR Codes
            Container(
              decoration: BoxDecoration(
                color: kCardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kBorderColor.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: kPrimary.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: EdgeInsets.all(isWide ? 32 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Saved GCash QR Codes',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isWide ? 20 : 17,
                      color: kPrimary,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchQrCodes(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Text('Error: ${snapshot.error}');
                      }
                      final data = snapshot.data ?? [];
                      if (data.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.qr_code_2_rounded,
                                size: 64,
                                color: kPrimary.withOpacity(0.12),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No QR codes found.',
                                style: TextStyle(
                                  color: kSubText,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: data.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 18),
                        itemBuilder: (context, idx) {
                          final row = data[idx];
                          final uploadedByName =
                              _userNames[row['uploaded_by']] ?? 'Unknown';
                          final userDeceasedName =
                              _userNames[row['userdeceased']] ?? 'Unknown';
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => Dialog(
                                    backgroundColor: Colors.black,
                                    insetPadding: const EdgeInsets.all(16),
                                    child: InteractiveViewer(
                                      child: Image.network(
                                        row['image_url'],
                                        fit: BoxFit.contain,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const Icon(
                                                  Icons.broken_image,
                                                  size: 100,
                                                  color: Colors.white,
                                                ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: EdgeInsets.all(isWide ? 22 : 14),
                                decoration: BoxDecoration(
                                  color: kPrimary.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: kPrimary.withOpacity(0.08),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.network(
                                        row['image_url'],
                                        width: isWide ? 80 : 60,
                                        height: isWide ? 80 : 60,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const Icon(Icons.broken_image),
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            row['name']?.toString() ?? '',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: isWide ? 17 : 15,
                                              color: kPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            row['created_at']?.toString() ?? '',
                                            style: TextStyle(
                                              fontSize: isWide ? 13 : 12,
                                              color: kSubText,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Uploaded by: $uploadedByName',
                                            style: TextStyle(
                                              fontSize: isWide ? 13 : 12,
                                              color: kSubText,
                                            ),
                                          ),
                                          Text(
                                            'For: $userDeceasedName',
                                            style: TextStyle(
                                              fontSize: isWide ? 13 : 12,
                                              color: kSubText,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: kAccent,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                      child: const Text('Pay'),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) {
                                            final TextEditingController
                                            amountController =
                                                TextEditingController();
                                            return AlertDialog(
                                              title: const Text('Enter Amount'),
                                              content: TextField(
                                                controller: amountController,
                                                keyboardType:
                                                    TextInputType.numberWithOptions(
                                                      decimal: true,
                                                    ),
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'Amount',
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.of(
                                                    context,
                                                  ).pop(),
                                                  child: const Text('Cancel'),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () {
                                                    final amount =
                                                        amountController.text
                                                            .trim();
                                                    if (amount.isNotEmpty) {
                                                      Navigator.of(
                                                        context,
                                                      ).pop();
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'Amount entered: ₱$amount',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  child: const Text('Proceed'),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
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
