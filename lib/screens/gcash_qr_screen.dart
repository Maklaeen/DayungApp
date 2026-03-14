import 'package:flutter/material.dart';

const Color kScreenBg = Color(0xFFFAFAF7);
const Color kScreenText = Color(0xFF1F2937);
const Color kScreenSubText = Color(0xFF6B7280);
const Color kScreenPrimary = Color(0xFF3B82F6);
const Color kScreenPrimaryDark = Color(0xFF1E40AF);

class GcashQrScreen extends StatelessWidget {
  const GcashQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> qrUrls = [
      'https://example.com/qr1.png',
      'https://example.com/qr2.png',
      'https://example.com/qr3.png',
    ];
    final isWide = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      backgroundColor: kScreenBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    kScreenPrimaryDark,
                    kScreenPrimary,
                    Color(0xFF60A5FA),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'GCash QR Gallery',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Review uploaded payment QR images in the same visual style as the rest of the app.',
                    style: TextStyle(
                      fontSize: isWide ? 15 : 14,
                      color: Colors.white.withValues(alpha: 0.88),
                      fontWeight: FontWeight.w600,
                      fontFamily: 'OpenSans',
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: qrUrls.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: const Icon(
                                  Icons.qr_code_2_rounded,
                                  size: 38,
                                  color: kScreenPrimaryDark,
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'No QR codes uploaded yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: kScreenText,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Uploaded QR images will appear here once payment collection starts.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: kScreenSubText,
                                  fontFamily: 'OpenSans',
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isWide ? 3 : 2,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: isWide ? 1.05 : 0.9,
                        ),
                        itemCount: qrUrls.length,
                        itemBuilder: (context, index) {
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x12000000),
                                  blurRadius: 14,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    qrUrls[index],
                                    fit: BoxFit.cover,
                                  ),
                                  Positioned(
                                    left: 12,
                                    right: 12,
                                    bottom: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.55,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Text(
                                        'QR ${index + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
