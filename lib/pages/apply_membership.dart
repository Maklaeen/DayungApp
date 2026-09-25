import 'dart:typed_data';

import 'package:capstone_app/Beneficiary/beneficiary.dart';
import 'package:capstone_app/Providers/role_router.dart';
import 'package:capstone_app/pages/membership_agreement_page.dart';
import 'package:capstone_app/profile/required_application_page.dart';
import 'package:capstone_app/settings/profsettings.dart';
import 'package:capstone_app/utils/supabase_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApplyMembershipWizard extends StatefulWidget {
  final int dayungUnitId;
  final String dayungName;

  const ApplyMembershipWizard({
    super.key,
    required this.dayungUnitId,
    required this.dayungName,
  });

  @override
  State<ApplyMembershipWizard> createState() => _ApplyMembershipWizardState();
}

class _ApplyMembershipWizardState extends State<ApplyMembershipWizard> {
  final _supabase = Supabase.instance.client;
  int _step = 0;
  bool _loading = true;
  bool _agreed = false;
  bool _saving = false;
  String? _agreementTitle;
  List<RequiredApplicationSection> _agreementSections = [];
  String? _birthCertificate;
  String? _validId;

  @override
  void initState() {
    super.initState();
    _loadAgreement();
  }

  Future<void> _loadAgreement() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      final application = userId == null
          ? null
          : await _supabase
                .from('applications')
                .select('is_agree')
                .eq('user_id', userId)
                .eq('dayung_unit_id', widget.dayungUnitId)
                .maybeSingle();
      final rows = await _supabase
          .from('required_applications')
          .select('title, description, created_at')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .order('created_at', ascending: true)
          .order('id', ascending: true);
      final documents = userId == null
          ? null
          : await _supabase
                .from('users')
                .select('birth_certificate_url, valid_id')
                .eq('id', userId)
                .maybeSingle();
      final content = RequiredApplicationContent.fromRows(
        rows.map((row) => Map<String, dynamic>.from(row)).toList(),
      );
      if (!mounted) return;
      setState(() {
        _agreementTitle = content.mainTitle;
        _agreementSections = content.sections;
        _agreed = application?['is_agree'] == true;
        _birthCertificate = documents?['birth_certificate_url'] as String?;
        _validId = documents?['valid_id'] as String?;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _uploadDocument({required String type}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    final file = result?.files.single;
    if (file?.bytes == null) return;
    setState(() => _saving = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw StateError('User is not signed in.');
      final bucket = type == 'birth' ? 'birth_certificates' : 'valid_ids';
      final extension = (file!.extension ?? 'pdf').toLowerCase();
      final path = '$userId-${type}_certificate.$extension';
      final key = encrypt.Key.fromUtf8(
        'capstonedayungappjjm'.padRight(32).substring(0, 32),
      );
      final iv = encrypt.IV.fromLength(16);
      final encrypted = encrypt.Encrypter(
        encrypt.AES(key),
      ).encryptBytes(file.bytes!, iv: iv);
      await _supabase.storage
          .from(bucket)
          .uploadBinary(
            path,
            Uint8List.fromList(iv.bytes + encrypted.bytes),
            fileOptions: const FileOptions(upsert: true),
          );
      final reference = buildStorageRef(bucket, path);
      await _supabase
          .from('users')
          .update({
            if (type == 'birth') 'birth_certificate_url': reference,
            if (type == 'valid') 'valid_id': reference,
          })
          .eq('id', userId);
      if (!mounted) return;
      setState(() {
        if (type == 'birth') _birthCertificate = reference;
        if (type == 'valid') _validId = reference;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _hasBeneficiary() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;
    final rows = await _supabase
        .from('beneficiaries')
        .select('id')
        .eq('user_id', userId)
        .limit(1);
    return rows.isNotEmpty;
  }

  Future<bool> _hasRequiredProfileDocuments() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;
    final documents = await _supabase
        .from('users')
        .select(
          'birth_certificate_url, marriage_certificate_url, '
          'proof_of_residency_url, valid_id',
        )
        .eq('id', userId)
        .maybeSingle();
    if (documents == null) return false;

    return [
      documents['birth_certificate_url'],
      documents['marriage_certificate_url'],
      documents['proof_of_residency_url'],
      documents['valid_id'],
    ].every((value) => value is String && value.trim().isNotEmpty);
  }

  Future<void> _showBeneficiaryRequiredMessage() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 40),
              const SizedBox(height: 12),
              const Text(
                'Add at least one beneficiary first.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDocumentsRequiredMessage() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.upload_file_outlined, size: 40),
              const SizedBox(height: 12),
              const Text(
                'Upload all 4 profile documents before continuing.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAgreementAccepted() async {
    if (!mounted) return;
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final existing = await _supabase
          .from('applications')
          .select('id')
          .eq('user_id', userId)
          .eq('dayung_unit_id', widget.dayungUnitId)
          .maybeSingle();
      if (existing != null) {
        await _supabase
            .from('applications')
            .update({'is_agree': true})
            .eq('id', existing['id']);
        final updated = await _supabase
            .from('applications')
            .select('is_agree')
            .eq('id', existing['id'])
            .maybeSingle();
        if (!mounted) return;
        setState(() => _agreed = updated?['is_agree'] == true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to record agreement: $e')),
        );
      }
    }
  }

  Future<void> _confirmApplication() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    if (!await _hasRequiredProfileDocuments()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload all 4 profile documents first.')),
      );
      return;
    }
    if (!await _hasBeneficiary()) {
      await _showBeneficiaryRequiredMessage();
      return;
    }
    setState(() => _saving = true);
    try {
      final existing = await _supabase
          .from('applications')
          .select('id')
          .eq('user_id', userId)
          .eq('dayung_unit_id', widget.dayungUnitId)
          .maybeSingle();
      if (existing == null) {
        final unit = await _supabase
            .from('dayung_units')
            .select('secretary_id')
            .eq('id', widget.dayungUnitId)
            .maybeSingle();
        final inserted = await _supabase
            .from('applications')
            .insert({
              'user_id': userId,
              'dayung_unit_id': widget.dayungUnitId,
              'status': 'pending',
              'name': widget.dayungName,
              'is_agree': _agreed,
            })
            .select('id')
            .single();
        final secretaryId = unit?['secretary_id'];
        if (secretaryId != null) {
          try {
            await _supabase.from('dayung_application_notifications').insert({
              'application_id': inserted['id'],
              'dayung_unit_id': widget.dayungUnitId,
              'secretary_id': secretaryId,
            });
          } catch (_) {}
        }
      } else {
        await _supabase
            .from('applications')
            .update({'status': 'pending', 'is_agree': true})
            .eq('id', existing['id']);
      }
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const RoleRouter()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit application: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showApplicationConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var isBisaya = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final message = isBisaya
                ? 'Gikumpirma nako nga akong nasusi ug nasiguro ang tanang impormasyon '
                      'nga akong gihatag ug sakto ug kompleto kini. Nasabtan ug '
                      'giuyonan nako nga ang akong kasabutan, impormasyon sa '
                      'beneficiary, ug mga sertipiko nga akong gi-upload kay i-save '
                      'ug isumite para sa review.'
                : 'I acknowledge that I have reviewed all the information provided and '
                      'confirm that it is accurate and complete. I understand and agree '
                      'that my agreement, beneficiary information and uploaded '
                      'certificates will be securely saved and submitted for review.';

            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 24,
              ),
              title: Center(
                child: Text(
                  isBisaya ? 'Kumpirma ang Aplikasyon' : 'Confirm Application',
                ),
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () =>
                            setDialogState(() => isBisaya = !isBisaya),
                        icon: const Icon(Icons.translate),
                        label: Text(
                          isBisaya ? 'Show English' : 'Translate to Bisaya',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 25, height: 1.5),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(isBisaya ? 'Dili' : 'Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(isBisaya ? 'Kumpirma' : 'Confirm'),
                ),
              ],
              actionsAlignment: MainAxisAlignment.center,
            );
          },
        );
      },
    );

    if (confirmed == true && mounted) {
      await _confirmApplication();
    }
  }

  Future<void> _next() async {
    if (_step == 0 && !_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please agree to the Membership Agreement.'),
        ),
      );
      return;
    }

    if (_step == 1 && !await _hasBeneficiary()) {
      if (!mounted) return;
      await _showBeneficiaryRequiredMessage();
      return;
    }

    if (_step == 2 && !await _hasRequiredProfileDocuments()) {
      if (!mounted) return;
      await _showDocumentsRequiredMessage();
      return;
    }

    if (_step < 3) setState(() => _step++);
  }

  void _goToLogin() {
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['Agreement', 'Beneficiary', 'Certificates', 'Confirm'];
    return Scaffold(
      appBar: AppBar(
        title: Text('Apply to ${widget.dayungName}'),
        actions: [TextButton(onPressed: _goToLogin, child: const Text('BACK'))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                    child: Row(
                      children: List.generate(
                        titles.length,
                        (index) => Expanded(
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 15,
                                backgroundColor: index <= _step
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey.shade300,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                titles[index],
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: _buildStep()),
                ],
              ),
            ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return Column(
          children: [
            Expanded(
              child: MembershipAgreementPage(
                showBackButton: false,
                persistAgreement: false,
                initialContent: RequiredApplicationContent(
                  mainTitle: _agreementTitle ?? '',
                  sections: _agreementSections,
                ),
                initialAgreed: _agreed,
                onAgreementAccepted: _handleAgreementAccepted,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              child: FilledButton(
                onPressed: _agreed && !_saving ? _next : null,
                child: const Text('Next'),
              ),
            ),
          ],
        );
      case 1:
        return Column(
          children: [
            Expanded(
              child: BeneficiaryPage(embedded: true, showBackButton: false),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              child: FilledButton(
                onPressed: _saving ? null : _next,
                child: const Text('Continue'),
              ),
            ),
          ],
        );
      case 2:
        return Column(
          children: [
            const Expanded(
              child: ProfSettingsPage(
                showBackButton: false,
                showManageDayung: false,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              child: FilledButton(
                onPressed: _saving ? null : _next,
                child: const Text('Continue'),
              ),
            ),
          ],
        );
      default:
        return _stepCard(
          'Confirm Application',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You are applying to ${widget.dayungName}.',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your agreement, beneficiary, and uploaded certificates will be submitted for review.',
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : _showApplicationConfirmation,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Confirm and submit application'),
              ),
            ],
          ),
        );
    }
  }

  Widget _stepCard(String title, Widget body) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                body,
              ],
            ),
          ),
        ),
        if (_step < 3) ...[
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _next,
            child: const Text('Continue'),
          ),
        ],
        if (_step > 0)
          TextButton(
            onPressed: _saving ? null : () => setState(() => _step--),
            child: const Text('Back'),
          ),
      ],
    );
  }

  Widget _uploadTile(String title, String? reference, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        reference == null ? Icons.upload_file_outlined : Icons.verified_rounded,
      ),
      title: Text(title),
      subtitle: Text(reference == null ? 'Required' : 'Uploaded'),
      trailing: OutlinedButton(
        onPressed: _saving ? null : onTap,
        child: Text(reference == null ? 'Upload' : 'Replace'),
      ),
    );
  }
}
