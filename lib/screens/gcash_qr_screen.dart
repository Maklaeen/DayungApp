import 'package:flutter/material.dart';

class GcashQrScreen extends StatelessWidget {
  const GcashQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Replace this with your actual data fetching logic
    final List<String> qrUrls = [
      'https://example.com/qr1.png',
      'https://example.com/qr2.png',
      'https://example.com/qr3.png',
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Uploaded GCash QR Codes'),
      ),
      body: qrUrls.isEmpty
          ? const Center(child: Text('No QR codes uploaded yet.'))
          : GridView.builder(
              padding: const EdgeInsets.all(8.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8.0,
                mainAxisSpacing: 8.0,
              ),
              itemCount: qrUrls.length,
              itemBuilder: (context, index) {
                return Card(
                  elevation: 4.0,
                  child: Image.network(
                    qrUrls[index],
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
    );
  }
}