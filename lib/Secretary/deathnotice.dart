import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);

class CreateDeathNoticePage extends StatefulWidget {
  final int? dayungUnitId;
  const CreateDeathNoticePage({super.key, this.dayungUnitId});

  @override
  State<CreateDeathNoticePage> createState() => _CreateDeathNoticePageState();
}

class _CreateDeathNoticePageState extends State<CreateDeathNoticePage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String _search = '';
  String? _barangay;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _fetchMembers();
  }

  Future<void> _fetchMembers() async {
    setState(() => _loading = true);
    final rows = await supabase
        .from('users')
        .select('id, full_name, is_deceased')
        .eq('is_deceased', false)
        .eq('dayung_unit_id', widget.dayungUnitId as Object);
    final list = List<Map<String, dynamic>>.from(rows);
    setState(() {
      _members = list;
      _filtered = list;
      _loading = false;
    });
  }

  void _filter(String q) {
    setState(() {
      _search = q;
      _filtered = _members.where((m) {
        final name = (m['full_name'] ?? '').toString().toLowerCase();
        return name.contains(q.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: kPrimaryDark),
        title: const Text(
          '+ Death Notice',
          style: TextStyle(
            color: kPrimaryDark,
            fontWeight: FontWeight.w800,
            fontSize: 22,
            fontFamily: 'Montserrat',
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Find member',
                      prefixIcon: const Icon(Icons.search, color: kPrimaryDark),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: kPrimary.withOpacity(.2)),
                      ),
                    ),
                    style: const TextStyle(fontSize: 18, color: kNeutralText),
                    onChanged: _filter,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final m = _filtered[i];
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(
                          m['full_name'] ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                            color: kNeutralText,
                          ),
                        ),
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: kBg,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(24),
                              ),
                            ),
                            builder: (ctx) => MarkDeceasedModal(
                              memberId: m['id'].toString(),
                              memberName: m['full_name'],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class MarkDeceasedModal extends StatefulWidget {
  final String memberId;
  final String memberName;
  const MarkDeceasedModal({
    super.key,
    required this.memberId,
    required this.memberName,
  });

  @override
  State<MarkDeceasedModal> createState() => _MarkDeceasedModalState();
}

class _MarkDeceasedModalState extends State<MarkDeceasedModal> {
  DateTime? _dateOfDeath;
  bool _submitting = false;
  List<Map<String, dynamic>> _beneficiaries = [];
  String? _selectedBeneficiaryId;
  File? _deathCertFile;
  String? _deathCertUrl;
  String? _barangay;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _fetchBeneficiaries();
  }

  Future<void> _fetchBeneficiaries() async {
    final rows = await Supabase.instance.client
        .from('beneficiaries')
        .select('id, full_name, status')
        .eq('user_id', widget.memberId);
    setState(() {
      _beneficiaries = List<Map<String, dynamic>>.from(rows);
    });
  }

  Future<void> _pickDeathCert() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _deathCertFile = File(result.files.single.path!);
      });
    }
  }

  Future<String?> _uploadDeathCert() async {
    if (_deathCertFile == null) return null;
    final storage = Supabase.instance.client.storage;
    final fileName =
        'death_cert_${widget.memberId}_${DateTime.now().millisecondsSinceEpoch}.${_deathCertFile!.path.split('.').last}';
    final bucket = 'death_certificates'; // Make sure this bucket exists
    final res = await storage.from(bucket).upload(fileName, _deathCertFile!);
    if (res.error != null) throw Exception(res.error!.message);
    return storage.from(bucket).getPublicUrl(fileName);
  }

  Future<void> _submit() async {
    if (_dateOfDeath == null || _selectedBeneficiaryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields.')),
      );
      return;
    }
    setState(() => _submitting = true);

    try {
      // Upload death certificate if picked
      String? fileUrl;
      if (_deathCertFile != null) {
        fileUrl = await _uploadDeathCert();
      }

      // Update user as deceased and store death certificate URL
      await Supabase.instance.client
          .from('users')
          .update({
            'is_deceased': true,
            'date_of_death': _dateOfDeath!.toIso8601String(),
            if (fileUrl != null) 'death_certificate_url': fileUrl,
          })
          .eq('id', widget.memberId);

      // Mark beneficiary as eligible to claim
      await Supabase.instance.client
          .from('beneficiaries')
          .update({'eligible_to_claim': true})
          .eq('id', _selectedBeneficiaryId as Object);

      // Insert death notice with all details
      await Supabase.instance.client.from('death_notices').insert({
        'user_id': widget.memberId,
        'name': widget.memberName,
        'date_of_death': _dateOfDeath!.toIso8601String(),
        'barangay': _barangay,
        'latitude': _latitude,
        'longitude': _longitude,
        if (fileUrl != null) 'death_certificate_url': fileUrl,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member marked as deceased.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    } finally {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  widget.memberName,
                  style: const TextStyle(fontSize: 17, color: kNeutralText),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Date of death',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: kNeutralText,
              ),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _dateOfDeath = picked);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Text(
                      _dateOfDeath == null
                          ? 'Select date'
                          : '${_dateOfDeath!.year}-${_dateOfDeath!.month.toString().padLeft(2, '0')}-${_dateOfDeath!.day.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 17, color: kNeutralText),
                    ),
                    const Spacer(),
                    const Icon(Icons.calendar_today, color: kPrimaryDark),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Barangay',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: kNeutralText,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Enter barangay',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
              ),
              onChanged: (v) => setState(() => _barangay = v),
            ),
            const SizedBox(height: 18),
            Text(
              'Latitude',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: kNeutralText,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Enter latitude',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) => setState(() => _latitude = double.tryParse(v)),
            ),
            const SizedBox(height: 18),
            Text(
              'Longitude',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: kNeutralText,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Enter longitude',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) => setState(() => _longitude = double.tryParse(v)),
            ),
            const SizedBox(height: 18),
            Text(
              'Death Certificate',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: kNeutralText,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _submitting ? null : _pickDeathCert,
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    _deathCertFile == null ? 'Choose file' : 'Change file',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (_deathCertFile != null)
                  Expanded(
                    child: Text(
                      _deathCertFile!.path.split('/').last,
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'OpenSans',
                        color: kSubtleText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Beneficiary who can claim:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: kNeutralText,
              ),
            ),
            const SizedBox(height: 8),
            ..._beneficiaries.map(
              (b) => Row(
                children: [
                  Radio<String>(
                    value: b['id'].toString(),
                    groupValue: _selectedBeneficiaryId,
                    onChanged: (v) =>
                        setState(() => _selectedBeneficiaryId = v),
                  ),
                  Expanded(
                    child: Text(
                      b['full_name'] ?? '',
                      style: const TextStyle(fontSize: 16, color: kNeutralText),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: kAccent.withOpacity(.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      (b['status'] ?? '').toString().toLowerCase() == 'approved'
                          ? 'Eligible'
                          : (b['status'] ?? ''),
                      style: const TextStyle(
                        color: kAccent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Submit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  get error => null;
}
