import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class GcashQrPage extends StatefulWidget {
  const GcashQrPage({super.key});

  @override
  State<GcashQrPage> createState() => _GcashQrPageState();
}

class _GcashQrPageState extends State<GcashQrPage> {
  File? _qrImage;
  Uint8List? _qrImageBytes; // Add this line
  final TextEditingController _nameController = TextEditingController();

  Future<void> _pickQrImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _qrImage = File(pickedFile.path);
        _qrImageBytes = bytes; // Store bytes for web
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

      // Insert into the new table instead of 'gcash_qr_codes'
      final currentUser = Supabase.instance.client.auth.currentUser;

      await Supabase.instance.client.from('gcash_qr_uploads').insert({
        'name': name,
        'qr_image_url': imageUrl,
        'created_at': DateTime.now().toIso8601String(),
        'uploaded_by': currentUser?.id, // Add this line
        // Add other fields as needed
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
        .select('image_url, uploaded_by, created_at, userdeceased, dayung_unit_id, amount') // <-- add dayung_unit_id
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GCash QR'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(top: .0), // Add top padding
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, // Align to left
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add QR'),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          File? tempQrImage;
                          Uint8List? tempQrImageBytes;
                          final TextEditingController tempNameController = TextEditingController();
                          bool isUploading = false;

                          // Add a Future to fetch the user's QR upload
                          Future<Map<String, dynamic>?> fetchUserQrUpload() async {
                            final currentUser = Supabase.instance.client.auth.currentUser;
                            if (currentUser == null) return null;
                            final response = await Supabase.instance.client
                                .from('gcash_qr_uploads')
                                .select('qr_image_url, name')
                                .eq('uploaded_by', currentUser.id)
                                .order('created_at', ascending: false)
                                .limit(1)
                                .maybeSingle();
                            return response;
                          }

                          return StatefulBuilder(
                            builder: (context, setState) {
                              Future<void> pickQrImage() async {
                                final picker = ImagePicker();
                                final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                                if (pickedFile != null) {
                                  final bytes = await pickedFile.readAsBytes();
                                  setState(() {
                                    tempQrImage = File(pickedFile.path);
                                    tempQrImageBytes = bytes;
                                  });
                                }
                              }

                              return AlertDialog(
                                title: const Text('Add GCash QR'),
                                content: isUploading
                                    ? const Center(child: CircularProgressIndicator())
                                    : Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TextField(
                                            controller: tempNameController,
                                            decoration: const InputDecoration(
                                              labelText: 'GCash Name',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          tempQrImageBytes != null
                                              ? Image.memory(tempQrImageBytes!, width: 100, height: 100)
                                              : const SizedBox(),
                                          TextButton.icon(
                                            icon: const Icon(Icons.upload),
                                            label: const Text('Upload QR'),
                                            onPressed: pickQrImage,
                                          ),
                                          // --- Display user's uploaded QR below the Upload QR button ---
                                          FutureBuilder<Map<String, dynamic>?>(
                                            future: fetchUserQrUpload(),
                                            builder: (context, snapshot) {
                                              if (snapshot.connectionState == ConnectionState.waiting) {
                                                return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                                              }
                                              final data = snapshot.data;
                                              if (data == null || data['qr_image_url'] == null) {
                                                return const Text('No QR uploaded yet.');
                                              }
                                              return Column(
                                                children: [
                                                  const SizedBox(height: 16),
                                                  Text('Your Uploaded QR:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                  const SizedBox(height: 8),
                                                  GestureDetector(
                                                    onTap: () {
                                                      showDialog(
                                                        context: context,
                                                        builder: (_) => Dialog(
                                                          child: InteractiveViewer(
                                                            child: Image.network(
                                                              data['qr_image_url'],
                                                              fit: BoxFit.contain,
                                                              errorBuilder: (context, error, stackTrace) =>
                                                                  const Icon(Icons.broken_image, size: 100),
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                    child: Image.network(
                                                      data['qr_image_url'],
                                                      width: 100,
                                                      height: 100,
                                                      errorBuilder: (context, error, stackTrace) =>
                                                          const Icon(Icons.broken_image, size: 60),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(data['name'] ?? '', style: const TextStyle(fontSize: 16)),
                                                ],
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                actions: isUploading
                                    ? []
                                    : [
                                        TextButton(
                                          onPressed: () => Navigator.of(context).pop(),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () async {
                                            final name = tempNameController.text.trim();
                                            if (name.isEmpty || tempQrImageBytes == null) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Please enter a name and select a QR image.')),
                                              );
                                              return;
                                            }
                                            setState(() => isUploading = true);
                                            try {
                                              final fileBytes = tempQrImageBytes!;
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

                                              Navigator.of(context).pop();
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('GCash QR saved!')),
                                              );
                                              setState(() {
                                                _nameController.clear();
                                                _qrImage = null;
                                                _qrImageBytes = null;
                                              });
                                            } catch (e) {
                                              Navigator.of(context).pop();
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Error saving: $e')),
                                              );
                                            }
                                          },
                                          child: const Text('Save'),
                                        ),
                                      ],
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              // --- End new button block ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Saved GCash QR Codes',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  // You can remove the old "Add QR" button here if you want only one
                ],
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _fetchQrCodes(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  }
                  if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}');
                  }
                  final data = snapshot.data ?? [];
                  if (data.isEmpty) {
                    return const Text('No QR codes found.');
                  }
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Screenshot of the GCash receipt')),
                        DataColumn(label: Text('Member')),
                        DataColumn(label: Text('Date Uploaded')),
                        DataColumn(label: Text('Deceased Member')),
                        DataColumn(label: Text('Action')), 
                      ],
                      rows: data.map((row) {
                        return DataRow(
                          cells: [
                            DataCell(
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
                                                errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 100),
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
                            ),
                            DataCell(
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
                                  return Text(userSnapshot.data['full_name'] ?? '');
                                },
                              ),
                            ),
                            DataCell(Text(row['created_at']?.toString() ?? '')),
                            DataCell(
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
                                  return Text(userSnapshot.data['full_name'] ?? '');
                                },
                              ),
                            ),
                            DataCell(
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
                                    onPressed: () {
                                      print('Pay clicked by user: ${row['uploaded_by']}');
                                      showDialog(
                                        context: context,
                                        builder: (context) {
                                          final TextEditingController amountController = TextEditingController();
                                          final requiredAmount = row['amount']?.toString() ?? '0';
                                          double? enteredAmount;
                                          bool isLoading = false; // Add loading state

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
                                                                    setState(() => isLoading = true); // Show loading
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
                                                                      Navigator.of(context).pop(); // Close dialog
                                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                                        SnackBar(content: Text('Payment saved: ₱$amount')),
                                                                      );
                                                                    } catch (e) {
                                                                      Navigator.of(context).pop(); // Close dialog
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
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}