import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);

class ManageFundPage extends StatelessWidget {
  final List<Map<String, dynamic>> funds;

  const ManageFundPage({
    super.key,
    this.funds = const [
      {
        'name': 'Fund 1',
        'owner': 'Kaitlyn Olivia Jackson',
        'amount': 18700,
        'goal': 25900,
        'deadline': 'July 25, 2025',
        'status': 'Still Collecting...',
        'progress': 0.72,
      },
      {
        'name': 'Fund 2',
        'owner': null,
        'amount': 0,
        'goal': 25900,
        'deadline': 'July 25, 2025',
        'status': 'Opens upon Fund 1 disbursement',
        'progress': 0.0,
      },
    ],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kPrimaryDark, size: 28),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: const Text(
          'Manage Fund',
          style: TextStyle(
            color: kPrimaryDark,
            fontWeight: FontWeight.w800,
            fontSize: 22,
            fontFamily: 'Montserrat',
            letterSpacing: .2,
          ),
        ),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: SizedBox(
                width: 240,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // TODO: Add Fund logic
                  },
                  icon: const Icon(Icons.add, size: 24),
                  label: const Text(
                    'Add Fund',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView.separated(
                itemCount: funds.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 36,
                  thickness: 1.2,
                  color: Colors.grey,
                ),
                itemBuilder: (context, i) {
                  final f = funds[i];
                  return _fundCard(f);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fundCard(Map<String, dynamic> fund) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _bottleIcon(progress: fund['progress'] ?? 0.0),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fund['name'] ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  fontFamily: 'Montserrat',
                  color: kNeutralText,
                ),
              ),
              if (fund['owner'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    fund['owner'],
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      fontFamily: 'OpenSans',
                      color: kSubtleText,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '₱${fund['amount']} / ₱${fund['goal']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    fontFamily: 'Montserrat',
                    color: kNeutralText,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Deadline: ${fund['deadline']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    fontFamily: 'OpenSans',
                    color: kSubtleText,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  fund['status'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    fontFamily: 'OpenSans',
                    color: kSubtleText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bottleIcon({double progress = 0.0}) {
    return SizedBox(
      width: 60,
      height: 90,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          SvgPicture.asset('assets/bottle.svg', width: 60, height: 90),
          // Animated fill overlay
          Positioned(
            bottom: 12,
            left: 8,
            right: 8,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              height: 50 * progress,
              decoration: BoxDecoration(
                color: Colors.teal[200],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
