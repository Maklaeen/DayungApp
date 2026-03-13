import 'package:capstone_app/SuperAdmin/superadmin_support.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageBeneficiariesPage extends StatefulWidget {
  const ManageBeneficiariesPage({super.key});

  @override
  State<ManageBeneficiariesPage> createState() =>
      _ManageBeneficiariesPageState();
}

class _ManageBeneficiariesPageState extends State<ManageBeneficiariesPage> {
  late Future<List<Map<String, dynamic>>> _beneficiariesFuture;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _beneficiariesFuture = _fetchBeneficiaries();
  }

  Future<List<Map<String, dynamic>>> _fetchBeneficiaries() async {
    final res = await Supabase.instance.client
        .from('beneficiaries')
        .select(
          'id, full_name, dob, marital_status, relationship, status, eligible_to_claim',
        )
        .order('full_name', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> _refresh() async {
    setState(() {
      _beneficiariesFuture = _fetchBeneficiaries();
    });
    await _beneficiariesFuture;
  }

  void _showDetails(Map<String, dynamic> beneficiary) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (beneficiary['full_name'] ?? 'Beneficiary').toString(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: kSuperAdminText,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 16),
              _DetailRow(
                label: 'Relationship',
                value: _displayValue(beneficiary['relationship']),
              ),
              _DetailRow(
                label: 'Marital status',
                value: _displayValue(beneficiary['marital_status']),
              ),
              _DetailRow(
                label: 'Date of birth',
                value: _displayDate(beneficiary['dob']),
              ),
              _DetailRow(
                label: 'Status',
                value: _displayValue(beneficiary['status']),
              ),
              _DetailRow(
                label: 'Claim eligibility',
                value: beneficiary['eligible_to_claim'] == true
                    ? 'Eligible to claim'
                    : 'Not yet eligible',
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAFC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kSuperAdminBorder),
                ),
                child: const Text(
                  'Editing is not connected yet on this screen. This polished view is for review, search, and verification while the secure edit workflow is being finalized.',
                  style: TextStyle(color: kSuperAdminMuted, height: 1.5),
                ),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SuperAdminAccessGuard(
      title: 'Manage Beneficiaries',
      child: Scaffold(
        backgroundColor: superAdminBackground(context),
        body: SafeArea(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _beneficiariesFuture,
            builder: (context, snapshot) {
              final filtered = (snapshot.data ?? const <Map<String, dynamic>>[])
                  .where(
                    (beneficiary) =>
                        (beneficiary['full_name'] ?? '')
                            .toString()
                            .toLowerCase()
                            .contains(_search) ||
                        (beneficiary['relationship'] ?? '')
                            .toString()
                            .toLowerCase()
                            .contains(_search) ||
                        (beneficiary['status'] ?? '')
                            .toString()
                            .toLowerCase()
                            .contains(_search),
                  )
                  .toList();

              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  children: [
                    const _BeneficiariesHero(),
                    const SizedBox(height: 18),
                    _SearchCard(
                      searchValue: _search,
                      onChanged: (value) =>
                          setState(() => _search = value.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 16),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const _LoadingCard()
                    else if (snapshot.hasError)
                      _FeedbackCard(
                        icon: Icons.error_outline_rounded,
                        title: 'Unable to load beneficiaries',
                        message: snapshot.error.toString(),
                        actionLabel: 'Try again',
                        onAction: _refresh,
                      )
                    else if (snapshot.data == null || snapshot.data!.isEmpty)
                      _FeedbackCard(
                        icon: Icons.family_restroom_outlined,
                        title: 'No beneficiaries found',
                        message:
                            'There are no beneficiary records to review yet.',
                        actionLabel: 'Refresh',
                        onAction: _refresh,
                      )
                    else ...[
                      _BeneficiarySummaryBar(items: snapshot.data!),
                      const SizedBox(height: 16),
                      if (filtered.isEmpty)
                        _FeedbackCard(
                          icon: Icons.search_off_rounded,
                          title: 'No matching beneficiaries',
                          message:
                              'Try a different name, relationship, or status keyword.',
                          actionLabel: 'Clear search',
                          onAction: () async {
                            setState(() => _search = '');
                          },
                        )
                      else
                        ...filtered.map(
                          (beneficiary) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _BeneficiaryCard(
                              beneficiary: beneficiary,
                              onViewDetails: () => _showDetails(beneficiary),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _displayValue(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'Not provided' : text;
  }

  String _displayDate(Object? value) {
    final raw = value?.toString() ?? '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw.isEmpty ? 'Not provided' : raw;
    }
    final local = parsed.toLocal();
    return '${local.month}/${local.day}/${local.year}';
  }
}

class _BeneficiariesHero extends StatelessWidget {
  const _BeneficiariesHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17326B), Color(0xFF2756A4), Color(0xFF0F9D7A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _HeroIcon(),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Manage Beneficiaries',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          // Text(
          //   'Search and review beneficiary records with larger text, calmer colors, and clearer status labels for daily supervision.',
          //   style: TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
          // ),
        ],
      ),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Icon(
        Icons.family_restroom_rounded,
        color: Colors.white,
        size: 30,
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  final String searchValue;
  final ValueChanged<String> onChanged;

  const _SearchCard({required this.searchValue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kSuperAdminBorder),
      ),
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Search by beneficiary name, relationship, or status',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: searchValue.isEmpty
              ? null
              : const Icon(
                  Icons.check_circle_outline_rounded,
                  color: kSuperAdminAccent,
                ),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: kSuperAdminBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: kSuperAdminBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: kSuperAdminPrimary, width: 1.8),
          ),
        ),
      ),
    );
  }
}

class _BeneficiarySummaryBar extends StatelessWidget {
  final List<Map<String, dynamic>> items;

  const _BeneficiarySummaryBar({required this.items});

  @override
  Widget build(BuildContext context) {
    final eligibleCount = items
        .where((item) => item['eligible_to_claim'] == true)
        .length;
    final activeCount = items
        .where(
          (item) => (item['status'] ?? '').toString().toLowerCase().contains(
            'active',
          ),
        )
        .length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kSuperAdminBorder),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _SummaryChip(
            label: 'Total records',
            value: '${items.length}',
            color: kSuperAdminPrimary,
          ),
          _SummaryChip(
            label: 'Eligible to claim',
            value: '$eligibleCount',
            color: kSuperAdminAccent,
          ),
          _SummaryChip(
            label: 'Active status',
            value: '$activeCount',
            color: kSuperAdminWarn,
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: color, fontSize: 14),
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            TextSpan(text: label),
          ],
        ),
      ),
    );
  }
}

class _BeneficiaryCard extends StatelessWidget {
  final Map<String, dynamic> beneficiary;
  final VoidCallback onViewDetails;

  const _BeneficiaryCard({
    required this.beneficiary,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final eligible = beneficiary['eligible_to_claim'] == true;
    final status = (beneficiary['status'] ?? 'Unknown').toString();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kSuperAdminBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: kSuperAdminPrimary.withValues(alpha: 0.1),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: kSuperAdminPrimary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (beneficiary['full_name'] ?? 'No Name').toString(),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: kSuperAdminText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Relationship: ${(beneficiary['relationship'] ?? 'Not provided').toString()}',
                      style: const TextStyle(color: kSuperAdminMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatusPill(label: status, color: kSuperAdminPrimary),
              _StatusPill(
                label: eligible ? 'Eligible to claim' : 'Not yet eligible',
                color: eligible ? kSuperAdminAccent : kSuperAdminWarn,
              ),
              _StatusPill(
                label:
                    'Marital: ${(beneficiary['marital_status'] ?? 'Not provided').toString()}',
                color: const Color(0xFF4F46E5),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Birth date: ${(beneficiary['dob'] ?? 'Not provided').toString()}',
                  style: const TextStyle(color: kSuperAdminMuted),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onViewDetails,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('View details'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kSuperAdminPrimary,
                  side: const BorderSide(color: kSuperAdminBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: kSuperAdminMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: kSuperAdminText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kSuperAdminBorder),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  const _FeedbackCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kSuperAdminBorder),
      ),
      child: Column(
        children: [
          Icon(icon, size: 44, color: kSuperAdminPrimary),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kSuperAdminMuted, height: 1.5),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: kSuperAdminPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
