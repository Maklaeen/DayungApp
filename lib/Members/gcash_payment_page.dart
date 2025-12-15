import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

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

  Future<void> uploadImage(String setAmountId, String userdeceased, int amount) async {
    setState(() => _isUploading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      // Check if already paid
      final paid = await isPaid(setAmountId, userdeceased);
      if (paid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment already marked as paid. No need to upload receipt.')),
        );
        return;
      }

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile == null) return;

      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name}';
      final bytes = await pickedFile.readAsBytes();

      final storageResponse = await Supabase.instance.client.storage
          .from('gcash_qr_images')
          .uploadBinary(fileName, bytes);

      if (storageResponse.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload failed.')),
        );
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GCash Payment'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double width = constraints.maxWidth;

          // ● Mobile: <600
          // ● Tablet: <1000
          // ● Desktop/Web: >=1000
          final bool isMobile = width < 600;
          final bool isTablet = width >= 600 && width < 1000;

          final double fontSize = isMobile ? 12 : isTablet ? 14 : 16;
          final double headingSize = isMobile ? 14 : isTablet ? 16 : 18;
          final double padding = isMobile ? 6 : isTablet ? 10 : 14;

          return Stack(
            children: [
              Padding(
                padding: EdgeInsets.all(padding),
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: fetchSetAmounts(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final setAmounts = snapshot.data!;
                    if (setAmounts.isEmpty) {
                      return Center(
                        child: Text("No data found.",
                            style: TextStyle(fontSize: fontSize)),
                      );
                    }

                    return SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: isMobile ? width : width * 0.7,
                          ),
                          child: DataTable(
                            columnSpacing: isMobile ? 8 : 20,
                            headingTextStyle: TextStyle(
                                fontSize: headingSize,
                                fontWeight: FontWeight.bold),
                            dataTextStyle: TextStyle(fontSize: fontSize),
                            columns: const [
                              DataColumn(label: Text('User')),
                              DataColumn(label: Text('Amount')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Upload')),
                              DataColumn(label: Text('View')),
                            ],
                            rows: setAmounts.map((data) {
                              final fullName = data['users']?['full_name'] ??
                                  data['userdeceased'] ??
                                  '';

                              return DataRow(
                                cells: [
                                  DataCell(
                                    SizedBox(
                                      width: isMobile ? 80 : 150,
                                      child: Text(fullName,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                  ),
                                  DataCell(
                                    Text('${data['amount']}'),
                                  ),

                                  /// STATUS
                                  DataCell(
                                    FutureBuilder<bool>(
                                      future: isPaid(data['id'].toString(), data['userdeceased']),
                                      builder: (context, paidSnap) {
                                        if (paidSnap.connectionState != ConnectionState.done) {
                                          return const Text("...");
                                        }
                                        if (paidSnap.data == true) {
                                          return Text(
                                            "Paid",
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          );
                                        }
                                        // Fallback to old logic for Pending/Unpaid
                                        return FutureBuilder<List<Map<String, dynamic>>>(
                                          future: Supabase.instance.client
                                              .from('gcash_qr_codes')
                                              .select('image_url')
                                              .eq('set_amount_id', data['id'])
                                              .eq('userdeceased', data['userdeceased'])
                                              .order('id', ascending: false)
                                              .limit(1),
                                          builder: (context, snap) {
                                            final hasImage = snap.hasData &&
                                                snap.data!.isNotEmpty &&
                                                snap.data![0]['image_url'] != null;

                                            return Text(
                                              hasImage ? "Pending" : "Unpaid",
                                              style: TextStyle(
                                                color: hasImage ? Colors.orange : Colors.red,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),

                                  /// UPLOAD BUTTON
                                  DataCell(
                                    FutureBuilder<bool>(
                                      future: isPaid(data['id'].toString(), data['userdeceased']),
                                      builder: (context, paidSnap) {
                                        final isPaidValue = paidSnap.data == true;
                                        return ElevatedButton(
                                          onPressed: (_isUploading || isPaidValue)
                                              ? null
                                              : () async {
                                                  await uploadImage(
                                                    data['id'].toString(),
                                                    data['userdeceased'],
                                                    int.parse(data['amount'].toString()),
                                                  );
                                                  setState(() {});
                                                },
                                          child: Text(
                                            isMobile ? "Upload" : "Upload Receipt",
                                            style: TextStyle(fontSize: fontSize),
                                          ),
                                        );
                                      },
                                    ),
                                  ),

                                  /// VIEW BUTTON
                                  DataCell(
                                    FutureBuilder<List<Map<String, dynamic>>>(
                                      future: Supabase.instance.client
                                          .from('gcash_qr_codes')
                                          .select('image_url')
                                          .eq('set_amount_id', data['id'])
                                          .eq('userdeceased',
                                              data['userdeceased'])
                                          .order('id', ascending: false)
                                          .limit(1),
                                      builder: (context, snap) {
                                        final hasImage = snap.hasData &&
                                            snap.data!.isNotEmpty &&
                                            snap.data![0]['image_url'] != null;

                                        if (!hasImage) {
                                          return Text("-");
                                        }

                                        final imageUrl =
                                            snap.data![0]['image_url'];

                                        return ElevatedButton(
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder: (context) =>
                                                  AlertDialog(
                                                content: SizedBox(
                                                  width: isMobile ? width * 0.8 : 400,
                                                  child: Image.network(imageUrl),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    child: const Text("Close"),
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                  )
                                                ],
                                              ),
                                            );
                                          },
                                          child: Text("View",
                                              style: TextStyle(
                                                  fontSize: fontSize)),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              /// LOADING OVERLAY
              if (_isUploading)
                Container(
                  color: Colors.black45,
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
