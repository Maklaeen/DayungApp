import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

// Color palette
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);
const kPrimary = Color(0xFF0D47A1);
const kWarn = Color(0xFFF57C00);

class GcashQrPage extends StatefulWidget {
  final dynamic dayungUnitId; // Accept dayungUnitId

  const GcashQrPage({super.key, required this.dayungUnitId});

  @override
  State<GcashQrPage> createState() => _GcashQrPageState();
}

class _GcashQrPageState extends State<GcashQrPage> {
  File? _qrImage;
  Uint8List? _qrImageBytes;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _gcashNumberController = TextEditingController(); // <-- Add this
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // State variables for displaying saved QR image and name
  String? _savedQrImageUrl;
  String? _savedQrName;
  bool _hasQrForUnit = false; // <-- Add this
  bool _showUpdateSuccess = false; // <-- Add this
  bool _showNoChanges = false; // <-- Add this
  bool _isLoading = false; // <-- Add this

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

  Future<void> _loadLatestSavedQr() async {
    try {
      print('Loading latest saved QR...');
      final response = await Supabase.instance.client
          .from('gcash_qr_uploads')
          .select('qr_image_url, name, gcash_number')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .order('created_at', ascending: false)
          .limit(1);

      print('Response: $response');
      if (response.isNotEmpty) {
        setState(() {
          _savedQrImageUrl = response[0]['qr_image_url'];
          _savedQrName = response[0]['name'];
          _hasQrForUnit = true;
          _nameController.text = _savedQrName ?? '';
          _gcashNumberController.text = response[0]['gcash_number'] ?? '';
        });
      } else {
        setState(() {
          _hasQrForUnit = false;
          _nameController.clear();
          _gcashNumberController.clear();
        });
      }
    } catch (e) {
      print('Error loading QR: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading QR: $e')),
      );
      setState(() {
        _hasQrForUnit = false;
        _nameController.clear();
        _gcashNumberController.clear();
      });
    }
  }

  void _saveQrCode() async {
    final name = _nameController.text.trim();
    final gcashNumber = _gcashNumberController.text.trim(); // <-- Get value
    if ((name.isEmpty && _qrImageBytes == null) || gcashNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name, GCash number, or select a QR image.')),
      );
      return;
    }

    setState(() {
      _isLoading = true; // <-- Start loading
    });

    try {
      String? imageUrl;
      if (_qrImageBytes != null) {
        final fileBytes = _qrImageBytes!;
        final fileName = 'gcash_qr_${DateTime.now().millisecondsSinceEpoch}.png';
        await Supabase.instance.client.storage
            .from('gcash_qr_images')
            .uploadBinary(fileName, fileBytes, fileOptions: const FileOptions(contentType: 'image/png'));

        imageUrl = Supabase.instance.client.storage
            .from('gcash_qr_images')
            .getPublicUrl(fileName);
      }

      final currentUser = Supabase.instance.client.auth.currentUser;

      // Check if QR already exists for this unit
      final existing = await Supabase.instance.client
          .from('gcash_qr_uploads')
          .select('id, name, qr_image_url, gcash_number') // <-- Add gcash_number
          .eq('dayung_unit_id', widget.dayungUnitId)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        // Prepare update data
        final updateData = <String, dynamic>{
          'updated_at': DateTime.now().toIso8601String(),
          'uploaded_by': currentUser?.id,
        };
        if (name.isNotEmpty && name != existing['name']) {
          updateData['name'] = name;
        }
        if (gcashNumber.isNotEmpty && gcashNumber != existing['gcash_number']) { // <-- Add this
          updateData['gcash_number'] = gcashNumber;
        }
        if (imageUrl != null) {
          updateData['qr_image_url'] = imageUrl;
        }
        if (updateData.length > 2) { // Only update if something changed
          await Supabase.instance.client.from('gcash_qr_uploads').update(updateData).eq('id', existing['id']);

          setState(() {
            _showUpdateSuccess = true; // Show success UI
          });
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _showUpdateSuccess = false);
          });
        } else {
          setState(() {
            _showNoChanges = true; // Show warning UI
          });
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _showNoChanges = false);
          });
        }
      } else {
        // Insert new QR
        if (name.isEmpty || gcashNumber.isEmpty || imageUrl == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter a name, GCash number, and select a QR image.')),
          );
          return;
        }
        await Supabase.instance.client.from('gcash_qr_uploads').insert({
          'name': name,
          'gcash_number': gcashNumber, // <-- Add this
          'qr_image_url': imageUrl,
          'created_at': DateTime.now().toIso8601String(),
          'uploaded_by': currentUser?.id,
          'dayung_unit_id': widget.dayungUnitId,
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GCash QR saved!')),
        );
      }

      // Clear form and reload latest QR from database
      setState(() {
        _nameController.clear();
        _gcashNumberController.clear(); // <-- Clear controller
        _qrImage = null;
        _qrImageBytes = null;
      });
      await _loadLatestSavedQr();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false; // <-- Stop loading
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchQrCodes() async {
    final response = await Supabase.instance.client
        .from('gcash_qr_codes')
        .select('image_url, uploaded_by, created_at, userdeceased, dayung_unit_id, amount, death_notice_id') // <-- add death_notice_id here
        .eq('dayung_unit_id', widget.dayungUnitId)
        .order('created_at', ascending: false);

    final List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(response);

    // Fetch names for uploaded_by and userdeceased
    for (final row in data) {
      // Fetch uploaded_by name
      if (row['uploaded_by'] != null) {
        final user = await Supabase.instance.client
            .from('users')
            .select('full_name')
            .eq('id', row['uploaded_by'])
            .maybeSingle();
        row['uploaded_by_name'] = user != null ? user['full_name'] : '';
      } else {
        row['uploaded_by_name'] = '';
      }
      // Fetch userdeceased name
      if (row['userdeceased'] != null) {
        final deceased = await Supabase.instance.client
            .from('users')
            .select('full_name')
            .eq('id', row['userdeceased'])
            .maybeSingle();
        row['userdeceased_name'] = deceased != null ? deceased['full_name'] : '';
      } else {
        row['userdeceased_name'] = '';
      }
    }

    return data;
  }

  @override
  void initState() {
    super.initState();
    _loadLatestSavedQr();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _gcashNumberController.dispose();
    _searchController.dispose();
    super.dispose();
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
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left: Form
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Add New GCash QR',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kText),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 180,
                                        child: TextField(
                                          controller: _nameController,
                                          decoration: const InputDecoration(
                                            labelText: 'GCash Name',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                 SizedBox(
  width: 140,
  child: TextField(
    controller: _gcashNumberController,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    maxLength: 11, // <-- Limit to 11 digits
    decoration: const InputDecoration(
      labelText: 'GCash Number',
      border: OutlineInputBorder(),
      counterText: '', // Hide character counter if you want
    ),
                                        ),
                                      ),
                                    ],
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
                                    icon: _isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(_hasQrForUnit ? Icons.update : Icons.save),
                                    label: Text(_hasQrForUnit ? 'Update QR' : 'Save QR'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kAccent,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: _isLoading ? null : _saveQrCode, // <-- Disable if loading
                                  ),
                                  if (_showUpdateSuccess)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Row(
                                        children: const [
                                          Icon(Icons.check_circle, color: Colors.green),
                                          SizedBox(width: 8),
                                          Text(
                                            'GCash QR updated',
                                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (_showNoChanges) // <-- Add this block
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Row(
                                        children: const [
                                          Icon(Icons.warning, color: Colors.orange),
                                          SizedBox(width: 8),
                                          Text(
                                            'No changes to update.',
                                            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Right: Display saved QR and name
                            if (_savedQrImageUrl != null && _savedQrName != null) ...[
                              const SizedBox(width: 24),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    _savedQrName!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: kText,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  GestureDetector(
                                    onTap: () {
                                      showDialog(
                                        context: context,
                                        builder: (_) => Dialog(
                                          child: InteractiveViewer(
                                            child: Image.network(
                                              _savedQrImageUrl!,
                                              fit: BoxFit.contain,
                                              errorBuilder: (context, error, stackTrace) =>
                                                const Icon(Icons.broken_image, size: 100),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    child: Image.network(
                                      _savedQrImageUrl!,
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                        const Icon(Icons.broken_image, size: 80),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Saved QRs
                    const Text(
                      'Payments collected via GCash',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 12),
                    // --- Search Bar ---
                    TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: 'Search by name',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.trim().toLowerCase();
                        });
                      },
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
                        // --- Filter data by search query ---
                        final filteredData = _searchQuery.isEmpty
                            ? data
                            : data.where((row) {
                                // You may want to cache user names for better performance
                                final uploadedByName = row['uploaded_by_name']?.toString().toLowerCase() ?? '';
                                final deceasedName = row['userdeceased_name']?.toString().toLowerCase() ?? '';
                                return uploadedByName.contains(_searchQuery) ||
                                       deceasedName.contains(_searchQuery);
                              }).toList();

                        if (filteredData.isEmpty) {
                          return const Text('No QR codes found.');
                        }
                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredData.length,
                          itemBuilder: (context, i) {
                            final row = filteredData[i];
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
                                                                            'death_notice_id': row['death_notice_id'], // <-- Add this line
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
                                          child: const Text('Pay'),
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

class UploadQrScreen extends StatefulWidget {
  const UploadQrScreen({super.key});

  @override
  _UploadQrScreenState createState() => _UploadQrScreenState();
}

class _UploadQrScreenState extends State<UploadQrScreen> {
  bool isQrUploaded = false; // Flag to track if QR is uploaded

  void uploadQrCode() {
    if (isQrUploaded) {
      // Show a message if the QR code has already been uploaded
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('QR code has already been uploaded!')),
      );
      return;
    }

    // Simulate QR code upload
    setState(() {
      isQrUploaded = true; // Mark as uploaded
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('QR code uploaded successfully!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Upload QR Code'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: uploadQrCode,
          child: Text(isQrUploaded ? 'QR Uploaded' : 'Upload QR Code'),
        ),
      ),
    );
  }
}

void main() {
  runApp(MaterialApp(
    home: UploadQrScreen(),
  ));
}