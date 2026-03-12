import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Color palette (from dashboard.dart)
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimaryLight = Color(0xFF3B82F6);
const kAccentDark = Color(0xFF059669);
const kCardBg = Color(0xFFFFFFFF);

class PresidentClaimsPage extends StatefulWidget {
  final int dayungUnitId;
  const PresidentClaimsPage({super.key, required this.dayungUnitId});

  @override
  State<PresidentClaimsPage> createState() => _PresidentClaimsPageState();
}

class _PresidentClaimsPageState extends State<PresidentClaimsPage> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _claims = [];
  Map<String, String> _userNames = {};

  @override
  void initState() {
    super.initState();
    _loadClaims();
  }

  Future<void> _loadClaims() async {
    setState(() => _loading = true);
    final rows = await _sb
        .from('claims')
        .select()
        .eq('dayung_unit_id', widget.dayungUnitId);

    final claims = List<Map<String, dynamic>>.from(rows);
    final userIds = claims
        .map((row) => (row['user_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final userNames = <String, String>{};
    if (userIds.isNotEmpty) {
      final users = await _sb
          .from('users')
          .select('id, full_name')
          .inFilter('id', userIds);
      for (final user in List<Map<String, dynamic>>.from(users)) {
        final id = (user['id'] ?? '').toString();
        final fullName = (user['full_name'] ?? '').toString().trim();
        if (id.isNotEmpty && fullName.isNotEmpty) {
          userNames[id] = fullName;
        }
      }
    }

    setState(() {
      _claims = claims;
      _userNames = userNames;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: _loading
          ? const DayungPageSkeleton(
              layout: DayungSkeletonLayout.list,
              itemCount: 5,
            )
          : _claims.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, color: kSubText, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'No claims found.',
                    style: TextStyle(color: kSubText, fontSize: 18),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _claims.length,
              itemBuilder: (context, idx) {
                final claim = _claims[idx];
                final createdAt =
                    claim['created_at']?.toString().split('T').first ?? '';
                final status = claim['status']?.toString() ?? '';
                final claimType = claim['claim_type']?.toString() ?? 'Claim';
                final userId = claim['user_id']?.toString() ?? '';
                final memberName = _userNames[userId] ?? 'Unknown member';
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 2,
                  color: kCardBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    child: Row(
                      children: [
                        // Claim details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                claimType,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: kPrimaryLight,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Status: $status',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: status == 'approved'
                                      ? kAccentDark
                                      : kSubText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Filed by: $memberName',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: kText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Date
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Date',
                              style: TextStyle(fontSize: 13, color: kSubText),
                            ),
                            Text(
                              createdAt,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: kPrimaryLight,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
