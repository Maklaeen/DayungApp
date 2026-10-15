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
        .select('proof_of_residency_url, valid_id')
        .eq('id', userId)
        .maybeSingle();
    if (documents == null) return false;

    return [
      documents['proof_of_residency_url'],
      documents['valid_id'],
    ].every((value) => value is String && value.trim().isNotEmpty);
  }

  Future<void> _showBeneficiaryRequiredMessage() async {
    await _showRequirementDialog(
      icon: Icons.groups_2_outlined,
      title: 'Beneficiary required',
      message:
          'Add at least one beneficiary to your profile before continuing with this application.',
    );
  }

  Future<void> _showDocumentsRequiredMessage() async {
    await _showRequirementDialog(
      icon: Icons.folder_open_outlined,
      title: 'Documents required',
      message: 'Upload your Proof of Residency and Valid ID before continuing.',
    );
  }

  Future<void> _showRequirementDialog({
    required IconData icon,
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(icon, size: 30, color: const Color(0xFF1E40AF)),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 15,
                    height: 1.5,
                    fontFamily: 'OpenSans',
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    child: const Text('Got it'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmApplicationDialog(
    BuildContext dialogContext,
    bool isBisaya,
    VoidCallback onToggleLanguage,
  ) {
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

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.fact_check_outlined,
                  size: 30,
                  color: Color(0xFF1E40AF),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isBisaya ? 'Kumpirma ang Aplikasyon' : 'Confirm Application',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isBisaya
                    ? 'Palihog susiha ang imong aplikasyon sa dili pa isumite.'
                    : 'Please review your application before submitting.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 14,
                  height: 1.4,
                  fontFamily: 'OpenSans',
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onToggleLanguage,
                  icon: const Icon(Icons.translate_rounded, size: 18),
                  label: Text(
                    isBisaya ? 'Show English' : 'Translate to Bisaya',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1E40AF),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 15,
                        height: 1.6,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4B5563),
                        minimumSize: const Size.fromHeight(50),
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(isBisaya ? 'Dili' : 'Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(isBisaya ? 'Kumpirma' : 'Confirm'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                    ),
                  ),
                ],
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
        const SnackBar(
          content: Text('Upload Proof of Residency and Valid ID first.'),
        ),
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
            return _buildConfirmApplicationDialog(
              dialogContext,
              isBisaya,
              () => setDialogState(() => isBisaya = !isBisaya),
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

  void _goBack() {
    if (_saving) return;
    if (_step == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _step--);
  }

  String get _currentStepTitle => switch (_step) {
    0 => 'Membership Agreement',
    1 => 'Beneficiary details',
    2 => 'Certificates',
    _ => 'Review application',
  };

  String get _currentStepDescription => switch (_step) {
    0 => 'Review and accept the terms before continuing.',
    1 => 'Add at least one beneficiary to your application.',
    2 => 'Upload the required documents for verification.',
    _ => 'Review the details before submitting your application.',
  };

  Widget _buildWizardHeader() {
    const titles = ['Agreement', 'Beneficiary', 'Certificates', 'Confirm'];
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 20, 18),
      decoration: const BoxDecoration(
        color: Color(0xFF0D47A1),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Color(0x261E40AF),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: _step == 0 ? 'Back to dashboard' : 'Previous step',
                onPressed: _goBack,
                icon: const Icon(Icons.arrow_back_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(48, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Apply to ${widget.dayungName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _currentStepTitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.84),
                        fontSize: 13,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: List.generate(titles.length, (index) {
              final isComplete = index < _step;
              final isCurrent = index == _step;
              final active = index <= _step;

              return Expanded(
                child: Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: isCurrent ? 34 : 28,
                          height: isCurrent ? 34 : 28,
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(
                                alpha: active ? 1 : 0.35,
                              ),
                            ),
                          ),
                          child: Icon(
                            isComplete ? Icons.check_rounded : _stepIcon(index),
                            size: 16,
                            color: active
                                ? colorScheme.primary
                                : Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          titles[index],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.64),
                            fontSize: 10,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                      ],
                    ),
                    if (index < titles.length - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.only(
                            left: 4,
                            right: 4,
                            bottom: 20,
                          ),
                          color: index < _step
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.28),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  IconData _stepIcon(int index) => switch (index) {
    0 => Icons.description_outlined,
    1 => Icons.groups_2_outlined,
    2 => Icons.folder_outlined,
    _ => Icons.fact_check_outlined,
  };

  Widget _buildStepFooter({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFamily: 'Montserrat',
              ),
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _step > 0 && !_saving) {
          setState(() => _step--);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _buildWizardHeader(),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                        child: Container(
                          width: double.infinity,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x100F172A),
                                blurRadius: 18,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: _buildStep(),
                        ),
                      ),
                    ),
                  ],
                ),
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
            _buildStepFooter(
              label: 'Agree and continue',
              onPressed: _agreed && !_saving ? _next : null,
            ),
          ],
        );
      case 1:
        return Column(
          children: [
            Expanded(
              child: BeneficiaryPage(
                embedded: true,
                showBackButton: false,
                dayungUnitId: widget.dayungUnitId,
              ),
            ),
            _buildStepFooter(
              label: 'Continue to certificates',
              onPressed: _saving ? null : _next,
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
                embedded: true,
              ),
            ),
            _buildStepFooter(
              label: 'Review application',
              onPressed: _saving ? null : _next,
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
      padding: const EdgeInsets.all(22),
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1F2937),
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _currentStepDescription,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            height: 1.5,
            fontFamily: 'OpenSans',
          ),
        ),
        const SizedBox(height: 20),
        body,
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
