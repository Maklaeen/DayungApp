import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
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
      await Supabase.instance.client.from('claims').insert({
        'user_id': user.id,
        'title': _title.text.trim(),
        'description': _desc.text.trim(),
        'status': 'Pending',
        'date_submitted': DateTime.now().toIso8601String(),
      });
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
    final width = MediaQuery.of(context).size.width;
    final padH = width > 640 ? width * 0.18 : 20;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(padH.toDouble(), 22, padH.toDouble(), 30),
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
            children: [
              Icon(Icons.description_outlined, size: 54, color: kPrimaryDark),
              const SizedBox(height: 12),
              const Text(
                'Claim Submission',
                style: TextStyle(
                  fontSize: 24,
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
                  fontSize: 13,
                  fontFamily: 'OpenSans',
                  color: kSubtleText.withOpacity(.85),
                ),
              ),
              const SizedBox(height: 26),
              TextFormField(
                controller: _title,
                textInputAction: TextInputAction.next,
                decoration: _fieldDec(label: 'Title', icon: Icons.title),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Enter a title';
                  if (t.length < 4) return 'Too short';
                  return null;
                },
              ),
              const SizedBox(height: 18),
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
              TextButton.icon(
                onPressed: _submitting ? null : () => Navigator.pop(context),
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
    );
  }
}
