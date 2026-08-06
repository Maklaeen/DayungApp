import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String _searchQuery = "";

  Future<List<Map<String, dynamic>>> fetchPayments() async {
    final data = await Supabase.instance.client
        .from('payments')
        .select(
          'id, userdeceased, deceased_name, amount, status, user_id, users!payments_user_id_fkey(full_name)',
        )
        .then((value) => value as List<dynamic>);
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchSetAmounts() async {
    final data = await Supabase.instance.client
        .from('payments')
        .select(
          'id, userdeceased, deceased_name, amount, status, user_id, users!payments_user_id_fkey(full_name)',
        )
        .then((value) => value as List<dynamic>);
    return data.cast<Map<String, dynamic>>();
  }

  Future<bool> isPaid(String setAmountId) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || setAmountId.isEmpty) return false;

    final data = await Supabase.instance.client
        .from('payments')
        .select('status')
        .eq('id', setAmountId)
        .eq('user_id', user.id)
        .maybeSingle();

    return data?['status']?.toString().toLowerCase() == 'paid';
  }

  Future<Map<String, dynamic>?> getExistingUpload(String setAmountId) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;

    final data = await Supabase.instance.client
        .from('gcash_qr_codes')
        .select('id, image_url, created_at')
        .eq('set_amount_id', setAmountId)
        .eq('uploaded_by', user.id)
        .maybeSingle();

    return data;
  }

  Future<void> uploadImage(
    String setAmountId,
    String? userdeceased,
    int amount,
    String type,
  ) async {
    final isMembershipPayment = type == 'for_membership';
    if (!isMembershipPayment &&
        (userdeceased == null || userdeceased.isEmpty)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment record is missing deceased user info.'),
        ),
      );
      return;
    }
    setState(() => _isUploading = true);

    try {
      final messenger = ScaffoldMessenger.of(context);
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      final paid = await isPaid(setAmountId);
      if (!mounted) return;
      if (paid) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Payment already marked as paid. No need to upload receipt.',
            ),
          ),
        );
        return;
      }

      // Prevent multiple uploads for the same payment by the same user
      final existingUpload = await getExistingUpload(setAmountId);
      if (existingUpload != null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'You have already uploaded a receipt for this payment.',
            ),
          ),
        );
        return;
      }

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile == null) return;

      final imageBytes = await pickedFile.readAsBytes();
      if (!mounted) return;

      final refNoController = TextEditingController();

      bool isValidRefNo(String refNo) {
        final cleaned = refNo.replaceAll(' ', '');
        return cleaned.length >= 9 &&
            cleaned.length <= 13 &&
            RegExp(r'^\d+$').hasMatch(cleaned);
      }

      final confirm = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Confirm Upload'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Are you sure you want to upload this receipt?'),
                  const SizedBox(height: 16),
                  Image.memory(imageBytes, height: 180),
                  const SizedBox(height: 16),
                  TextField(
                    controller: refNoController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                      LengthLimitingTextInputFormatter(15),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Reference No.',
                      border: OutlineInputBorder(),
                      helperText:
                          'Please Input the Exact Reference No. shown in your GCash receipt',
                    ),
                    onChanged: (value) {
                      String digits = value.replaceAll(RegExp(r'\D'), '');
                      if (digits.length > 13) {
                        digits = digits.substring(0, 13);
                      }
                      String formatted = digits;
                      if (digits.length > 4 && digits.length <= 7) {
                        formatted =
                            '${digits.substring(0, 4)} ${digits.substring(4)}';
                      } else if (digits.length > 7) {
                        formatted =
                            '${digits.substring(0, 4)} ${digits.substring(4, 7)} ${digits.substring(7)}';
                      }
                      if (formatted != value) {
                        refNoController.value = TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(
                            offset: formatted.length,
                          ),
                        );
                      }
                      setDialogState(() {});
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(null),
                ),
                ElevatedButton(
                  onPressed: isValidRefNo(refNoController.text)
                      ? () => Navigator.of(context).pop({
                          'confirm': true,
                          'refNo': refNoController.text.replaceAll(' ', ''),
                        })
                      : null,
                  child: const Text('Upload'),
                ),
              ],
            ),
          );
        },
      );

      if (confirm == null || confirm['confirm'] != true) {
        setState(() => _isUploading = false);
        return;
      }

      final refNo = (confirm['refNo'] ?? '').toString();

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name}';
      final bytes = await pickedFile.readAsBytes();

      final storageResponse = await Supabase.instance.client.storage
          .from('gcash_qr_images')
          .uploadBinary(fileName, bytes);

      if (storageResponse.isEmpty) {
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(content: Text('Upload failed.')));
        return;
      }

      // Save only the file name in the database
      final dbUserDeceased = (userdeceased == null || userdeceased.isEmpty)
          ? null
          : userdeceased;

      await Supabase.instance.client.from('gcash_qr_codes').insert({
        'set_amount_id': setAmountId,
        'userdeceased': dbUserDeceased,
        'amount': amount,
        'image_url': fileName, // store file name only
        'uploaded_by': user.id,

        'type': type,
        'created_at': DateTime.now().toIso8601String().substring(0, 19),
        'dayung_unit_id': widget.dayungUnitId,
        'refno': refNo,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<String?> getBeneficiaryName(String beneficiaryId) async {
    final data = await Supabase.instance.client
        .from('beneficiaries')
        .select('full_name')
        .eq('id', beneficiaryId)
        .maybeSingle();
    return data?['full_name'];
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
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }
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
                      final deceasedName = data['deceased_name'] ?? '';
                      final userDeceased = data['userdeceased'] ?? '';
                      return deceasedName.toLowerCase().contains(
                            _searchQuery,
                          ) ||
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
                          (data) => isPaid(data['id'].toString()),
                        ),
                      ),
                      builder: (context, statusSnapshot) {
                        if (statusSnapshot.hasError) {
                          return Center(
                            child: Text('Error: ${statusSnapshot.error}'),
                          );
                        }
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
                            String fullName =
                                data['deceased_name'] ??
                                data['userdeceased'] ??
                                'Membership Payment';
                            final amount = data['amount'];
                            final paidStatus = i >= pending.length;
                            final setAmountId = data['id'].toString();

                            return FutureBuilder<Map<String, dynamic>?>(
                              future: getExistingUpload(setAmountId),
                              builder: (context, uploadSnapshot) {
                                if (uploadSnapshot.hasError) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: Text(
                                      'Error: ${uploadSnapshot.error}',
                                    ),
                                  );
                                }
                                final uploadData = uploadSnapshot.data;
                                final hasUpload = uploadData != null;

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                                  (_isUploading ||
                                                      paidStatus ||
                                                      hasUpload)
                                                  ? null
                                                  : () async {
                                                      // 1. Fetch QR code info for this dayung_unit_id
                                                      debugPrint(
                                                        'DEBUG: widget.dayungUnitId = [1m${widget.dayungUnitId}[0m',
                                                      );
                                                      final qrData = await Supabase
                                                          .instance
                                                          .client
                                                          .from(
                                                            'gcash_qr_uploads',
                                                          )
                                                          .select()
                                                          .eq(
                                                            'dayung_unit_id',
                                                            (widget.dayungUnitId ??
                                                                    0)
                                                                .toString(),
                                                          )
                                                          .maybeSingle();

                                                      if (qrData == null) {
                                                        debugPrint(
                                                          'DEBUG: No QR code found for dayung_unit_id: ${widget.dayungUnitId}',
                                                        );
                                                        final qrList =
                                                            await Supabase
                                                                .instance
                                                                .client
                                                                .from(
                                                                  'gcash_qr_uploads',
                                                                )
                                                                .select();
                                                        debugPrint(
                                                          'DEBUG: All QR uploads: $qrList',
                                                        );
                                                        if (!context.mounted) {
                                                          return;
                                                        }
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              'No QR code found for this unit.',
                                                            ),
                                                          ),
                                                        );
                                                        return;
                                                      }

                                                      // 2. Show QR code dialog
                                                      // ...existing code...
                                                      if (!context.mounted) {
                                                        return;
                                                      }
                                                      final proceed = await showDialog<bool>(
                                                        context: context,
                                                        builder: (context) => LayoutBuilder(
                                                          builder: (context, constraints) {
                                                            final isMobile =
                                                                constraints
                                                                    .maxWidth <
                                                                600;
                                                            return AlertDialog(
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      24,
                                                                    ),
                                                              ),
                                                              backgroundColor:
                                                                  Colors.white,
                                                              title: Center(
                                                                child: Column(
                                                                  children: [
                                                                    const Icon(
                                                                      Icons
                                                                          .qr_code_2,
                                                                      color:
                                                                          kAccent,
                                                                      size: 36,
                                                                    ),
                                                                    const SizedBox(
                                                                      height: 8,
                                                                    ),
                                                                    Text(
                                                                      'GCash QR Code',
                                                                      style: TextStyle(
                                                                        fontWeight:
                                                                            FontWeight.w700,
                                                                        fontSize:
                                                                            isMobile
                                                                            ? 20
                                                                            : 24,
                                                                        color:
                                                                            kAccent,
                                                                        letterSpacing:
                                                                            0.5,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                              content: SingleChildScrollView(
                                                                child: Column(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    if (qrData['name'] !=
                                                                        null)
                                                                      Text(
                                                                        qrData['name'],
                                                                        style: TextStyle(
                                                                          fontWeight:
                                                                              FontWeight.w600,
                                                                          fontSize:
                                                                              isMobile
                                                                              ? 15
                                                                              : 18,
                                                                          color:
                                                                              kText,
                                                                        ),
                                                                      ),
                                                                    const SizedBox(
                                                                      height:
                                                                          12,
                                                                    ),
                                                                    if (qrData['gcash_number'] !=
                                                                            null &&
                                                                        qrData['gcash_number']
                                                                            .toString()
                                                                            .isNotEmpty)
                                                                      Row(
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.center,
                                                                        children: [
                                                                          Flexible(
                                                                            child: Text(
                                                                              'Gcash Number: ${qrData['gcash_number']}',
                                                                              style: TextStyle(
                                                                                fontSize: isMobile
                                                                                    ? 14
                                                                                    : 16,
                                                                                color: kSubText,
                                                                              ),
                                                                              overflow: TextOverflow.ellipsis,
                                                                            ),
                                                                          ),
                                                                          IconButton(
                                                                            icon: Icon(
                                                                              Icons.copy,
                                                                              size: 18,
                                                                              color: kAccent,
                                                                            ),
                                                                            tooltip:
                                                                                'Copy',
                                                                            onPressed: () {
                                                                              Clipboard.setData(
                                                                                ClipboardData(
                                                                                  text: qrData['gcash_number'].toString(),
                                                                                ),
                                                                              );
                                                                              ScaffoldMessenger.of(
                                                                                context,
                                                                              ).showSnackBar(
                                                                                SnackBar(
                                                                                  content: Text(
                                                                                    'Gcash number copied!',
                                                                                  ),
                                                                                ),
                                                                              );
                                                                            },
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    const SizedBox(
                                                                      height:
                                                                          18,
                                                                    ),
                                                                    if (qrData['qr_image_url'] !=
                                                                        null)
                                                                      Builder(
                                                                        builder:
                                                                            (
                                                                              context,
                                                                            ) {
                                                                              final rawFileName = qrData['qr_image_url'];
                                                                              debugPrint(
                                                                                'DEBUG: qr_image_url = ${rawFileName?.toString() ?? 'null'}',
                                                                              );
                                                                              if (rawFileName ==
                                                                                      null ||
                                                                                  rawFileName.toString().isEmpty) {
                                                                                return Container(
                                                                                  height: isMobile
                                                                                      ? 180
                                                                                      : 240,
                                                                                  width: isMobile
                                                                                      ? 180
                                                                                      : 240,
                                                                                  alignment: Alignment.center,
                                                                                  child: const Text(
                                                                                    'No QR image found.',
                                                                                    style: TextStyle(
                                                                                      color: kWarn,
                                                                                    ),
                                                                                  ),
                                                                                );
                                                                              }
                                                                              // If it's a full URL, extract file name
                                                                              String
                                                                              fileName = rawFileName;
                                                                              if (fileName.contains(
                                                                                '/',
                                                                              )) {
                                                                                final uri = Uri.tryParse(
                                                                                  fileName,
                                                                                );
                                                                                if (uri !=
                                                                                        null &&
                                                                                    uri.pathSegments.isNotEmpty) {
                                                                                  final idx = uri.pathSegments.indexOf(
                                                                                    'gcash_qr_images',
                                                                                  );
                                                                                  if (idx !=
                                                                                          -1 &&
                                                                                      idx +
                                                                                              1 <
                                                                                          uri.pathSegments.length) {
                                                                                    fileName = uri.pathSegments
                                                                                        .sublist(
                                                                                          idx +
                                                                                              1,
                                                                                        )
                                                                                        .join(
                                                                                          '/',
                                                                                        );
                                                                                  } else {
                                                                                    fileName = uri.pathSegments.last;
                                                                                  }
                                                                                }
                                                                              }
                                                                              return Container(
                                                                                decoration: BoxDecoration(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    16,
                                                                                  ),
                                                                                  border: Border.all(
                                                                                    color: kAccent,
                                                                                    width: 2,
                                                                                  ),
                                                                                  boxShadow: [
                                                                                    BoxShadow(
                                                                                      color: Colors.black12,
                                                                                      blurRadius: 8,
                                                                                      offset: Offset(
                                                                                        0,
                                                                                        4,
                                                                                      ),
                                                                                    ),
                                                                                  ],
                                                                                ),
                                                                                child: ClipRRect(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    16,
                                                                                  ),
                                                                                  child: GestureDetector(
                                                                                    onTap: () {
                                                                                      showDialog(
                                                                                        context: context,
                                                                                        builder:
                                                                                            (
                                                                                              context,
                                                                                            ) => Dialog(
                                                                                              backgroundColor: Colors.transparent,
                                                                                              child: InteractiveViewer(
                                                                                                child: Container(
                                                                                                  padding: const EdgeInsets.all(
                                                                                                    8,
                                                                                                  ),
                                                                                                  color: Colors.white,
                                                                                                  child:
                                                                                                      FutureBuilder<
                                                                                                        String
                                                                                                      >(
                                                                                                        future: Supabase.instance.client.storage
                                                                                                            .from(
                                                                                                              'gcash_qr_images',
                                                                                                            )
                                                                                                            .createSignedUrl(
                                                                                                              fileName,
                                                                                                              3600,
                                                                                                            ),
                                                                                                        builder:
                                                                                                            (
                                                                                                              context,
                                                                                                              snapshot,
                                                                                                            ) {
                                                                                                              if (snapshot.connectionState ==
                                                                                                                  ConnectionState.waiting) {
                                                                                                                return const CircularProgressIndicator();
                                                                                                              }
                                                                                                              if (snapshot.hasError ||
                                                                                                                  !snapshot.hasData ||
                                                                                                                  (snapshot.data?.isEmpty ??
                                                                                                                      true)) {
                                                                                                                return const Text(
                                                                                                                  'Failed to load QR image',
                                                                                                                  style: TextStyle(
                                                                                                                    color: kWarn,
                                                                                                                  ),
                                                                                                                );
                                                                                                              }
                                                                                                              return Image.network(
                                                                                                                snapshot.data!,
                                                                                                                width: isMobile
                                                                                                                    ? MediaQuery.of(
                                                                                                                            context,
                                                                                                                          ).size.width *
                                                                                                                          0.85
                                                                                                                    : 400,
                                                                                                                height: isMobile
                                                                                                                    ? MediaQuery.of(
                                                                                                                            context,
                                                                                                                          ).size.height *
                                                                                                                          0.65
                                                                                                                    : 400,
                                                                                                                fit: BoxFit.contain,
                                                                                                              );
                                                                                                            },
                                                                                                      ),
                                                                                                ),
                                                                                              ),
                                                                                            ),
                                                                                      );
                                                                                    },
                                                                                    child:
                                                                                        FutureBuilder<
                                                                                          String
                                                                                        >(
                                                                                          future: Supabase.instance.client.storage
                                                                                              .from(
                                                                                                'gcash_qr_images',
                                                                                              )
                                                                                              .createSignedUrl(
                                                                                                fileName,
                                                                                                3600,
                                                                                              ),
                                                                                          builder:
                                                                                              (
                                                                                                context,
                                                                                                snapshot,
                                                                                              ) {
                                                                                                if (snapshot.connectionState ==
                                                                                                    ConnectionState.waiting) {
                                                                                                  return const CircularProgressIndicator();
                                                                                                }
                                                                                                if (snapshot.hasError ||
                                                                                                    !snapshot.hasData ||
                                                                                                    (snapshot.data?.isEmpty ??
                                                                                                        true)) {
                                                                                                  return Container(
                                                                                                    height: isMobile
                                                                                                        ? 180
                                                                                                        : 240,
                                                                                                    width: isMobile
                                                                                                        ? 180
                                                                                                        : 240,
                                                                                                    alignment: Alignment.center,
                                                                                                    child: const Text(
                                                                                                      'Failed to load QR image',
                                                                                                      style: TextStyle(
                                                                                                        color: kWarn,
                                                                                                      ),
                                                                                                    ),
                                                                                                  );
                                                                                                }
                                                                                                return Image.network(
                                                                                                  snapshot.data!,
                                                                                                  height: isMobile
                                                                                                      ? 180
                                                                                                      : 240,
                                                                                                  width: isMobile
                                                                                                      ? 180
                                                                                                      : 240,
                                                                                                  fit: BoxFit.contain,
                                                                                                );
                                                                                              },
                                                                                        ),
                                                                                  ),
                                                                                ),
                                                                              );
                                                                            },
                                                                      ),
                                                                    const SizedBox(
                                                                      height:
                                                                          24,
                                                                    ),
                                                                    Text(
                                                                      'Please pay using the QR code above.',
                                                                      style: TextStyle(
                                                                        fontSize:
                                                                            isMobile
                                                                            ? 15
                                                                            : 17,
                                                                        color:
                                                                            kSubText,
                                                                      ),
                                                                      textAlign:
                                                                          TextAlign
                                                                              .center,
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                              actionsAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              actions: [
                                                                TextButton.icon(
                                                                  icon: Icon(
                                                                    Icons
                                                                        .cancel,
                                                                    color:
                                                                        kWarn,
                                                                  ),
                                                                  label: Text(
                                                                    'Cancel',
                                                                    style: TextStyle(
                                                                      color:
                                                                          kWarn,
                                                                    ),
                                                                  ),
                                                                  onPressed: () =>
                                                                      Navigator.of(
                                                                        context,
                                                                      ).pop(
                                                                        false,
                                                                      ),
                                                                ),
                                                                ElevatedButton.icon(
                                                                  icon: Icon(
                                                                    Icons
                                                                        .upload_file,
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                                  label: Text(
                                                                    'Upload Receipt',
                                                                  ),
                                                                  style: ElevatedButton.styleFrom(
                                                                    backgroundColor:
                                                                        kAccent,
                                                                    shape: RoundedRectangleBorder(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            12,
                                                                          ),
                                                                    ),
                                                                  ),
                                                                  onPressed: () =>
                                                                      Navigator.of(
                                                                        context,
                                                                      ).pop(
                                                                        true,
                                                                      ),
                                                                ),
                                                              ],
                                                            );
                                                          },
                                                        ),
                                                      );
                                                      // ...existing code...
                                                      // 3. If user chooses to upload, proceed with uploadImage
                                                      if (proceed == true) {
                                                        final userDeceasedValue =
                                                            data['userdeceased']
                                                                ?.toString() ??
                                                            '';
                                                        final hasDeceasedValue =
                                                            userDeceasedValue
                                                                .isNotEmpty;
                                                        final isMembershipPayment =
                                                            !hasDeceasedValue &&
                                                            (data['deceased_name'] ==
                                                                    null ||
                                                                data['deceased_name']
                                                                    .toString()
                                                                    .isEmpty);
                                                        if (!hasDeceasedValue &&
                                                            !isMembershipPayment) {
                                                          if (!context.mounted) {
                                                            return;
                                                          }
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).showSnackBar(
                                                            const SnackBar(
                                                              content: Text(
                                                                'This payment record has no deceased user assigned.',
                                                              ),
                                                            ),
                                                          );
                                                          return;
                                                        }
                                                        await uploadImage(
                                                          data['id'].toString(),
                                                          isMembershipPayment
                                                              ? null
                                                              : userDeceasedValue,
                                                          int.parse(
                                                            data['amount']
                                                                .toString(),
                                                          ),
                                                          isMembershipPayment
                                                              ? 'for_membership'
                                                              : 'default',
                                                        );
                                                        if (!context.mounted) {
                                                          return;
                                                        }
                                                        setState(() {});
                                                      }
                                                    },
                                            ),
                                          ],
                                        ),
                                        if (hasUpload) ...[
                                          const SizedBox(height: 8),
                                          FutureBuilder<String>(
                                            future: () async {
                                              // Generate signed URL for private image, compatible with file name or full URL
                                              String? fileName =
                                                  uploadData['image_url'];
                                              if (fileName != null &&
                                                  fileName.isNotEmpty &&
                                                  fileName.contains('/')) {
                                                // If fileName is a full URL, extract the path after the bucket name
                                                final uri = Uri.parse(fileName);
                                                final segments =
                                                    uri.pathSegments;
                                                final bucketIndex = segments
                                                    .indexOf('gcash_qr_images');
                                                if (bucketIndex != -1 &&
                                                    bucketIndex + 1 <
                                                        segments.length) {
                                                  fileName = segments
                                                      .sublist(bucketIndex + 1)
                                                      .join('/');
                                                }
                                              }
                                              // Ensure fileName is not null
                                              final safeFileName =
                                                  fileName ?? '';
                                              final signedUrl = await Supabase
                                                  .instance
                                                  .client
                                                  .storage
                                                  .from('gcash_qr_images')
                                                  .createSignedUrl(
                                                    safeFileName,
                                                    3600,
                                                  );
                                              return signedUrl;
                                            }(),
                                            builder: (context, snapshot) {
                                              if (snapshot.hasError) {
                                                return Text(
                                                  'Error loading receipt: ${snapshot.error}',
                                                  style: const TextStyle(
                                                    color: kWarn,
                                                  ),
                                                );
                                              }
                                              if (!snapshot.hasData ||
                                                  snapshot.connectionState ==
                                                      ConnectionState.waiting) {
                                                return const CircularProgressIndicator(
                                                  color: kAccent,
                                                );
                                              }
                                              final signedUrl = snapshot.data!;
                                              return GestureDetector(
                                                onTap: () {
                                                  showDialog(
                                                    context: context,
                                                    builder: (context) => Dialog(
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              16,
                                                            ),
                                                      ),
                                                      child: ClipRRect(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              16,
                                                            ),
                                                        child: InteractiveViewer(
                                                          child: Image.network(
                                                            signedUrl,
                                                            fit: BoxFit.contain,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: Row(
                                                  children: const [
                                                    Icon(
                                                      Icons.receipt_long,
                                                      size: 18,
                                                      color: kAccent,
                                                    ),
                                                    SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        'Receipt uploaded',
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          color: kSubText,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
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
