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
      // Use _qrImageBytes for upload (works on all platforms)
      final fileBytes = _qrImageBytes!;
      final fileName = 'gcash_qr_${DateTime.now().millisecondsSinceEpoch}.png';
      await Supabase.instance.client.storage
          .from('gcash_qr_images')
          .uploadBinary(fileName, fileBytes, fileOptions: const FileOptions(contentType: 'image/png'));

      final imageUrl = Supabase.instance.client.storage
          .from('gcash_qr_images')
          .getPublicUrl(fileName);

      await Supabase.instance.client.from('gcash_qr_codes').insert({
        'name': name,
        'qr_image_url': imageUrl,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GCash QR'),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _qrImageBytes != null
                  ? Image.memory(_qrImageBytes!, width: 180, height: 180)
                  : const Icon(Icons.qr_code_2_rounded, size: 120, color: Colors.blue),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'GCash Name',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _pickQrImage,
                icon: const Icon(Icons.add_photo_alternate),
                label: const Text('Add QR Image'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saveQrCode,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}