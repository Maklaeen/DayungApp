import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/profile/required_application_page.dart';
import 'package:capstone_app/utils/theme_surface.dart';

class MembershipAgreementPage extends StatefulWidget {
  final VoidCallback? onBack;
  final bool showBackButton;
  final RequiredApplicationContent? initialContent;

  const MembershipAgreementPage({
    super.key,
    this.onBack,
    this.showBackButton = true,
    this.initialContent,
  });

  static bool shouldShowAgreementContent({
    required bool hasApplicationRecord,
    required bool hasRequiredApplicationContent,
  }) {
    return hasApplicationRecord && hasRequiredApplicationContent;
  }

  @override
  State<MembershipAgreementPage> createState() =>
      _MembershipAgreementPageState();
}

class _MembershipAgreementPageState extends State<MembershipAgreementPage> {
  RequiredApplicationContent _content = RequiredApplicationContent.empty();
  bool _loading = false;
  bool _savingAgreement = false;
  bool _hasAgreed = false;
  int? _applicationId;

  @override
  void initState() {
    super.initState();
    if (widget.initialContent != null) {
      _content = widget.initialContent!;
      return;
    }
    _fetchAgreementContent();
  }

  Future<void> _fetchAgreementContent() async {
    setState(() => _loading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _content = RequiredApplicationContent.empty());
        return;
      }

      final applicationRows = await Supabase.instance.client
          .from('applications')
          .select('id, dayung_unit_id, is_agree')
          .eq('user_id', userId)
          .limit(1);

      final applicationRow = applicationRows.isNotEmpty
          ? applicationRows.first
          : null;
      final hasApplicationRecord = applicationRow != null;

      if (!hasApplicationRecord) {
        if (!mounted) return;
        setState(() => _content = RequiredApplicationContent.empty());
        return;
      }

      final applicationMap = Map<String, dynamic>.from(applicationRow as Map);
      final rawApplicationId = applicationMap['id'];
      if (rawApplicationId is int) {
        _applicationId = rawApplicationId;
      } else if (rawApplicationId is num) {
        _applicationId = rawApplicationId.toInt();
      } else if (rawApplicationId is String) {
        _applicationId = int.tryParse(rawApplicationId.trim());
      }

      final rawIsAgree = applicationMap['is_agree'];
      _hasAgreed =
          rawIsAgree == true ||
          rawIsAgree == 1 ||
          rawIsAgree == 't' ||
          rawIsAgree == 'true';

      int? dayungUnitId;
      final rawUnitId = applicationMap['dayung_unit_id'];
      if (rawUnitId is int) {
        dayungUnitId = rawUnitId;
      } else if (rawUnitId is num) {
        dayungUnitId = rawUnitId.toInt();
      } else if (rawUnitId is String) {
        dayungUnitId = int.tryParse(rawUnitId.trim());
      }

      if (dayungUnitId == null) {
        if (!mounted) return;
        setState(() => _content = RequiredApplicationContent.empty());
        return;
      }

      final rows = await Supabase.instance.client
          .from('required_applications')
          .select('title, description, dayung_unit_id')
          .eq('dayung_unit_id', dayungUnitId)
          .order('id', ascending: true);

      if (!mounted) return;

      final parsedRows = rows
          .whereType<Map<String, dynamic>>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      final hasRequiredApplicationContent = parsedRows.any((row) {
        final title = (row['title'] ?? '').toString().trim();
        final description = (row['description'] ?? '').toString().trim();
        return title.isNotEmpty || description.isNotEmpty;
      });

      setState(() {
        _content =
            MembershipAgreementPage.shouldShowAgreementContent(
              hasApplicationRecord: hasApplicationRecord,
              hasRequiredApplicationContent: hasRequiredApplicationContent,
            )
            ? RequiredApplicationContent.fromRows(parsedRows)
            : RequiredApplicationContent.empty();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load agreement: $e')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _handleAgreementAccept() async {
    if (!mounted || _savingAgreement) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Membership Agreement'),
        content: const Text(
          'Do you agree to the membership terms and want to mark your application as accepted?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Agree'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _saveAgreement();
  }

  Future<void> _saveAgreement() async {
    if (!mounted) return;
    setState(() => _savingAgreement = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        throw StateError('User is not signed in.');
      }

      final applicationId = _applicationId;
      final matchMap = applicationId != null
          ? {'id': applicationId}
          : {'user_id': userId};

      await Supabase.instance.client
          .from('applications')
          .update({'is_agree': true})
          .match(matchMap);

      final checkResult = await Supabase.instance.client
          .from('applications')
          .select('id, is_agree')
          .match(matchMap)
          .limit(1);

      if (checkResult.isEmpty) {
        throw StateError('No application record was found after update.');
      }

      final updatedRow = Map<String, dynamic>.from(checkResult.first as Map);
      final updatedValue = updatedRow['is_agree'];
      if (updatedValue != true &&
          updatedValue != 1 &&
          updatedValue != 't' &&
          updatedValue != 'true') {
        throw StateError(
          'Application update did not persist is_agree. value=$updatedValue',
        );
      }

      if (!mounted) return;
      setState(() => _hasAgreed = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your agreement has been recorded.'),
          backgroundColor: Color(0xFF16A34A),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to record agreement: $e')));
    } finally {
      if (mounted) {
        setState(() => _savingAgreement = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            isWide ? 28 : 18,
            18,
            isWide ? 28 : 18,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showBackButton)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    onPressed:
                        widget.onBack ??
                        () {
                          Navigator.of(context).pop();
                        },
                    icon: const Icon(Icons.arrow_back_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(isWide ? 24 : 20),
                decoration: dayungSectionCardDecoration(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Membership Agreement',
                      style: TextStyle(
                        fontSize: isWide ? 24 : 20,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E40AF),
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Please review the membership agreement below before continuing.',
                      style: TextStyle(
                        fontSize: isWide ? 16 : 14,
                        color: const Color(0xFF4B5563),
                        fontFamily: 'OpenSans',
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (_content.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: const Text(
                          'No agreement details are available yet.',
                          style: TextStyle(
                            color: Color(0xFF4B5563),
                            fontFamily: 'OpenSans',
                            height: 1.6,
                          ),
                        ),
                      )
                    else ...[
                      if (_content.mainTitle.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _content.mainTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                              fontFamily: 'Montserrat',
                            ),
                          ),
                        ),
                      for (final section in _content.sections)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _AgreementSection(
                            title: section.title,
                            body: section.description,
                          ),
                        ),
                    ],
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _hasAgreed
                            ? 'You already agreed to the membership terms.'
                            : 'Please click I Agree below to confirm your agreement.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isWide ? 15 : 14,
                          color: const Color(0xFF6B7280),
                          fontFamily: 'OpenSans',
                          height: 1.5,
                        ),
                      ),
                    ),
                    Center(
                      child: InkWell(
                        onTap: (!_hasAgreed && !_savingAgreement)
                            ? _handleAgreementAccept
                            : null,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxWidth: 360),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: _hasAgreed
                                ? const Color(0xFF9CA3AF)
                                : const Color(0xFF16A34A),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (_hasAgreed
                                            ? const Color(0xFF9CA3AF)
                                            : const Color(0xFF16A34A))
                                        .withValues(alpha: 0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Center(
                            child: _savingAgreement
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _hasAgreed ? 'Already Agreed' : 'I Agree',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgreementSection extends StatelessWidget {
  final String title;
  final String body;

  const _AgreementSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
              fontFamily: 'Montserrat',
            ),
          ),
          if (body.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              body,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF4B5563),
                fontFamily: 'OpenSans',
                height: 1.6,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
