import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

// Color palette
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);
const kPrimary = Color(0xFF0D47A1);
const kWarn = Color(0xFFF57C00);

class GcashQrPage extends StatefulWidget {
  const GcashQrPage({super.key});

  @override
  State<GcashQrPage> createState() => _GcashQrPageState();
}

class _GcashQrPageState extends State<GcashQrPage> {
  File? _qrImage;
  Uint8List? _qrImageBytes;
  final TextEditingController _nameController = TextEditingController();

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
        const SnackBar(content: Text('Please enter a name and select a QR image.')),
      );
      return;
    }

    try {
      final fileBytes = _qrImageBytes!;
      final fileName = 'gcash_qr_${DateTime.now().millisecondsSinceEpoch}.png';
      await Supabase.instance.client.storage
          .from('gcash_qr_images')
          .uploadBinary(fileName, fileBytes, fileOptions: const FileOptions(contentType: 'image/png'));

      final imageUrl = Supabase.instance.client.storage
          .from('gcash_qr_images')
          .getPublicUrl(fileName);

      final currentUser = Supabase.instance.client.auth.currentUser;

      await Supabase.instance.client.from('gcash_qr_uploads').insert({
        'name': name,
        'qr_image_url': imageUrl,
        'created_at': DateTime.now().toIso8601String(),
        'uploaded_by': currentUser?.id,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GCash QR saved!')),
      );
      setState(() {
        _nameController.clear();
        _qrImage = null;
        _qrImageBytes = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving: $e')),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _fetchQrCodes() async {
    final response = await Supabase.instance.client
        .from('gcash_qr_codes')
        .select('image_url, uploaded_by, created_at, userdeceased, dayung_unit_id, amount')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width < 600;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Curved Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 36, 20, 28),
              decoration: const BoxDecoration(
                color: kAccent,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: kAccent,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.white, size: 24),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Icon(Icons.qr_code, color: Colors.white, size: 24),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'GCash QR Management',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFamily: 'Montserrat',
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ListView(
                  children: [
                    // Add QR Card
                    Card(
                      elevation: 3,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Add New GCash QR',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kText),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'GCash Name',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _qrImageBytes != null
                                ? Image.memory(_qrImageBytes!, width: 100, height: 100)
                                : const SizedBox(),
                            TextButton.icon(
                              icon: const Icon(Icons.upload),
                              label: const Text('Upload QR'),
                              onPressed: _pickQrImage,
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.save),
                              label: const Text('Save QR'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _saveQrCode,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Saved QRs
                    const Text(
                      'Saved GCash QR Codes',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _fetchQrCodes(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: kAccent));
                        }
                        if (snapshot.hasError) {
                          return Text('Error: ${snapshot.error}');
                        }
                        final data = snapshot.data ?? [];
                        if (data.isEmpty) {
                          return const Text('No QR codes found.');
                        }
                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: data.length,
                          itemBuilder: (context, i) {
                            final row = data[i];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              elevation: 2,
                              color: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // QR Image
                                    row['image_url'] != null
                                        ? GestureDetector(
                                            onTap: () {
                                              showDialog(
                                                context: context,
                                                builder: (_) => Dialog(
                                                  child: InteractiveViewer(
                                                    child: Image.network(
                                                      row['image_url'],
                                                      fit: BoxFit.contain,
                                                      errorBuilder: (context, error, stackTrace) =>
                                                          const Icon(Icons.broken_image, size: 100),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                            child: Image.network(
                                              row['image_url'],
                                              width: 60,
                                              height: 60,
                                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image),
                                            ),
                                          )
                                        : const Text('No Image'),
                                    const SizedBox(width: 16),
                                    // Details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          FutureBuilder(
                                            future: Supabase.instance.client
                                                .from('users')
                                                .select('full_name')
                                                .eq('id', row['uploaded_by'])
                                                .maybeSingle(),
                                            builder: (context, AsyncSnapshot<dynamic> userSnapshot) {
                                              if (userSnapshot.connectionState == ConnectionState.waiting) {
                                                return const SizedBox(width: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                                              }
                                              if (userSnapshot.hasError || userSnapshot.data == null) {
                                                return const Text('Unknown');
                                              }
                                              return Text(
                                                userSnapshot.data['full_name'] ?? '',
                                                style: const TextStyle(fontWeight: FontWeight.bold, color: kText),
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Date Uploaded: ${row['created_at']?.toString() ?? ''}',
                                            style: const TextStyle(fontSize: 13, color: kSubText),
                                          ),
                                          const SizedBox(height: 4),
                                          FutureBuilder(
                                            future: Supabase.instance.client
                                                .from('users')
                                                .select('full_name')
                                                .eq('id', row['userdeceased'])
                                                .maybeSingle(),
                                            builder: (context, AsyncSnapshot<dynamic> userSnapshot) {
                                              if (userSnapshot.connectionState == ConnectionState.waiting) {
                                                return const SizedBox(width: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                                              }
                                              if (userSnapshot.hasError || userSnapshot.data == null) {
                                                return const Text('Unknown');
                                              }
                                              return Text(
                                                'Deceased: ${userSnapshot.data['full_name'] ?? ''}',
                                                style: const TextStyle(fontSize: 13, color: kSubText),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Action
                                    FutureBuilder(
                                      future: Supabase.instance.client
                                          .from('payments')
                                          .select('id')
                                          .eq('user_id', row['uploaded_by'])
                                          .eq('userdeceased', row['userdeceased'])
                                          .eq('status', 'paid')
                                          .maybeSingle(),
                                      builder: (context, AsyncSnapshot<dynamic> paymentSnapshot) {
                                        if (paymentSnapshot.connectionState == ConnectionState.waiting) {
                                          return const SizedBox(
                                            width: 80,
                                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                          );
                                        }
                                        final alreadyPaid = paymentSnapshot.data != null;
                                        if (alreadyPaid) {
                                          return const Chip(
                                            label: Text('Paid', style: TextStyle(color: Colors.white)),
                                            backgroundColor: Colors.green,
                                          );
                                        }
                                        return ElevatedButton(
                                          child: const Text('Pay'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: kAccent,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder: (context) {
                                                final TextEditingController amountController = TextEditingController();
                                                final requiredAmount = row['amount']?.toString() ?? '0';
                                                double? enteredAmount;
                                                bool isLoading = false;

                                                return StatefulBuilder(
                                                  builder: (context, setState) {
                                                    return AlertDialog(
                                                      title: const Text('Enter Amount'),
                                                      content: isLoading
                                                          ? const Center(child: CircularProgressIndicator())
                                                          : Column(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                const SizedBox(height: 8),
                                                                TextField(
                                                                  controller: amountController,
                                                                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                                                                  decoration: InputDecoration(
                                                                    labelText: 'Amount',
                                                                    border: OutlineInputBorder(),
                                                                    helperText: 'Required: ₱$requiredAmount',
                                                                  ),
                                                                  onChanged: (value) {
                                                                    setState(() {
                                                                      enteredAmount = double.tryParse(value);
                                                                    });
                                                                  },
                                                                ),
                                                              ],
                                                            ),
                                                      actions: isLoading
                                                          ? []
                                                          : [
                                                              TextButton(
                                                                onPressed: () => Navigator.of(context).pop(),
                                                                child: const Text('Cancel'),
                                                              ),
                                                              ElevatedButton(
                                                                onPressed: (enteredAmount != null && enteredAmount.toString() == requiredAmount)
                                                                    ? () async {
                                                                        final amount = amountController.text.trim();
                                                                        if (amount.isNotEmpty) {
                                                                          setState(() => isLoading = true);
                                                                          final currentUser = Supabase.instance.client.auth.currentUser;
                                                                          final collectedBy = currentUser?.id;

                                                                          final paymentData = {
                                                                            'user_id': row['uploaded_by'],
                                                                            'collected_by': collectedBy,
                                                                            'datepaidamount': DateTime.now().toUtc().toIso8601String(),
                                                                            'payment_id': row['userdeceased'],
                                                                            'userdeceased': row['userdeceased'],
                                                                            'dayung_unit_id': row['dayung_unit_id'],
                                                                            'paid_at': DateTime.now().toUtc().toIso8601String(),
                                                                            'created_at': DateTime.now().toUtc().toIso8601String(),
                                                                            'amount': amount,
                                                                            'status': 'paid',
                                                                          };

                                                                          try {
                                                                            await Supabase.instance.client.from('payments').insert(paymentData);
                                                                            Navigator.of(context).pop();
                                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                                              SnackBar(content: Text('Payment saved: ₱$amount')),
                                                                            );
                                                                          } catch (e) {
                                                                            Navigator.of(context).pop();
                                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                                              SnackBar(content: Text('Error saving payment: $e')),
                                                                            );
                                                                          }
                                                                        }
                                                                      }
                                                                    : null,
                                                                child: const Text('Save Payment'),
                                                              ),
                                                            ],
                                                    );
                                                  },
                                                );
                                              },
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ],
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
            ),
          ],
        ),
      ),
    );
  }
}