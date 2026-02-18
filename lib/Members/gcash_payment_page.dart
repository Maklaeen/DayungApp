import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

// Color palette
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);
const kPrimary = Color(0xFF0D47A1);
const kWarn = Color(0xFFF57C00);

class GCashPaymentPage extends StatefulWidget {
  final int? dayungUnitId;
  const GCashPaymentPage({super.key, this.dayungUnitId});

  @override
  State<GCashPaymentPage> createState() => _GCashPaymentPageState();
}

class _GCashPaymentPageState extends State<GCashPaymentPage> {
  bool _isUploading = false;
  String _searchQuery = ""; // Add a variable to store the search query

  Future<List<Map<String, dynamic>>> fetchSetAmounts() async {
    final data = await Supabase.instance.client
        .from('set_amount')
        .select('id, userdeceased, amount, users(full_name)')
        .then((value) => value as List<dynamic>);
    return data.cast<Map<String, dynamic>>();
  }

  Future<bool> isPaid(String setAmountId, String userdeceased) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;
    final data = await Supabase.instance.client
        .from('payments')
        .select('id')
        .eq('userdeceased', userdeceased)
        .eq('user_id', user.id)
        .eq('status', 'paid')
        .maybeSingle();
    return data != null;
  }

  Future<void> uploadImage(
    String setAmountId,
    String userdeceased,
    int amount, {
    required int deathNoticeId,
  }) async {
    setState(() => _isUploading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      final paid = await isPaid(setAmountId, userdeceased);
      if (paid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payment already marked as paid. No need to upload receipt.',
            ),
          ),
        );
        return;
      }

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile == null) return;

      final imageBytes = await pickedFile.readAsBytes();

      // Show confirmation dialog before uploading
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Upload'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Are you sure you want to upload this receipt?'),
              const SizedBox(height: 16),
              Image.memory(imageBytes, height: 180),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              child: const Text('Upload'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );

      if (confirm != true) {
        setState(() => _isUploading = false);
        return;
      }

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name}';
      final bytes = await pickedFile.readAsBytes();

      final storageResponse = await Supabase.instance.client.storage
          .from('gcash_qr_images')
          .uploadBinary(fileName, bytes);

      if (storageResponse.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Upload failed.')));
        return;
      }

      final imageUrl = Supabase.instance.client.storage
          .from('gcash_qr_images')
          .getPublicUrl(fileName);

      await Supabase.instance.client.from('gcash_qr_codes').insert({
        'set_amount_id': setAmountId,
        'userdeceased': userdeceased,
        'amount': amount,
        'image_url': imageUrl,
        'uploaded_by': user.id,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String().substring(0, 19),
        'dayung_unit_id': widget.dayungUnitId,
        'death_notice_id': deathNoticeId,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image uploaded successfully!')),
      );

      // Show confirmation dialog
      final uploadAgain = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Upload Complete'),
          actions: [
            TextButton(
              child: const Text('No'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              child: const Text('Yes'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );

      if (uploadAgain == true) {
        // Call uploadImage again with the same parameters
        await uploadImage(
          setAmountId,
          userdeceased,
          amount,
          deathNoticeId: deathNoticeId,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isUploading = false);
    }
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
                    icon: const Icon(
                      Icons.chevron_left,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Icon(Icons.qr_code_2, color: Colors.white, size: 24),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'GCash Payment',
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
            // Search Bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: "Search by name or deceased user...",
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value
                        .toLowerCase(); // Update the search query
                  });
                },
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: fetchSetAmounts(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: kAccent),
                      );
                    }
                    final setAmounts = snapshot.data!;
                    if (setAmounts.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.info_outline, color: kSubText, size: 48),
                            const SizedBox(height: 16),
                            const Text(
                              "No payment data found.",
                              style: TextStyle(color: kSubText, fontSize: 18),
                            ),
                          ],
                        ),
                      );
                    }

                    // Filter the list based on the search query
                    final filteredSetAmounts = setAmounts.where((data) {
                      final fullName = data['users']?['full_name'] ?? '';
                      final userDeceased = data['userdeceased'] ?? '';
                      return fullName.toLowerCase().contains(_searchQuery) ||
                          userDeceased.toLowerCase().contains(_searchQuery);
                    }).toList();

                    if (filteredSetAmounts.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off, color: kSubText, size: 48),
                            const SizedBox(height: 16),
                            const Text(
                              "No results found.",
                              style: TextStyle(color: kSubText, fontSize: 18),
                            ),
                          ],
                        ),
                      );
                    }

                    return FutureBuilder<List<bool>>(
                      future: Future.wait(
                        filteredSetAmounts.map(
                          (data) => isPaid(
                            data['id'].toString(),
                            data['userdeceased'],
                          ),
                        ),
                      ),
                      builder: (context, statusSnapshot) {
                        if (!statusSnapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(color: kAccent),
                          );
                        }
                        final statuses = statusSnapshot.data!;
                        final pending = <Map<String, dynamic>>[];
                        final paid = <Map<String, dynamic>>[];
                        for (int i = 0; i < filteredSetAmounts.length; i++) {
                          if (statuses[i]) {
                            paid.add(filteredSetAmounts[i]);
                          } else {
                            pending.add(filteredSetAmounts[i]);
                          }
                        }
                        final sortedList = [...pending, ...paid];

                        return ListView.builder(
                          itemCount: sortedList.length,
                          itemBuilder: (context, i) {
                            final data = sortedList[i];
                            final fullName =
                                data['users']?['full_name'] ??
                                data['userdeceased'] ??
                                '';
                            final amount = data['amount'];
                            final paidStatus =
                                i >=
                                pending
                                    .length; // Paid if index is after pending
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 10),
                              elevation: 3,
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 18,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fullName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: kText,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Amount: ₱ $amount',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        color: kAccent,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        // Status
                                        Text(
                                          paidStatus ? "Paid" : "Pending",
                                          style: TextStyle(
                                            color: paidStatus
                                                ? Colors.green
                                                : kWarn,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const Spacer(),
                                        // Upload Button
                                        ElevatedButton.icon(
                                          icon: const Icon(
                                            Icons.upload,
                                            size: 18,
                                          ),
                                          label: Text(
                                            isMobile ? "Upload" : "Upload Receipt",
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: kAccent,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                          onPressed: (_isUploading || paidStatus)
                                              ? null
                                              : () async {
                                                  // 1. Fetch QR code info for this dayung_unit_id
                                                  final qrData = await Supabase.instance.client
    .from('gcash_qr_uploads')
    .select()
    .eq('dayung_unit_id', (widget.dayungUnitId ?? 0).toString())
    .maybeSingle();

                                                  if (qrData == null) {
                                                      debugPrint('DEBUG: No QR code found for dayung_unit_id: ${widget.dayungUnitId}');
  final qrList = await Supabase.instance.client
      .from('gcash_qr_uploads')
      .select();
  debugPrint('DEBUG: All QR uploads: $qrList');
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(content: Text('No QR code found for this unit.')),
                                                    );
                                                    return;
                                                  }

                                                  // 2. Show QR code dialog
                                                // ...existing code...
final proceed = await showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Gcash QR Code'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(qrData['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (qrData['gcash_number'] != null && qrData['gcash_number'].toString().isNotEmpty)
          Text(
            'Gcash Number: ${qrData['gcash_number']}',
            style: const TextStyle(fontSize: 15, color: kSubText),
          ),
        const SizedBox(height: 12),
        if (qrData['qr_image_url'] != null)
          GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => Dialog(
                  backgroundColor: Colors.transparent,
                  child: InteractiveViewer(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.white,
                      child: Image.network(
                        qrData['qr_image_url'],
                        width: MediaQuery.of(context).size.width * 0.85,
                        height: MediaQuery.of(context).size.height * 0.65,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              );
            },
            child: Image.network(qrData['qr_image_url'], height: 180),
          ),
        const SizedBox(height: 50),
        const Text('Please pay using the QR code above.'),
      ],
    ),
    actions: [
      TextButton(
        child: const Text('Cancel'),
        onPressed: () => Navigator.of(context).pop(false),
      ),
      ElevatedButton(
        child: const Text('Upload Receipt'),
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  ),
);
// ...existing code...
                                                  // 3. If user chooses to upload, proceed with uploadImage
                                                  if (proceed == true) {
                                                    await uploadImage(
                                                      data['id'].toString(),
                                                      data['userdeceased'],
                                                      int.parse(data['amount'].toString()),
                                                      deathNoticeId: data['death_notice_id'] ?? 0,
                                                    );
                                                    setState(() {});
                                                  }
                                                },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            // Loading overlay
            if (_isUploading)
              Container(
                color: Colors.black45,
                child: const Center(
                  child: CircularProgressIndicator(color: kAccent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
