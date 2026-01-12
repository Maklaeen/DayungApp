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
    int amount,
  ) async {
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
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image uploaded successfully!')),
      );
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
                    return ListView.builder(
                      itemCount: setAmounts.length,
                      itemBuilder: (context, i) {
                        final data = setAmounts[i];
                        final fullName =
                            data['users']?['full_name'] ??
                            data['userdeceased'] ??
                            '';
                        final amount = data['amount'];
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
                                    FutureBuilder<bool>(
                                      future: isPaid(
                                        data['id'].toString(),
                                        data['userdeceased'],
                                      ),
                                      builder: (context, paidSnap) {
                                        if (!paidSnap.hasData)
                                          return const Text("...");
                                        final paid = paidSnap.data!;
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: paid
                                                ? Colors.green[50]
                                                : kWarn.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            paid ? "Paid" : "Pending",
                                            style: TextStyle(
                                              color: paid
                                                  ? Colors.green
                                                  : kWarn,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const Spacer(),
                                    // Upload Button
                                    FutureBuilder<bool>(
                                      future: isPaid(
                                        data['id'].toString(),
                                        data['userdeceased'],
                                      ),
                                      builder: (context, paidSnap) {
                                        final isPaidValue =
                                            paidSnap.data == true;
                                        return ElevatedButton.icon(
                                          icon: const Icon(
                                            Icons.upload,
                                            size: 18,
                                          ),
                                          label: Text(
                                            isMobile
                                                ? "Upload"
                                                : "Upload Receipt",
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: kAccent,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          onPressed:
                                              (_isUploading || isPaidValue)
                                              ? null
                                              : () async {
                                                  await uploadImage(
                                                    data['id'].toString(),
                                                    data['userdeceased'],
                                                    int.parse(
                                                      data['amount'].toString(),
                                                    ),
                                                  );
                                                  setState(() {});
                                                },
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    // View Button
                                    FutureBuilder<List<Map<String, dynamic>>>(
                                      future: Supabase.instance.client
                                          .from('gcash_qr_codes')
                                          .select('image_url')
                                          .eq('set_amount_id', data['id'])
                                          .eq(
                                            'userdeceased',
                                            data['userdeceased'],
                                          )
                                          .order('id', ascending: false)
                                          .limit(1),
                                      builder: (context, snap) {
                                        final hasImage =
                                            snap.hasData &&
                                            snap.data!.isNotEmpty &&
                                            snap.data![0]['image_url'] != null;
                                        if (!hasImage) {
                                          return Text(
                                            "-",
                                            style: TextStyle(color: kSubText),
                                          );
                                        }
                                        final imageUrl =
                                            snap.data![0]['image_url'];
                                        return ElevatedButton.icon(
                                          icon: const Icon(
                                            Icons.visibility,
                                            size: 18,
                                          ),
                                          label: const Text("View"),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: kAccent
                                                .withOpacity(0.8),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                content: SizedBox(
                                                  width: isMobile
                                                      ? width * 0.8
                                                      : 400,
                                                  child: Image.network(
                                                    imageUrl,
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    child: const Text("Close"),
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        );
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
