import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

// Shared palette (aligned with claims page)
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);
const double kRadius = 18;

class SubmitClaimForm extends StatefulWidget {
  const SubmitClaimForm({super.key});
  @override
  State<SubmitClaimForm> createState() => _SubmitClaimFormState();
}

class _SubmitClaimFormState extends State<SubmitClaimForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  bool _submitting = false;
  File? _deathCertFile;
  // String? _deathCertUrl;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
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

  Future<String?> _uploadDeathCert(String claimId) async {
    if (_deathCertFile == null) return null;
    final storage = Supabase.instance.client.storage;
    final fileName =
        'death_cert_${claimId}_${DateTime.now().millisecondsSinceEpoch}.${_deathCertFile!.path.split('.').last}';
    final bucket = 'death_certificates'; // <-- This is the correct place!
    final res = await storage.from(bucket).upload(fileName, _deathCertFile!);
    if (res.error != null) throw Exception(res.error!.message);
    return storage.from(bucket).getPublicUrl(fileName);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not logged in.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      // 1. Insert claim (without file URL yet)
      final insertRes = await Supabase.instance.client
          .from('claims')
          .insert({
            'user_id': user.id,
            'title': _title.text.trim(),
            'description': _desc.text.trim(),
            'status': 'Pending',
            'date_submitted': DateTime.now().toIso8601String(),
          })
          .select()
          .single();
      final claimId = insertRes['id'].toString();

      // 2. Upload file if picked
      String? fileUrl;
      if (_deathCertFile != null) {
        fileUrl = await _uploadDeathCert(claimId);
        // 3. Update claim with file URL
        await Supabase.instance.client
            .from('claims')
            .update({'death_certificate_url': fileUrl})
            .eq('id', claimId);
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Claim submitted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Submit failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _fieldDec({
    required String label,
    required IconData icon,
    int lines = 1,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.grey.shade100,
      contentPadding: EdgeInsets.symmetric(
        vertical: lines > 1 ? 16 : 0,
        horizontal: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: kPrimaryDark, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = mq.size.width;
    final isTablet = width >= 600;
    final double padH = isTablet ? 24 : 16;

    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        // Lift above the keyboard when typing
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: Center(
          child: ConstrainedBox(
            // Keep a nice readable width on desktop/tablet
            constraints: BoxConstraints(
              maxWidth: 640,
              // Ensure the modal never exceeds the viewport height
              maxHeight: mq.size.height - 40,
            ),
            child: Material(
              color: Colors.transparent,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(padH, 22, padH, 30),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(kRadius),
                    border: Border.all(color: Colors.grey.shade300),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: isTablet ? 58 : 52,
                          color: kPrimaryDark,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Claim Submission',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isTablet ? 24 : 22,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Montserrat',
                            color: kNeutralText,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Provide clear details to speed up review.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isTablet ? 14 : 13,
                            fontFamily: 'OpenSans',
                            color: kSubtleText.withOpacity(.85),
                          ),
                        ),
                        const SizedBox(height: 26),

                        // Title
                        TextFormField(
                          controller: _title,
                          textInputAction: TextInputAction.next,
                          decoration: _fieldDec(
                            label: 'Title',
                            icon: Icons.title,
                          ),
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.isEmpty) return 'Enter a title';
                            if (t.length < 4) return 'Too short';
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),

                        // Description
                        TextFormField(
                          controller: _desc,
                          minLines: 4,
                          maxLines: 6,
                          decoration: _fieldDec(
                            label: 'Description (optional)',
                            icon: Icons.notes_outlined,
                            lines: 4,
                          ),
                        ),
                        const SizedBox(height: 30),

                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Death Certificate (PDF/JPG/PNG)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Montserrat',
                              fontSize: 15,
                              color: kNeutralText,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _submitting ? null : _pickDeathCert,
                              icon: const Icon(Icons.attach_file),
                              label: Text(
                                _deathCertFile == null
                                    ? 'Attach File'
                                    : 'Change File',
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
                        const SizedBox(height: 26),

                        // Submit
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _submitting ? null : _submit,
                            icon: _submitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
                            label: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                _submitting ? 'Submitting...' : 'Submit Claim',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Montserrat',
                                  letterSpacing: .4,
                                ),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimary,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(54),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Cancel
                        TextButton.icon(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          label: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontFamily: 'OpenSans',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension on String {
  get error => null;
}
