import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:capstone_app/utils/input_safety.dart';

// Color palette
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF6B7280);
const kAccent = Color(0xFF3B82F6);
const kPrimary = Color(0xFF1E40AF);
const kWarn = Color(0xFFF59E0B);
const Color _kHeaderGradientStart = Color(0xFF1E40AF);
const Color _kHeaderGradientEnd = Color(0xFF3B82F6);

class GcashQrPage extends StatefulWidget {
  final dynamic dayungUnitId; // Accept dayungUnitId

  const GcashQrPage({super.key, required this.dayungUnitId});

  @override
  State<GcashQrPage> createState() => _GcashQrPageState();
}

class _GcashQrPageState extends State<GcashQrPage> {
  static const int _initialQrFetchLimit = 20;
  static const Duration _queryTimeout = Duration(seconds: 8);

  Uint8List? _qrImageBytes;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _gcashNumberController =
      TextEditingController(); // <-- Add this
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _qrRows = const [];
  bool _qrRowsLoading = false;
  String? _qrRowsError;

  // State variables for displaying saved QR image and name
  String? _savedQrImageUrl;
  String? _savedQrName;
  bool _hasQrForUnit = false; // <-- Add this
  bool _showUpdateSuccess = false; // <-- Add this
  bool _showNoChanges = false; // <-- Add this
  bool _isLoading = false; // <-- Add this

  String _paymentKey({
    dynamic userId,
    dynamic deathNoticeId,
    dynamic deceasedId,
  }) {
    final normalizedUserId = (userId ?? '').toString();
    final normalizedNoticeId = (deathNoticeId ?? '').toString();
    final normalizedDeceasedId = (deceasedId ?? '').toString();
    return '$normalizedUserId|$normalizedNoticeId|$normalizedDeceasedId';
  }

  String _formatUploadedAt(dynamic value) {
    final rawValue = value?.toString() ?? '';
    if (rawValue.isEmpty) return '';

    final parsed = DateTime.tryParse(rawValue);
    if (parsed == null) return rawValue;

    final philippinesTime = parsed.toUtc().add(const Duration(hours: 8));
    return DateFormat('MMM d, yyyy - h:mm a').format(philippinesTime);
  }

  bool _isUuid(String? value) {
    if (value == null || value.isEmpty) return false;
    final uuidRegExp = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegExp.hasMatch(value);
  }

  String _getDeceasedDisplayText(Map<String, dynamic> row) {
    final deceasedName = row['userdeceased_name']?.toString().trim();
    if (deceasedName != null && deceasedName.isNotEmpty) {
      return deceasedName;
    }

    final type = row['type']?.toString().trim().toLowerCase();
    if (type == 'for_membership') {
      return 'For Membership';
    }

    return 'Unknown';
  }

  void _refreshQrData() {
    _loadQrRows();
  }

  Future<void> _pickQrImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _qrImageBytes = bytes;
      });
    }
  }

  String _maskName(String? name) {
    if (name == null || name.isEmpty) return '';
    final words = name.split(' ');
    return words
        .map((word) {
          if (word.length <= 2) return word;
          final visible = word.substring(0, 2);
          final masked = '*' * (word.length - 2);
          return visible + masked;
        })
        .join(' ');
  }

  Future<void> _loadLatestSavedQr() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await Supabase.instance.client
          .from('gcash_qr_uploads')
          .select('qr_image_url, name, gcash_number')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .order('created_at', ascending: false)
          .limit(1)
          .timeout(_queryTimeout);

      if (!mounted) return;
      if (response.isNotEmpty) {
        String? signedUrl;
        String? fileName = response[0]['qr_image_url'];

        if (fileName!.isNotEmpty) {
          // If fileName is a full URL, extract the path after the bucket name
          final uri = Uri.parse(fileName);
          final segments = uri.pathSegments;
          // Find the index of the bucket name
          final bucketIndex = segments.indexOf('gcash_qr_images');
          if (bucketIndex != -1 && bucketIndex + 1 < segments.length) {
            // Join the rest as the file path
            fileName = segments.sublist(bucketIndex + 1).join('/');
          }

          signedUrl = await Supabase.instance.client.storage
              .from('gcash_qr_images')
              .createSignedUrl(fileName, 60 * 60); // 1 hour expiry
        }
        setState(() {
          _savedQrImageUrl = signedUrl;
          _savedQrName = _maskName(response[0]['name']);
          _hasQrForUnit = true;
          _nameController.text = response[0]['name'] ?? '';
          _gcashNumberController.text = response[0]['gcash_number'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading QR: $e');
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Error loading QR: $e')));
      setState(() {
        _hasQrForUnit = false;
        _nameController.clear();
        _gcashNumberController.clear();
      });
    }
  }

  Future<void> _initializePageData() async {
    await Future.wait([_loadLatestSavedQr(), _loadQrRows()]);
  }

  void _saveQrCode() async {
    final messenger = ScaffoldMessenger.of(context);
    final rawName = AppInputSecurity.sanitizePlainText(
      _nameController.text,
      maxLength: 120,
    );
    final name = _maskName(rawName);
    final gcashNumber = AppInputSecurity.sanitizePhone(
      _gcashNumberController.text,
    );
    if ((rawName.isEmpty && _qrImageBytes == null) || gcashNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a name, GCash number, or select a QR image.',
          ),
        ),
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
        final fileName =
            'gcash_qr_${DateTime.now().millisecondsSinceEpoch}.png';
        await Supabase.instance.client.storage
            .from('gcash_qr_images')
            .uploadBinary(
              fileName,
              fileBytes,
              fileOptions: const FileOptions(contentType: 'image/png'),
            );

        imageUrl = await Supabase.instance.client.storage
            .from('gcash_qr_images')
            .createSignedUrl(fileName, 60 * 60); // 1 hour expiry
      }

      final currentUser = Supabase.instance.client.auth.currentUser;

      // Check if QR already exists for this unit
      final existing = await Supabase.instance.client
          .from('gcash_qr_uploads')
          .select(
            'id, name, qr_image_url, gcash_number',
          ) // <-- Add gcash_number
          .eq('dayung_unit_id', widget.dayungUnitId)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        // Prepare update data
        final updateData = <String, dynamic>{
          'updated_at': DateTime.now().toIso8601String(),
          'uploaded_by': currentUser?.id,
        };
        if (rawName.isNotEmpty && name != existing['name']) {
          updateData['name'] = name;
        }
        if (gcashNumber.isNotEmpty && gcashNumber != existing['gcash_number']) {
          // <-- Add this
          updateData['gcash_number'] = gcashNumber;
        }
        if (imageUrl != null) {
          updateData['qr_image_url'] = imageUrl;
        }
        if (updateData.length > 2) {
          // Only update if something changed
          await Supabase.instance.client
              .from('gcash_qr_uploads')
              .update(updateData)
              .eq('id', existing['id']);

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
        if (rawName.isEmpty || gcashNumber.isEmpty || imageUrl == null) {
          if (!mounted) return;
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Please enter a name, GCash number, and select a QR image.',
              ),
            ),
          );
          return;
        }
        await Supabase.instance.client.from('gcash_qr_uploads').insert({
          'name': name,
          'gcash_number': gcashNumber,
          'qr_image_url': imageUrl,
          'created_at': DateTime.now().toIso8601String(),
          'uploaded_by': currentUser?.id,
          'dayung_unit_id': widget.dayungUnitId,
        });
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('GCash QR saved!')),
        );
      }

      // Clear form and reload latest QR from database
      if (!mounted) return;
      setState(() {
        _nameController.clear();
        _gcashNumberController.clear(); // <-- Clear controller
        _qrImageBytes = null;
      });
      await _loadLatestSavedQr();
      _refreshQrData();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Error saving: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false; // <-- Stop loading
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchQrCodes() async {
    final sb = Supabase.instance.client;
    // Fetch QR codes and join with claims table to get claim id
    final response = await sb
        .from('gcash_qr_codes')
        .select(
          'id, set_amount_id, image_url, uploaded_by, created_at, userdeceased, dayung_unit_id, amount, refno, type',
        )
        .eq('dayung_unit_id', widget.dayungUnitId)
        .order('created_at', ascending: false)
        .limit(_initialQrFetchLimit)
        .timeout(_queryTimeout);

    final List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(
      response,
    );

    // --- Ensure all image URLs are valid signed URLs ---
    for (final row in data) {
      final imageUrl = row['image_url']?.toString() ?? '';
      if (imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
        // If imageUrl is not a full URL, generate a signed URL
        try {
          // Remove any leading slashes
          final cleanFileName = imageUrl.startsWith('/')
              ? imageUrl.substring(1)
              : imageUrl;
          final signedUrl = await sb.storage
              .from('gcash_qr_images')
              .createSignedUrl(cleanFileName, 60 * 60); // 1 hour expiry
          row['image_url'] = signedUrl;
        } catch (e) {
          // If failed, leave as is (will show broken image)
        }
      }
    }

    if (data.isEmpty) return data;

    final userIds = <String>{};
    for (final row in data) {
      final uploadedBy = row['uploaded_by']?.toString();
      final userDeceased = row['userdeceased']?.toString();
      if (uploadedBy != null && uploadedBy.isNotEmpty && _isUuid(uploadedBy)) {
        userIds.add(uploadedBy);
      }
      if (userDeceased != null &&
          userDeceased.isNotEmpty &&
          _isUuid(userDeceased)) {
        userIds.add(userDeceased);
      }
    }

    final userNameMap = <String, String>{};
    if (userIds.isNotEmpty) {
      final users = await sb
          .from('users')
          .select('id, full_name')
          .inFilter('id', userIds.toList())
          .timeout(_queryTimeout);
      for (final user in List<Map<String, dynamic>>.from(users)) {
        final userId = (user['id'] ?? '').toString();
        if (userId.isEmpty) continue;
        userNameMap[userId] = (user['full_name'] ?? '').toString();
      }
    }

    final paidKeys = <String>{};
    final paymentIdMap = <String, String>{};

    final setAmountIds = data
        .map((row) => row['set_amount_id'])
        .where((value) => value != null)
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty && _isUuid(value))
        .toSet()
        .toList();

    if (setAmountIds.isNotEmpty) {
      final paymentsBySetAmount = await sb
          .from('payments')
          .select('id, status')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .inFilter('id', setAmountIds)
          .timeout(_queryTimeout);

      for (final payment in List<Map<String, dynamic>>.from(
        paymentsBySetAmount,
      )) {
        final paymentId = payment['id']?.toString();
        if (paymentId == null || paymentId.isEmpty) continue;
        if (payment['status']?.toString().toLowerCase() == 'paid') {
          paidKeys.add(paymentId);
        }
        paymentIdMap[paymentId] = paymentId;
      }
    }

    final qrIds = data
        .map((row) => row['qr_id'])
        .where((value) => value != null)
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty && _isUuid(value))
        .toSet()
        .toList();

    if (qrIds.isNotEmpty) {
      final paymentsByQr = await sb
          .from('payments')
          .select('id, user_id, qr_id, userdeceased, status')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .inFilter('qr_id', qrIds)
          .timeout(_queryTimeout);

      for (final payment in List<Map<String, dynamic>>.from(paymentsByQr)) {
        final key = _paymentKey(
          userId: payment['user_id'],
          deathNoticeId: payment['qr_id'],
          deceasedId: payment['userdeceased'],
        );
        if (payment['status']?.toString().toLowerCase() == 'paid') {
          paidKeys.add(key);
        }
        if (payment['id'] != null) {
          paymentIdMap[key] = payment['id'].toString();
        }
      }
    }

    final deceasedIds = data
        .map((row) => row['userdeceased'])
        .where((value) => value != null)
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    if (deceasedIds.isNotEmpty) {
      final paymentsByDeceased = await sb
          .from('payments')
          .select('id, user_id, qr_id, userdeceased')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'paid')
          .isFilter('qr_id', null)
          .inFilter('userdeceased', deceasedIds)
          .timeout(_queryTimeout);

      for (final payment in List<Map<String, dynamic>>.from(
        paymentsByDeceased,
      )) {
        final key = _paymentKey(
          userId: payment['user_id'],
          deathNoticeId: payment['qr_id'],
          deceasedId: payment['userdeceased'],
        );
        paidKeys.add(key);
        if (payment['id'] != null) {
          paymentIdMap[key] = payment['id'].toString();
        }
      }
    }

    // ...existing code...
    for (final row in data) {
      final uploadedBy = row['uploaded_by']?.toString() ?? '';
      final deceasedId = row['userdeceased']?.toString() ?? '';
      final setAmountId = row['set_amount_id']?.toString();
      final qrId = row['qr_id']?.toString();

      String? paymentKey;
      if (setAmountId != null &&
          setAmountId.isNotEmpty &&
          _isUuid(setAmountId)) {
        paymentKey = setAmountId;
      } else {
        paymentKey = _paymentKey(
          userId: row['uploaded_by'],
          deathNoticeId: qrId,
          deceasedId: row['userdeceased'],
        );
      }

      row['uploaded_by_name'] = userNameMap[uploadedBy] ?? '';
      row['userdeceased_name'] = userNameMap[deceasedId] ?? '';
      row['payment_id'] = paymentIdMap[paymentKey];
      row['already_paid'] = paymentKey != null && paidKeys.contains(paymentKey);
    }
    return data;
  }

  Future<void> _loadQrRows() async {
    if (!mounted) return;
    setState(() {
      _qrRowsLoading = true;
      _qrRowsError = null;
    });

    try {
      final rows = await _fetchQrCodes();
      if (!mounted) return;
      setState(() {
        _qrRows = rows;
        _qrRowsLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _qrRowsLoading = false;
        _qrRowsError = error.toString();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initializePageData();
    });
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
    final double previewSize = isMobile ? 72 : 96;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_kHeaderGradientStart, _kHeaderGradientEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x22083366),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'GCash QR Management',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Upload, update, and manage your unit’s QR payment code with clarity and speed.',
                              style: TextStyle(
                                fontSize: isMobile ? 14 : 15,
                                color: Colors.white.withOpacity(0.88),
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'QR Status',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _hasQrForUnit ? 'Active' : 'Not set',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Uploads',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_qrRows.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x12000000),
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 20,
                        ),
                        child: isMobile
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Add New GCash QR',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                      color: kText,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Upload the official QR and assign the correct GCash owner details.',
                                    style: TextStyle(
                                      color: kSubText,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'OpenSans',
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _nameController,
                                    inputFormatters:
                                        AppInputSecurity.singleLineFormatters(
                                          maxLength: 120,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'GCash Name',
                                      filled: true,
                                      fillColor: Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(16),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _gcashNumberController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters:
                                        AppInputSecurity.phoneFormatters(
                                          maxLength: 11,
                                        ),
                                    maxLength: 11,
                                    decoration: const InputDecoration(
                                      labelText: 'GCash Number',
                                      filled: true,
                                      fillColor: Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(16),
                                        ),
                                      ),
                                      counterText: '',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (_qrImageBytes != null)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.memory(
                                        _qrImageBytes!,
                                        width: previewSize,
                                        height: previewSize,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.upload),
                                    label: const Text('Upload QR'),
                                    onPressed: _pickQrImage,
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      icon: _isLoading
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Icon(
                                              _hasQrForUnit
                                                  ? Icons.update
                                                  : Icons.save,
                                            ),
                                      label: Text(
                                        _hasQrForUnit ? 'Update QR' : 'Save QR',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: kPrimary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                      onPressed: _isLoading
                                          ? null
                                          : _saveQrCode,
                                    ),
                                  ),
                                  if (_showUpdateSuccess)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Row(
                                        children: const [
                                          Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'GCash QR updated',
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (_showNoChanges)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Row(
                                        children: const [
                                          Icon(
                                            Icons.warning,
                                            color: Colors.orange,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'No changes to update.',
                                            style: TextStyle(
                                              color: Colors.orange,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (_savedQrImageUrl != null &&
                                      _savedQrName != null) ...[
                                    const SizedBox(height: 20),
                                    Center(
                                      child: Column(
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
                                            onTap: () => _showImagePreview(
                                              _savedQrImageUrl!,
                                            ),
                                            child: _buildThumbImage(
                                              _savedQrImageUrl!,
                                              width: 120,
                                              height: 120,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Add New GCash QR',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                            color: kText,
                                            fontFamily: 'Montserrat',
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        const Text(
                                          'Keep your unit payment QR updated and searchable for collectors.',
                                          style: TextStyle(
                                            color: kSubText,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'OpenSans',
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                children: [
                                                  TextField(
                                                    controller: _nameController,
                                                    inputFormatters:
                                                        AppInputSecurity.singleLineFormatters(
                                                          maxLength: 120,
                                                        ),
                                                    decoration: const InputDecoration(
                                                      labelText: 'GCash Name',
                                                      filled: true,
                                                      fillColor: Color(
                                                        0xFFF8FAFC,
                                                      ),
                                                      border: OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.all(
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  TextField(
                                                    controller:
                                                        _gcashNumberController,
                                                    keyboardType:
                                                        TextInputType.number,
                                                    inputFormatters:
                                                        AppInputSecurity.phoneFormatters(
                                                          maxLength: 11,
                                                        ),
                                                    maxLength: 11,
                                                    decoration: const InputDecoration(
                                                      labelText: 'GCash Number',
                                                      filled: true,
                                                      fillColor: Color(
                                                        0xFFF8FAFC,
                                                      ),
                                                      border: OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.all(
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                            ),
                                                      ),
                                                      counterText: '',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 18),
                                            Column(
                                              children: [
                                                if (_qrImageBytes != null)
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                    child: Image.memory(
                                                      _qrImageBytes!,
                                                      width: previewSize,
                                                      height: previewSize,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  )
                                                else
                                                  Container(
                                                    width: previewSize,
                                                    height: previewSize,
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFFF8FAFC,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                      border: Border.all(
                                                        color: const Color(
                                                          0xFFE5E7EB,
                                                        ),
                                                      ),
                                                    ),
                                                    alignment: Alignment.center,
                                                    child: const Icon(
                                                      Icons.qr_code_rounded,
                                                      color: kSubText,
                                                      size: 28,
                                                    ),
                                                  ),
                                                const SizedBox(height: 12),
                                                TextButton.icon(
                                                  icon: const Icon(
                                                    Icons.upload,
                                                  ),
                                                  label: const Text(
                                                    'Upload QR',
                                                  ),
                                                  onPressed: _pickQrImage,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            icon: _isLoading
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          color: Colors.white,
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : Icon(
                                                    _hasQrForUnit
                                                        ? Icons.update
                                                        : Icons.save,
                                                  ),
                                            label: Text(
                                              _hasQrForUnit
                                                  ? 'Update QR'
                                                  : 'Save QR',
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: kPrimary,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 16,
                                                  ),
                                            ),
                                            onPressed: _isLoading
                                                ? null
                                                : _saveQrCode,
                                          ),
                                        ),
                                        if (_showUpdateSuccess)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 10,
                                            ),
                                            child: Row(
                                              children: const [
                                                Icon(
                                                  Icons.check_circle,
                                                  color: Colors.green,
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'GCash QR updated',
                                                  style: TextStyle(
                                                    color: Colors.green,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (_showNoChanges)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 10,
                                            ),
                                            child: Row(
                                              children: const [
                                                Icon(
                                                  Icons.warning,
                                                  color: Colors.orange,
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'No changes to update.',
                                                  style: TextStyle(
                                                    color: Colors.orange,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (_savedQrImageUrl != null &&
                                      _savedQrName != null) ...[
                                    const SizedBox(width: 24),
                                    Column(
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
                                          onTap: () => _showImagePreview(
                                            _savedQrImageUrl!,
                                          ),
                                          child: _buildThumbImage(
                                            _savedQrImageUrl!,
                                            width: 96,
                                            height: 96,
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
                    const Text(
                      'Payments collected via GCash',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: kText,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Search uploaded proofs, review payer details, and confirm paid records.',
                      style: TextStyle(
                        color: kSubText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Showing the latest $_initialQrFetchLimit uploads first to keep this page fast.',
                      style: const TextStyle(
                        color: kSubText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _searchController,
                      inputFormatters: AppInputSecurity.singleLineFormatters(
                        maxLength: 80,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Search by name or reference number',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(18)),
                        ),
                        enabledBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(18)),
                          borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(18)),
                          borderSide: BorderSide(color: kPrimary, width: 1.5),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = AppInputSecurity.sanitizeSearchQuery(
                            value,
                          ).toLowerCase();
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    if (_qrRowsLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: CircularProgressIndicator(color: kAccent),
                        ),
                      )
                    else if (_qrRowsError != null)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFFED7AA)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Unable to load QR uploads right now.',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: kText,
                                fontFamily: 'Montserrat',
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _qrRowsError!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: kSubText,
                                fontFamily: 'OpenSans',
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _refreshQrData,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Builder(
                        builder: (context) {
                          final filteredData = _searchQuery.isEmpty
                              ? _qrRows
                              : _qrRows.where((row) {
                                  final uploadedByName =
                                      row['uploaded_by_name']
                                          ?.toString()
                                          .toLowerCase() ??
                                      '';
                                  final deceasedName =
                                      row['userdeceased_name']
                                          ?.toString()
                                          .toLowerCase() ??
                                      '';
                                  final refNo =
                                      row['refno']?.toString().toLowerCase() ??
                                      '';
                                  return uploadedByName.contains(
                                        _searchQuery,
                                      ) ||
                                      deceasedName.contains(_searchQuery) ||
                                      refNo.contains(_searchQuery);
                                }).toList();

                          if (filteredData.isEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.qr_code_2_rounded,
                                    size: 42,
                                    color: kSubText,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'No QR codes found',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: kText,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Try a different search term or wait for new uploads.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: kSubText,
                                      fontFamily: 'OpenSans',
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filteredData.length,
                            itemBuilder: (context, i) {
                              final row = filteredData[i];
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: const Color(0xFFE5E7EB),
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x10000000),
                                      blurRadius: 12,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                    horizontal: 16,
                                  ),
                                  child: isMobile
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (row['image_url'] != null)
                                              GestureDetector(
                                                onTap: () {
                                                  _showImagePreview(
                                                    row['image_url'].toString(),
                                                  );
                                                },
                                                child: _buildThumbImage(
                                                  row['image_url'].toString(),
                                                  width: double.infinity,
                                                  height: 180,
                                                ),
                                              )
                                            else
                                              const SizedBox(),
                                            const SizedBox(height: 12),
                                            Text(
                                              row['uploaded_by_name']
                                                          ?.toString()
                                                          .trim()
                                                          .isNotEmpty ==
                                                      true
                                                  ? row['uploaded_by_name']
                                                        .toString()
                                                  : 'Unknown uploader',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: kText,
                                                fontFamily: 'Montserrat',
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Date Uploaded: ${_formatUploadedAt(row['created_at'])}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: kSubText,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Deceased: ${_getDeceasedDisplayText(row)}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: kSubText,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Ref No: ${row['refno']?.toString().trim().isNotEmpty == true ? row['refno'].toString() : 'N/A'}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: kSubText,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            if (row['already_paid'] == true)
                                              const Chip(
                                                label: Text(
                                                  'Paid',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                backgroundColor: Colors.green,
                                              )
                                            else
                                              _buildMarkPaidButton(row),
                                          ],
                                        )
                                      : Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (row['image_url'] != null)
                                              GestureDetector(
                                                onTap: () {
                                                  _showImagePreview(
                                                    row['image_url'].toString(),
                                                  );
                                                },
                                                child: _buildThumbImage(
                                                  row['image_url'].toString(),
                                                  width: 60,
                                                  height: 60,
                                                ),
                                              )
                                            else
                                              const SizedBox(),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    row['uploaded_by_name']
                                                                ?.toString()
                                                                .trim()
                                                                .isNotEmpty ==
                                                            true
                                                        ? row['uploaded_by_name']
                                                              .toString()
                                                        : 'Unknown uploader',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: kText,
                                                      fontFamily: 'Montserrat',
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Date Uploaded: ${_formatUploadedAt(row['created_at'])}',
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      color: kSubText,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Deceased: ${_getDeceasedDisplayText(row)}',
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      color: kSubText,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Ref No: ${row['refno']?.toString().trim().isNotEmpty == true ? row['refno'].toString() : 'N/A'}',
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      color: kSubText,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (row['already_paid'] == true)
                                              const Chip(
                                                label: Text(
                                                  'Paid',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                backgroundColor: Colors.green,
                                              )
                                            else
                                              _buildMarkPaidButton(row),
                                          ],
                                        ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbImage(
    String imageUrl, {
    required double width,
    required double height,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        cacheWidth: width.isFinite ? (width * 2).round() : null,
        errorBuilder: (context, error, stackTrace) => Container(
          width: width,
          height: height,
          color: const Color(0xFFF3F4F6),
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image, color: kSubText),
        ),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: width,
            height: height,
            color: const Color(0xFFF8FAFC),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      ),
    );
  }

  void _showImagePreview(String imageUrl) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.low,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.broken_image, size: 100),
          ),
        ),
      ),
    );
  }

  Widget _buildMarkPaidButton(Map<String, dynamic> row) {
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
            final requiredAmount = row['amount']?.toString() ?? '0';
            bool isLoading = false;

            return StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  title: const Text('Confirm Payment'),
                  content: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text(
                                  'Amount to pay:',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '₱$requiredAmount',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
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
                            onPressed: () async {
                              setState(() => isLoading = true);
                              final navigator = Navigator.of(context);
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                final paymentId = row['payment_id'];
                                final currentUserId = Supabase
                                    .instance
                                    .client
                                    .auth
                                    .currentUser
                                    ?.id;
                                final updateData = {
                                  'status': 'paid',
                                  'paid_at': DateTime.now()
                                      .toUtc()
                                      .toIso8601String(),
                                  'collected_by': currentUserId,
                                  'iscollectedbytreasurer': true,
                                  'iscollectedbytreasurer_date': DateTime.now()
                                      .toUtc()
                                      .toIso8601String(),
                                };

                                if (paymentId == null) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Unable to mark payment as paid: missing payment identifier.',
                                      ),
                                    ),
                                  );
                                  setState(() => isLoading = false);
                                  return;
                                }

                                // Debug prints
                                print('Current auth user id: $currentUserId');
                                print(
                                  'Current session: ${Supabase.instance.client.auth.currentSession}',
                                );
                                print('payment id: $paymentId');
                                print('row: $row');

                                if (paymentId == null ||
                                    paymentId.toString().isEmpty) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Unable to mark payment as paid: no linked payment record found.',
                                      ),
                                    ),
                                  );
                                  setState(() => isLoading = false);
                                  return;
                                }

                                final selectResult = await Supabase
                                    .instance
                                    .client
                                    .from('payments')
                                    .select()
                                    .eq('id', paymentId);
                                print('Select result: $selectResult');

                                final result = await Supabase.instance.client
                                    .from('payments')
                                    .update(updateData)
                                    .eq('id', paymentId);
                                print('Update result: $result');
                                if (mounted) {
                                  this.setState(() {
                                    row['already_paid'] = true;
                                  });
                                  _refreshQrData();
                                }
                                navigator.pop();
                              } catch (e) {
                                navigator.pop();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Error updating payment: $e'),
                                  ),
                                );
                              }
                            },
                            child: const Text('Save Payment'),
                          ),
                        ],
                );
              },
            );
          },
        );
      },
      child: const Text('Mark as Paid'),
    );
  }
}
