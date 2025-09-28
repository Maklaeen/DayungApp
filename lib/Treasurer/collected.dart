import 'package:flutter/material.dart';

// Palette
const Color kBg = Color(0xFFFAFAF7);
const Color kPrimaryDark = Color(0xFF083366);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);

class CollectedFromCollectorsPage extends StatelessWidget {
  final List<Map<String, dynamic>> collectors;

  const CollectedFromCollectorsPage({
    super.key,
    this.collectors = const [
      {'name': 'Collector 1', 'amount': 2000, 'members': 20},
      {'name': 'Collector 2', 'amount': 1800, 'members': 18},
      {'name': 'Collector 3', 'amount': 2400, 'members': 24},
      {'name': 'Collector 4', 'amount': 3000, 'members': 30},
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
          'Collected',
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
        child: GridView.builder(
          itemCount: collectors.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 18,
            crossAxisSpacing: 18,
            childAspectRatio: 1.1,
          ),
          itemBuilder: (context, i) {
            final c = collectors[i];
            return Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade300, width: 1.5),
              ),
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    c['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      fontFamily: 'Montserrat',
                      color: kNeutralText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '₱ ${c['amount']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                      fontFamily: 'Montserrat',
                      color: kNeutralText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${c['members']} collected\nfrom members',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'OpenSans',
                      color: kSubtleText,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}