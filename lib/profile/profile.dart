import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:capstone_app/Auth/login.dart' hide kWarn;
import 'package:capstone_app/Beneficiary/beneficiary.dart' hide kPrimaryLight;
import 'package:capstone_app/President/manage_rules.dart' hide kPrimary;
import 'package:capstone_app/Providers/apptheme_provider.dart';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/profile/dayung_profile.dart';
import 'package:capstone_app/profile/required_application_page.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dropdown_button2/dropdown_button2.dart';

// color palette
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimaryLight = Color(0xFF3B82F6);
const kAccentDark = Color(0xFF059669);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;

  final _fullNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _addressController = TextEditingController();
  final _sexController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  final _currentPwController = TextEditingController();
  final _newPwController = TextEditingController();
  final _confirmPwController = TextEditingController();

  String fullName = '';
  String mobileNumber = '';
  String address = '';
  String sex = '';
  String? profileUrl;
  String? birthCertificateUrl;
  String? marriageCertificateUrl;
  String? validIdUrl; // Add this field to hold the valid ID URL
  String?
  proofOfResidencyUrl; // Add this field to hold the proof of residency URL
  // ignore: unused_field
  int? _unitAtEntry;

  bool _obscureCur = true;
  bool _obscureNew = true;
  bool _obscureConf = true;
  bool _loggingOut = false;
  bool isLoading = true;
  bool _editing = false;
  bool _saving = false;
  bool _uploadingImage = false;
  bool get isPresident {
    try {
      return context.select<DayungRoleProvider, bool>((r) => r.isPresident);
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
    _loadUnitAtEntry();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final unitId = context.read<DayungUnitProvider>().currentUnitId;
      context.read<DayungRoleProvider>().refreshRoles(unitId);
    });
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _sexController.dispose();
    _currentPwController.dispose();
    _newPwController.dispose();
    _confirmPwController.dispose();
    super.dispose();
  }

  Future<void> _loadUnitAtEntry() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('selectedDayungUnit');
    int? id;
    if (raw != null) {
      try {
        id = (jsonDecode(raw) as Map)['id'] as int?;
      } catch (_) {}
    }
    if (mounted) setState(() => _unitAtEntry = id);
  }

  // Future<bool> _handleBackNavigate() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   final raw = prefs.getString('selectedDayungUnit');
  //   int? currentId;
  //   if (raw != null) {
  //     try {
  //       currentId = (jsonDecode(raw) as Map)['id'] as int?;
  //     } catch (_) {}
  //   }

  //   if (currentId != null && currentId != _unitAtEntry) {
  //     final roles = context.read<DayungRoleProvider>();
  //     final Widget home = roles.isPresident
  //         ? const PresidentDashboardPage()
  //         : roles.isSecretary
  //         ? const SecretaryDashboardPage()
  //         : roles.isTreasurer
  //         ? const TreasurerDashboardPage()
  //         : roles.isCollector
  //         ? const CollectorDashboardPage()
  //         : const MemberDashboardPage();

  //     if (!mounted) return false;
  //     Navigator.of(context).pushAndRemoveUntil(
  //       MaterialPageRoute(builder: (_) => home),
  //       (route) => false,
  //     );
  //     return false; // we handled navigation
  //   }
  //   return true; // normal back
  // }

  // void _openCertificate(String url) {
  //   showDialog(
  //     context: context,
  //     builder: (ctx) => AlertDialog(
  //       title: const Text('Certificate'),
  //       content: url.endsWith('.pdf')
  //           ? Text('Open this PDF in browser?')
  //           : Image.network(url, fit: BoxFit.contain, height: 300),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Navigator.pop(ctx),
  //           child: const Text('Close'),
  //         ),
  //         if (url.endsWith('.pdf'))
  //           TextButton(
  //             onPressed: () {
  //               Navigator.pop(ctx);
  //               launchUrl(Uri.parse(url));
  //             },
  //             child: const Text('Open PDF'),
  //           ),
  //       ],
  //     ),
  //   );
  // }

  // Widget _certificateRow({
  //   required String label,
  //   required String? url,
  //   required VoidCallback onUpload,
  //   required VoidCallback onView,
  //   required Color labelColor,
  // }) {
  //   return Row(
  //     children: [
  //       Icon(
  //         url != null && url.isNotEmpty
  //             ? Icons.check_circle
  //             : Icons.warning_amber_rounded,
  //         color: url != null && url.isNotEmpty ? Colors.green : Colors.red,
  //       ),
  //       const SizedBox(width: 8),
  //       Expanded(
  //         child: Text(
  //           label,
  //           style: TextStyle(
  //             fontSize: 15,
  //             fontWeight: FontWeight.w600,
  //             color: labelColor,
  //           ),
  //         ),
  //       ),
  //       if (url != null && url.isNotEmpty)
  //         IconButton(
  //           icon: const Icon(Icons.open_in_new, color: kAccent),
  //           tooltip: 'View',
  //           onPressed: () => _openCertificate(url),
  //         ),
  //       // Always show the upload/replace button
  //       ElevatedButton.icon(
  //         icon: const Icon(Icons.upload_file),
  //         label: Text(url != null && url.isNotEmpty ? 'Replace' : 'Add'),
  //         style: ElevatedButton.styleFrom(
  //           backgroundColor: kAccent,
  //           foregroundColor: Colors.white,
  //           padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  //           shape: RoundedRectangleBorder(
  //             borderRadius: BorderRadius.circular(10),
  //           ),
  //         ),
  //         onPressed: onUpload,
  //       ),
  //     ],
  //   );
  // }

  // Future<void> _showPinModal({required bool hasPin}) async {
  //   String? err;
  //   final pinController = TextEditingController();
  //   final confirmController = TextEditingController();
  //   final oldPinController = TextEditingController();
  //   bool saving = false;

  //   await showGeneralDialog<void>(
  //     context: context,
  //     barrierDismissible: !saving,
  //     barrierColor: Colors.black.withOpacity(0.35),
  //     barrierLabel: hasPin ? 'Change PIN' : 'Set up PIN',
  //     transitionDuration: const Duration(milliseconds: 220),
  //     pageBuilder: (_, __, ___) => const SizedBox.shrink(),
  //     transitionBuilder: (ctx, anim, __, ___) {
  //       final curved = CurvedAnimation(
  //         parent: anim,
  //         curve: Curves.easeOutCubic,
  //         reverseCurve: Curves.easeInCubic,
  //       );
  //       return FadeTransition(
  //         opacity: curved,
  //         child: ScaleTransition(
  //           scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
  //           child: Center(
  //             child: StatefulBuilder(
  //               builder: (ctx, setD) {
  //                 return Material(
  //                   color: Colors.transparent,
  //                   child: ConstrainedBox(
  //                     constraints: const BoxConstraints(maxWidth: 420),
  //                     child: Container(
  //                       margin: EdgeInsets.fromLTRB(
  //                         24,
  //                         0,
  //                         24,
  //                         MediaQuery.of(ctx).viewInsets.bottom + 24,
  //                       ),
  //                       padding: const EdgeInsets.symmetric(
  //                         horizontal: 20,
  //                         vertical: 24,
  //                       ),
  //                       decoration: BoxDecoration(
  //                         color: Colors.white,
  //                         borderRadius: BorderRadius.circular(18),
  //                         border: Border.all(
  //                           color: Colors.black12.withOpacity(0.45),
  //                         ),
  //                         boxShadow: const [
  //                           BoxShadow(
  //                             color: Colors.black26,
  //                             blurRadius: 18,
  //                             offset: Offset(0, 12),
  //                           ),
  //                         ],
  //                       ),
  //                       child: Column(
  //                         mainAxisSize: MainAxisSize.min,
  //                         children: [
  //                           Row(
  //                             children: [
  //                               Container(
  //                                 width: 40,
  //                                 height: 40,
  //                                 decoration: BoxDecoration(
  //                                   color: kAccent.withOpacity(0.12),
  //                                   borderRadius: BorderRadius.circular(12),
  //                                 ),
  //                                 child: const Icon(
  //                                   Icons.pin_rounded,
  //                                   color: kAccent,
  //                                 ),
  //                               ),
  //                               const SizedBox(width: 12),
  //                               Expanded(
  //                                 child: Text(
  //                                   hasPin
  //                                       ? 'Change App PIN'
  //                                       : 'Set up App PIN',
  //                                   style: const TextStyle(
  //                                     color: kText,
  //                                     fontSize: 18,
  //                                     fontWeight: FontWeight.w800,
  //                                   ),
  //                                 ),
  //                               ),
  //                               IconButton(
  //                                 onPressed: saving
  //                                     ? null
  //                                     : () => Navigator.of(ctx).pop(),
  //                                 icon: const Icon(
  //                                   Icons.close,
  //                                   color: kSubText,
  //                                 ),
  //                                 tooltip: 'Close',
  //                               ),
  //                             ],
  //                           ),
  //                           const SizedBox(height: 18),
  //                           if (hasPin)
  //                             Column(
  //                               children: [
  //                                 TextField(
  //                                   controller: oldPinController,
  //                                   keyboardType: TextInputType.number,
  //                                   maxLength: 6,
  //                                   obscureText: true,
  //                                   decoration: InputDecoration(
  //                                     labelText: 'Current PIN',
  //                                     filled: true,
  //                                     fillColor: Colors.white,
  //                                     contentPadding:
  //                                         const EdgeInsets.symmetric(
  //                                           horizontal: 14,
  //                                           vertical: 14,
  //                                         ),
  //                                     border: OutlineInputBorder(
  //                                       borderRadius: BorderRadius.circular(12),
  //                                     ),
  //                                   ),
  //                                 ),
  //                                 const SizedBox(height: 12),
  //                               ],
  //                             ),
  //                           TextField(
  //                             controller: pinController,
  //                             keyboardType: TextInputType.number,
  //                             maxLength: 6,
  //                             obscureText: true,
  //                             decoration: InputDecoration(
  //                               labelText: 'Enter 6-digit PIN',
  //                               filled: true,
  //                               fillColor: Colors.white,
  //                               contentPadding: const EdgeInsets.symmetric(
  //                                 horizontal: 14,
  //                                 vertical: 14,
  //                               ),
  //                               border: OutlineInputBorder(
  //                                 borderRadius: BorderRadius.circular(12),
  //                               ),
  //                             ),
  //                           ),
  //                           const SizedBox(height: 8),
  //                           TextField(
  //                             controller: confirmController,
  //                             keyboardType: TextInputType.number,
  //                             maxLength: 6,
  //                             obscureText: true,
  //                             decoration: InputDecoration(
  //                               labelText: 'Confirm PIN',
  //                               filled: true,
  //                               fillColor: Colors.white,
  //                               contentPadding: const EdgeInsets.symmetric(
  //                                 horizontal: 14,
  //                                 vertical: 14,
  //                               ),
  //                               border: OutlineInputBorder(
  //                                 borderRadius: BorderRadius.circular(12),
  //                               ),
  //                             ),
  //                           ),
  //                           if (err != null)
  //                             Padding(
  //                               padding: const EdgeInsets.only(top: 6),
  //                               child: Row(
  //                                 crossAxisAlignment: CrossAxisAlignment.start,
  //                                 children: [
  //                                   const Icon(
  //                                     Icons.error_outline,
  //                                     color: kWarn,
  //                                     size: 18,
  //                                   ),
  //                                   const SizedBox(width: 6),
  //                                   Expanded(
  //                                     child: Text(
  //                                       err!,
  //                                       style: const TextStyle(
  //                                         color: kWarn,
  //                                         fontSize: 13.5,
  //                                         height: 1.2,
  //                                       ),
  //                                     ),
  //                                   ),
  //                                 ],
  //                               ),
  //                             ),
  //                           const SizedBox(height: 24),
  //                           SizedBox(
  //                             width: double.infinity,
  //                             height: 48,
  //                             child: ElevatedButton(
  //                               onPressed: saving
  //                                   ? null
  //                                   : () async {
  //                                       setD(() => err = null);
  //                                       final pin = pinController.text.trim();
  //                                       final confirm = confirmController.text
  //                                           .trim();
  //                                       if (pin.length != 6 ||
  //                                           confirm.length != 6) {
  //                                         setD(
  //                                           () => err = 'PIN must be 6 digits.',
  //                                         );
  //                                         return;
  //                                       }
  //                                       if (pin != confirm) {
  //                                         setD(
  //                                           () => err = 'PINs do not match.',
  //                                         );
  //                                         return;
  //                                       }
  //                                       if (hasPin) {
  //                                         final oldPin = oldPinController.text
  //                                             .trim();
  //                                         if (oldPin.length != 6) {
  //                                           setD(
  //                                             () => err =
  //                                                 'Enter your current PIN.',
  //                                           );
  //                                           return;
  //                                         }
  //                                         final valid = await PinLock.verify(
  //                                           oldPin,
  //                                         );
  //                                         if (!valid) {
  //                                           setD(
  //                                             () => err =
  //                                                 'Current PIN is incorrect.',
  //                                           );
  //                                           return;
  //                                         }
  //                                       }
  //                                       setD(() => saving = true);
  //                                       await PinLock.setPin(pin);
  //                                       if (!ctx.mounted) return;
  //                                       setD(() => saving = false);
  //                                       Navigator.of(ctx).pop();
  //                                       _showTopPopup(
  //                                         hasPin
  //                                             ? 'PIN updated successfully'
  //                                             : 'PIN set successfully',
  //                                         color: kAccent,
  //                                         icon: Icons.check_circle,
  //                                       );
  //                                     },
  //                               style: ElevatedButton.styleFrom(
  //                                 backgroundColor: kAccent,
  //                                 foregroundColor: Colors.white,
  //                                 shape: RoundedRectangleBorder(
  //                                   borderRadius: BorderRadius.circular(12),
  //                                 ),
  //                                 elevation: 0,
  //                               ),
  //                               child: saving
  //                                   ? const SizedBox(
  //                                       width: 22,
  //                                       height: 22,
  //                                       child: CircularProgressIndicator(
  //                                         color: Colors.white,
  //                                         strokeWidth: 2.5,
  //                                       ),
  //                                     )
  //                                   : Text(
  //                                       hasPin ? 'Change PIN' : 'Set PIN',
  //                                       style: const TextStyle(
  //                                         fontWeight: FontWeight.w700,
  //                                       ),
  //                                     ),
  //                             ),
  //                           ),
  //                         ],
  //                       ),
  //                     ),
  //                   ),
  //                 );
  //               },
  //             ),
  //           ),
  //         ),
  //       );
  //     },
  //   );
  // }

  Future<void> _openChangePasswordDialog() async {
    _currentPwController.clear();
    _newPwController.clear();
    _confirmPwController.clear();

    String? curErr;
    String? newErr;
    String? confErr;
    String? genErr;
    bool saving = false;

    InputDecoration dec(String label, {IconData? icon, bool error = false}) {
      return InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: kSubText) : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: error ? kWarn : const Color(0xFFE5E7EB),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: error ? kWarn : kAccent, width: 2),
        ),
        errorText: null, // we render custom error rows below
      );
    }

    Widget errRow(String msg) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: kWarn, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(color: kWarn, fontSize: 13.5, height: 1.2),
            ),
          ),
        ],
      ),
    );

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: !saving,
      barrierColor: Colors.black.withOpacity(0.35),
      barrierLabel: 'Change Password',
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, ___) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: Center(
              child: StatefulBuilder(
                builder: (ctx, setD) {
                  return Material(
                    color: Colors.transparent,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Container(
                        margin: EdgeInsets.fromLTRB(
                          24,
                          0,
                          24,
                          MediaQuery.of(ctx).viewInsets.bottom + 24,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: (genErr != null ? kWarn : Colors.black12)
                                .withOpacity(0.45),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 18,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Title
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: kAccent.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.lock_reset,
                                    color: kAccent,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Change Password',
                                    style: TextStyle(
                                      color: kText,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: saving
                                      ? null
                                      : () => Navigator.of(ctx).pop(),
                                  icon: const Icon(
                                    Icons.close,
                                    color: kSubText,
                                  ),
                                  tooltip: 'Close',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // General error (e.g., offline)
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: genErr == null
                                  ? const SizedBox.shrink()
                                  : errRow(genErr!),
                            ),
                            if (genErr != null) const SizedBox(height: 8),

                            // Current password
                            TextField(
                              controller: _currentPwController,
                              obscureText: _obscureCur,
                              onChanged: (_) => setD(() {
                                curErr = null;
                                genErr = null;
                              }),
                              decoration:
                                  dec(
                                    'Current password',
                                    icon: Icons.lock_outline,
                                    error: curErr != null,
                                  ).copyWith(
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureCur
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: kSubText,
                                      ),
                                      onPressed: () => setD(
                                        () => _obscureCur = !_obscureCur,
                                      ),
                                    ),
                                  ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: curErr == null
                                  ? const SizedBox.shrink()
                                  : errRow(curErr!),
                            ),
                            const SizedBox(height: 12),

                            // New password
                            TextField(
                              controller: _newPwController,
                              obscureText: _obscureNew,
                              onChanged: (_) => setD(() {
                                newErr = null;
                                genErr = null;
                              }),
                              decoration:
                                  dec(
                                    'New password (min 6 chars)',
                                    icon: Icons.password_outlined,
                                    error: newErr != null,
                                  ).copyWith(
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureNew
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: kSubText,
                                      ),
                                      onPressed: () => setD(
                                        () => _obscureNew = !_obscureNew,
                                      ),
                                    ),
                                  ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: newErr == null
                                  ? const SizedBox.shrink()
                                  : errRow(newErr!),
                            ),
                            const SizedBox(height: 12),

                            // Confirm password
                            TextField(
                              controller: _confirmPwController,
                              obscureText: _obscureConf,
                              onChanged: (_) => setD(() {
                                confErr = null;
                                genErr = null;
                              }),
                              decoration:
                                  dec(
                                    'Confirm new password',
                                    icon: Icons.lock_person_outlined,
                                    error: confErr != null,
                                  ).copyWith(
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureConf
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: kSubText,
                                      ),
                                      onPressed: () => setD(
                                        () => _obscureConf = !_obscureConf,
                                      ),
                                    ),
                                  ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: confErr == null
                                  ? const SizedBox.shrink()
                                  : errRow(confErr!),
                            ),
                            const SizedBox(height: 16),

                            // Actions
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 48,
                                    child: OutlinedButton(
                                      onPressed: saving
                                          ? null
                                          : () => Navigator.of(ctx).pop(),
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        side: const BorderSide(
                                          color: kAccent,
                                          width: 1.5,
                                        ),
                                        foregroundColor: kAccent,
                                      ),
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: SizedBox(
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: saving
                                          ? null
                                          : () async {
                                              // Clear previous errors
                                              setD(() {
                                                curErr = null;
                                                newErr = null;
                                                confErr = null;
                                                genErr = null;
                                              });

                                              final cur = _currentPwController
                                                  .text
                                                  .trim();
                                              final npw = _newPwController.text
                                                  .trim();
                                              final cnpw = _confirmPwController
                                                  .text
                                                  .trim();

                                              // Client-side validation
                                              if (cur.isEmpty) {
                                                curErr =
                                                    'Current password is required';
                                              }
                                              if (npw.isEmpty) {
                                                newErr =
                                                    'New password is required';
                                              }
                                              if (npw.isNotEmpty &&
                                                  npw.length < 6) {
                                                newErr =
                                                    'New password must be at least 6 characters';
                                              }
                                              if (cnpw.isEmpty) {
                                                confErr =
                                                    'Please confirm your new password';
                                              }
                                              if (npw.isNotEmpty &&
                                                  cnpw.isNotEmpty &&
                                                  npw != cnpw) {
                                                confErr =
                                                    'New passwords do not match';
                                              }
                                              if (curErr != null ||
                                                  newErr != null ||
                                                  confErr != null) {
                                                setD(() {});
                                                return;
                                              }

                                              setD(() => saving = true);
                                              try {
                                                final email = supabase
                                                    .auth
                                                    .currentUser
                                                    ?.email;
                                                if (email == null) {
                                                  throw const AuthException(
                                                    'No signed-in user.',
                                                  );
                                                }

                                                // Re-auth to verify current password
                                                await supabase.auth
                                                    .signInWithPassword(
                                                      email: email,
                                                      password: cur,
                                                    );

                                                // Update password
                                                await supabase.auth.updateUser(
                                                  UserAttributes(password: npw),
                                                );

                                                if (!mounted) return;
                                                Navigator.of(ctx).pop();
                                                _showTopPopup(
                                                  'Password updated successfully',
                                                  color: kAccent,
                                                  icon: Icons.check_circle,
                                                );
                                              } on SocketException {
                                                setD(() {
                                                  genErr =
                                                      'Please check your internet connection and try again.';
                                                  saving = false;
                                                });
                                              } on AuthException catch (e) {
                                                final msg = e.message
                                                    .toLowerCase();
                                                setD(() {
                                                  if (msg.contains(
                                                        'invalid login',
                                                      ) ||
                                                      msg.contains('invalid') ||
                                                      msg.contains(
                                                        'credentials',
                                                      )) {
                                                    curErr =
                                                        'Current password is incorrect';
                                                  } else {
                                                    genErr = e.message;
                                                  }
                                                  saving = false;
                                                });
                                              } catch (e) {
                                                setD(() {
                                                  genErr =
                                                      'Something went wrong. Please try again.';
                                                  saving = false;
                                                });
                                              }
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: kAccent,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: saving
                                          ? const SizedBox(
                                              height: 22,
                                              width: 22,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2.5,
                                              ),
                                            )
                                          : const Text(
                                              'Save new password',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
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
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _showLogoutConfirmDialog() {
    return showGeneralDialog<bool>(
      context: context,
      barrierLabel: 'Logout',
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, ___) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: kWarn.withOpacity(0.35)),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 18,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: kWarn.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.logout, color: kWarn),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'Log out?',
                                    style: TextStyle(
                                      color: kText,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'You will be logged out of your account on this device. You can sign in again anytime.',
                                    style: TextStyle(
                                      color: kSubText,
                                      fontSize: 16,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              icon: const Icon(Icons.close, color: kSubText),
                              tooltip: 'Close',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: OutlinedButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    side: const BorderSide(
                                      color: kAccent,
                                      width: 1.5,
                                    ),
                                    foregroundColor: kAccent,
                                  ),
                                  child: const Text(
                                    'Stay logged in',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kWarn,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Text(
                                    'Log out',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
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
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _chooseImageSource() async {
    if (_uploadingImage) return;
    final source = await showModalBottomSheet<_PickSource>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            const Text(
              'Profile Photo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, _PickSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, _PickSource.gallery),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );

    if (source == null) return;

    switch (source) {
      case _PickSource.camera:
        await _capturePhoto();
        break;
      case _PickSource.gallery:
        await _pickFromGallery();
        break;
    }
  }

  Future<void> _capturePhoto() async {
    if (_uploadingImage) return;
    // Request camera permission
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (!mounted) return;
      _showTopPopup(
        'Camera permission denied',
        color: kWarn,
        icon: Icons.error_outline,
      );
    }
    try {
      final xFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 70,
      );
      if (xFile == null) return;
      final bytes = await xFile.readAsBytes();
      await _cropAndConfirm(
        bytes,
        originalFileName: 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
    } catch (e) {
      if (!mounted) return;
      _showTopPopup(
        'Camera error: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    }
  }

  Future<void> _pickFromGallery() async {
    // ORIGINAL logic (moved from _pickAndCropImage)
    if (_uploadingImage) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null) return;
      final bytes = result.files.first.bytes;
      final name = result.files.first.name;
      if (bytes == null) throw Exception('No file bytes');

      await _cropAndConfirm(bytes, originalFileName: name);
    } catch (e) {
      if (!mounted) return;
      _showTopPopup(
        'Image selection failed: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    }
  }

  Future<void> _cropAndConfirm(
    Uint8List bytes, {
    required String originalFileName,
  }) async {
    // Save temp file
    final tempDir = await getTemporaryDirectory();
    final originalPath = '${tempDir.path}/$originalFileName';
    final f = File(originalPath);
    await f.writeAsBytes(bytes);

    final crop = await ImageCropper().cropImage(
      sourcePath: originalPath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 92,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Photo',
          toolbarColor: kPrimary,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: kAccent,
          hideBottomControls: false,
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: 'Crop Photo', aspectRatioLockEnabled: false),
      ],
    );
    if (crop == null) return;

    final croppedBytes = await File(crop.path).readAsBytes();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use this photo?'),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(croppedBytes, fit: BoxFit.cover, height: 220),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _uploadCroppedBytes(croppedBytes, extension: 'jpg');
    }
  }

  Future<void> _fetchUserProfile() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      setState(() => isLoading = false);
      return;
    }

    try {
      final response = await supabase
          .from('users')
          .select(
            'full_name, mobile_number, address, sex, profile_url, birth_certificate_url, marriage_certificate_url, valid_id, proof_of_residency_url',
          )
          .eq('id', currentUser.id)
          .maybeSingle();

      if (!mounted) return;
      if (response == null) {
        setState(() {
          fullName = '';
          mobileNumber = '';
          address = '';
          sex = '';
          profileUrl = null;
          birthCertificateUrl = null;
          marriageCertificateUrl = null;
          validIdUrl = null;
          proofOfResidencyUrl = null;
          isLoading = false;
        });
      } else {
        setState(() {
          fullName = (response['full_name'] as String?)?.trim() ?? '';
          mobileNumber = (response['mobile_number'] as String?)?.trim() ?? '';
          address = (response['address'] as String?)?.trim() ?? '';
          sex = (response['sex'] as String?)?.trim() ?? '';
          profileUrl = response['profile_url'] as String?;
          birthCertificateUrl = response['birth_certificate_url'] as String?;
          marriageCertificateUrl =
              response['marriage_certificate_url'] as String?;
          validIdUrl = response['valid_id'] as String?;
          proofOfResidencyUrl = response['proof_of_residency_url'] as String?;
          _fullNameController.text = fullName;
          _mobileController.text = mobileNumber;
          _addressController.text = address;
          _sexController.text = sex;
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showTopPopup(
        'Failed to load profile: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    }
  }

  String removeTitle(String name) {
    final titleRegex = RegExp(r'^(Mr\.|Mrs\.)\s', caseSensitive: false);
    return name.replaceAll(titleRegex, '').trim();
  }

  String _displayName() => removeTitle(fullName);

  String _initialOf(String? name) {
    final t = (name ?? '').trim();
    if (t.isEmpty) return 'M';
    return t.characters.first.toUpperCase();
  }

  void _showTopPopup(
    String message, {
    Color color = kAccent,
    IconData icon = Icons.check_circle,
  }) {
    final overlay = Overlay.of(context);

    late OverlayEntry entry;
    final animationController = AnimationController(
      vsync: Navigator.of(context),
      duration: const Duration(milliseconds: 350),
    );
    final curved = CurvedAnimation(
      parent: animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 24,
        right: 24,
        child: AnimatedBuilder(
          animation: curved,
          builder: (context, child) {
            return Opacity(
              opacity: curved.value,
              child: Transform.translate(
                offset: Offset(0, -40 * (1 - curved.value)),
                child: child,
              ),
            );
          },
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.38),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.18),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
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
    );

    overlay.insert(entry);
    animationController.forward();

    Future.delayed(const Duration(seconds: 5), () async {
      await animationController.reverse();
      entry.remove();
      animationController.dispose();
    });
  }

  Future<void> _uploadCroppedBytes(
    Uint8List bytes, {
    required String extension,
  }) async {
    setState(() => _uploadingImage = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      // 1. Delete previous profile image if it exists
      if (profileUrl != null && profileUrl!.isNotEmpty) {
        // Extract the file name from the URL
        final uri = Uri.parse(profileUrl!);
        final segments = uri.pathSegments;
        final fileName = segments.isNotEmpty ? segments.last : null;
        if (fileName != null && fileName.isNotEmpty) {
          await supabase.storage.from('avatars').remove([fileName]);
        }
      }

      // 2. Upload new image
      final fileName =
          '$userId-${DateTime.now().millisecondsSinceEpoch}.$extension';

      await supabase.storage
          .from('avatars')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);

      final update = await supabase
          .from('users')
          .update({'profile_url': publicUrl})
          .eq('id', userId)
          .select()
          .maybeSingle();

      if (update == null) {
        throw Exception('Update failed');
      }

      if (!mounted) return;
      setState(() {
        profileUrl = publicUrl;
        _uploadingImage = false;
      });
      ScaffoldMessenger.of(context);
      _showTopPopup('Profile photo updated');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      ScaffoldMessenger.of(context);
      _showTopPopup(
        'Upload error: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    }
  }

  void _openProfilePreview() {
    if (profileUrl == null || profileUrl!.isEmpty) return;
    showGeneralDialog(
      context: context,
      barrierLabel: 'Profile Photo',
      barrierDismissible: true,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, a1, a2, child) {
        final scale = Curves.easeOutCubic.transform(a1.value);
        return Opacity(
          opacity: a1.value,
          child: Transform.scale(
            scale: scale,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Stack(
                children: [
                  Center(
                    child: Hero(
                      tag: 'profilePhotoHero',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: InteractiveViewer(
                          clipBehavior: Clip.none,
                          minScale: 0.7,
                          maxScale: 4,
                          child: Image.network(
                            profileUrl!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 40,
                    right: 20,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 32,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 260),
    );
  }

  // Future<void> _uploadCertificate({required String type}) async {
  //   final result = await FilePicker.platform.pickFiles(
  //     type: FileType.custom,
  //     allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
  //     allowMultiple: false,
  //     withData: true,
  //   );
  //   if (result == null) return;

  //   final file = result.files.first;
  //   final bytes = file.bytes;
  //   final ext = file.extension ?? 'pdf';
  //   if (bytes == null) return;

  //   setState(() => _uploadingImage = true);
  //   try {
  //     final userId = supabase.auth.currentUser!.id;
  //     late String fileName;
  //     late String bucket;
  //     Map<String, dynamic> updateFields = {};

  //     if (type == 'birth') {
  //       fileName = '$userId-birth_certificate.${ext.toLowerCase()}';
  //       bucket = 'birth_certificates';
  //       updateFields = {'birth_certificate_url': supabase.storage.from(bucket).getPublicUrl(fileName)};
  //     } else if (type == 'marriage') {
  //       fileName = '$userId-marriage_certificate.${ext.toLowerCase()}';
  //       bucket = 'marriage_certificates';
  //       updateFields = {'marriage_certificate_url': supabase.storage.from(bucket).getPublicUrl(fileName)};
  //     } else if (type == 'valid') {
  //       fileName = '$userId-valid_id.${ext.toLowerCase()}';
  //       bucket = 'valid_ids';
  //       updateFields = {'valid_id': supabase.storage.from(bucket).getPublicUrl(fileName)};
  //     } else if (type == 'residency') {
  //       fileName = '$userId-proof_of_residency.${ext.toLowerCase()}';
  //       bucket = 'proof_of_residency';
  //       updateFields = {'proof_of_residency_url': supabase.storage.from(bucket).getPublicUrl(fileName)};
  //     } else {
  //       throw Exception('Unknown certificate type');
  //     }

  //     await supabase.storage
  //         .from(bucket)
  //         .uploadBinary(
  //           fileName,
  //           bytes,
  //           fileOptions: const FileOptions(upsert: true),
  //         );

  //     await supabase
  //         .from('users')
  //         .update(updateFields)
  //         .eq('id', userId)
  //         .select()
  //         .maybeSingle();

  //     if (!mounted) return;
  //     setState(() {
  //       if (type == 'birth') birthCertificateUrl = updateFields['birth_certificate_url'];
  //       if (type == 'marriage') marriageCertificateUrl = updateFields['marriage_certificate_url'];
  //       if (type == 'valid') validIdUrl = updateFields['valid_id'];
  //       if (type == 'residency') proofOfResidencyUrl = updateFields['proof_of_residency_url'];
  //       _uploadingImage = false;
  //     });
  //     _showTopPopup(
  //       '${type[0].toUpperCase()}${type.substring(1)} uploaded!',
  //       color: kAccent,
  //       icon: Icons.check_circle,
  //     );
  //   } catch (e) {
  //     if (!mounted) return;
  //     setState(() => _uploadingImage = false);
  //     _showTopPopup(
  //       'Upload error: $e',
  //       color: kWarn,
  //       icon: Icons.error_outline,
  //     );
  //   }
  // }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final userId = supabase.auth.currentUser!.id;
      final updated = {
        'full_name': _fullNameController.text.trim(),
        'mobile_number': _mobileController.text.trim(),
        'address': _addressController.text.trim(),
        'sex': _sexController.text.trim(),
        'profile_url': profileUrl,
      };

      final res = await supabase
          .from('users')
          .update(updated)
          .eq('id', userId)
          .select();

      if (!mounted) return;
      if (res.isEmpty) {
        _showTopPopup(
          'No profile found to update',
          color: kWarn,
          icon: Icons.error_outline,
        );
      } else {
        final row = res.first;
        setState(() {
          fullName = (row['full_name'] ?? '').toString();
          mobileNumber = (row['mobile_number'] ?? '').toString();
          address = (row['address'] ?? '').toString();
          sex = (row['sex'] ?? '').toString();
          profileUrl = (row['profile_url'] ?? profileUrl)?.toString();
          _editing = false;
        });
        _showTopPopup('Profile updated successfully');
      }
    } catch (e) {
      if (!mounted) return;
      _showTopPopup(
        'Error updating profile: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await _showLogoutConfirmDialog();
    if (ok == true) {
      await Supabase.instance.client.auth.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('selectedDayungUnit');
      await prefs.remove('selectedDayungUnitData');

      try {
        if (mounted) {
          context.read<DayungUnitProvider>().clear();
        }
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Login()),
        (route) => false,
      );
    }
  }

  Future<void> handleLogout(BuildContext context) async {
    setState(() => _loggingOut = true);
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selectedDayungUnit');
    await prefs.remove('selectedDayungUnitData');

    try {
      context.read<DayungUnitProvider>().clear();
    } catch (_) {}
    try {
      await context.read<DayungRoleProvider>().refreshRoles(null);
    } catch (_) {}

    if (!context.mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      setState(() => _loggingOut = false);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Login()),
        (route) => false,
      );
    });
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kSubText),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeBg = isDark ? const Color(0xFF18181B) : const Color(0xFFF8FAFC);
    final themeCard = isDark ? const Color(0xFF23232A) : Colors.white;
    final themeText = isDark ? Colors.white : const Color(0xFF111827);
    final themeSubText = isDark ? Colors.white : const Color(0xFF111827);
    final themeField = isDark ? const Color(0xFF23232A) : Colors.white;

    if (isLoading) {
      return Scaffold(
        backgroundColor: themeBg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: themeBg,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [
                    const Color(0xFF23232A),
                    const Color(0xFF18181B),
                    const Color(0xFF23232A),
                  ]
                : [
                    const Color(0xFF1E40AF),
                    const Color(0xFF3B82F6),
                    const Color(0xFFF8FAFC),
                  ],
            stops: [0.0, 0.3, 0.3],
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.chevron_left,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Profile',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFamily: 'Montserrat',
                        letterSpacing: 0.3,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            offset: Offset(0, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Theme.of(context).brightness == Brightness.dark
                          ? Icons.wb_sunny_rounded
                          : Icons.nightlight_round,
                      color: Colors.white,
                      size: 22,
                    ),
                    tooltip: Theme.of(context).brightness == Brightness.dark
                        ? 'Light mode'
                        : 'Dark mode',
                    onPressed: () => context.read<AppTheme>().toggle(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: themeBg,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Stack(
                  children: [
                    Form(
                      key: _formKey,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildModernProfileSection(
                              themeCard,
                              themeText,
                              themeSubText,
                            ),
                            const SizedBox(height: 32),

                            _buildProfileFields(
                              themeCard,
                              themeText,
                              themeSubText,
                              themeField,
                            ),
                            const SizedBox(height: 24),

                            _buildActionButtons(),
                            const SizedBox(height: 24),

                            // _buildCertificatesSection(themeCard, themeText),
                            // const SizedBox(height: 24),

                            // _buildDayungManagement(
                            //   themeCard,
                            //   themeText,
                            //   themeSubText,
                            // ),
                          ],
                        ),
                      ),
                    ),
                    if (_uploadingImage)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [kPrimary, kPrimaryLight],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: kPrimary.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Uploading photo...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernProfileSection(
    Color themeCard,
    Color themeText,
    Color themeSubText,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF44444A)
                  : const Color.fromARGB(255, 215, 215, 215),
              borderRadius: BorderRadius.circular(45),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: _buildProfileAvatar(themeCard),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName().isNotEmpty ? _displayName() : 'Your name',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: themeText,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  mobileNumber.isNotEmpty ? mobileNumber : 'Mobile not set',
                  style: TextStyle(
                    fontSize: 12,
                    color: themeSubText,
                    fontFamily: 'OpenSans',
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: _editing ? kWarn : kAccent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ElevatedButton.icon(
                    icon: Icon(
                      _editing ? Icons.close_rounded : Icons.edit_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    label: Text(
                      _editing ? 'Cancel' : 'Edit Profile',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      if (_editing) {
                        _fullNameController.text = fullName;
                        _mobileController.text = mobileNumber;
                        _addressController.text = address;
                        _sexController.text = sex;
                      }
                      setState(() => _editing = !_editing);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileAvatar(Color themeCard) {
    return GestureDetector(
      onTap: _editing ? _chooseImageSource : _openProfilePreview,
      child: Hero(
        tag: 'profilePhotoHero',
        child: CircleAvatar(
          radius: 40,
          backgroundColor: themeCard,
          backgroundImage: (profileUrl != null && profileUrl!.isNotEmpty)
              ? NetworkImage(profileUrl!)
              : null,
          child: (profileUrl == null || profileUrl!.isEmpty)
              ? Icon(Icons.person, color: kPrimary, size: 28)
              : null,
        ),
      ),
    );
  }

  Widget _buildProfileFields(
    Color themeCard,
    Color themeText,
    Color themeSubText,
    Color themeField,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Personal Information',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: themeText,
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 12),
        _buildSimpleField(
          icon: Icons.person_rounded,
          label: 'Full Name',
          value: _displayName(),
          editingChild: TextFormField(
            controller: _fullNameController,
            textCapitalization: TextCapitalization.words,
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Full name is required' : null,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: themeText,
            ),
            decoration: _fieldDecoration(
              'Enter full name',
            ).copyWith(filled: true, fillColor: themeField),
          ),
          themeCard: themeCard,
          themeText: themeText,
          themeSubText: themeSubText,
        ),
        _buildSimpleField(
          icon: Icons.location_on_rounded,
          label: 'Address',
          value: address.isNotEmpty ? address : 'Not provided',
          editingChild: TextFormField(
            controller: _addressController,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: themeText,
            ),
            decoration: _fieldDecoration(
              'Enter address',
            ).copyWith(filled: true, fillColor: themeField),
          ),
          themeCard: themeCard,
          themeText: themeText,
          themeSubText: themeSubText,
        ),
        _buildSimpleField(
          icon: Icons.phone_rounded,
          label: 'Mobile Number',
          value: mobileNumber.isNotEmpty ? mobileNumber : 'Not provided',
          editingChild: TextFormField(
            controller: _mobileController,
            keyboardType: TextInputType.phone,
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return 'Mobile number is required';
              if (t.length < 7) return 'Enter a valid number';
              return null;
            },
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: themeText,
            ),
            decoration: _fieldDecoration(
              'Enter mobile number',
            ).copyWith(filled: true, fillColor: themeField),
          ),
          themeCard: themeCard,
          themeText: themeText,
          themeSubText: themeSubText,
        ),
        _buildSimpleField(
          icon: Icons.person_outline_rounded,
          label: 'Sex',
          value: sex.isNotEmpty ? sex : 'Not provided',
          editingChild: DropdownButtonFormField2<String>(
            isExpanded: true,
            value: (_sexController.text.isNotEmpty
                ? _sexController.text
                : null),
            decoration: _fieldDecoration(
              'Select sex',
            ).copyWith(filled: true, fillColor: themeField),
            // Selected value (in the field) style
            style: TextStyle(
              color: themeText,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            // Dropdown list items (white), same as register/addbeneficiary
            items: const ['Male', 'Female', 'Prefer not to say']
                .map(
                  (s) => DropdownMenuItem<String>(
                    value: s,
                    child: Text(
                      s,
                      style: const TextStyle(
                        color: Colors.white, // list text
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
                .toList(),
            // Field shows icon + black text (like register.dart)
            selectedItemBuilder: (context) =>
                ['Male', 'Female', 'Prefer not to say']
                    .map(
                      (s) => Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (s == 'Male')
                              Icon(Icons.male, color: Colors.blue[700])
                            else if (s == 'Female')
                              Icon(Icons.female, color: Colors.pink[400])
                            else
                              const Icon(Icons.person_outline, color: kSubText),
                            const SizedBox(width: 8),
                            Text(
                              s,
                              style: TextStyle(
                                color: themeText, // field text
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
            onChanged: (val) => _sexController.text = val ?? '',
            validator: (_) => null,
          ),
          themeCard: themeCard,
          themeText: themeText,
          themeSubText: themeSubText,
        ),
      ],
    );
  }

  Widget _buildSimpleField({
    required IconData icon,
    required String label,
    required String value,
    required Widget editingChild,
    required Color themeCard,
    required Color themeText,
    required Color themeSubText,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: themeCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 16, color: kPrimary),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: themeText,
                  fontFamily: 'Montserrat',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _editing
              ? editingChild
              : Text(
                  value,
                  style: TextStyle(
                    color: themeSubText,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeButtonBeneficiary = isDark
        ? const Color(0xFF23232A)
        : Colors.white;
    final themeButtonChangePw = isDark ? const Color(0xFF23232A) : Colors.white;
    final themeButtonLogout = isDark ? const Color(0xFFB91C1C) : kWarn;
    final themeButtonPin = isDark ? const Color(0xFF23232A) : Colors.white;
    final textColor = isDark ? Colors.white : kText;

    if (_editing) {
      return Container(
        width: double.infinity,
        height: 44,
        decoration: BoxDecoration(
          color: themeButtonBeneficiary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ElevatedButton(
          onPressed: _saving ? null : _saveProfile,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
          child: _saving
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Save Changes',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontFamily: 'Montserrat',
                  ),
                ),
        ),
      );
    } else {
      return Consumer<DayungRoleProvider>(
        builder: (_, roles, __) {
          return Column(
            children: [
              if (roles.isPresident)
                _buildActionButton(
                  icon: Icons.rule_rounded,
                  label: 'User Preferences',
                  color: Colors.indigo,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ManageRulesPagePres(),
                      ),
                    );
                  },
                  textColor: Colors.white,
                ),
              const SizedBox(height: 8),
              if (roles.isPresident)
                _buildActionButton(
                  icon: Icons.assignment_turned_in_rounded,
                  label: 'RULES',
                  color: Colors.deepPurple,
                  onTap: () {
                    final user = Supabase.instance.client.auth.currentUser;
                    debugPrint(
                      'Required Applications button clicked by user: ${user?.id} (${user?.email})',
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RequiredApplicationsPage(),
                      ),
                    );
                  },
                  textColor: Colors.white,
                ),
              if (roles.isPresident) const SizedBox(height: 8),
              // _buildActionButton(
              //   icon: Icons.people_rounded,
              //   label: 'Beneficiaries',
              //   color: themeButtonBeneficiary,
              //   onTap: () {
              //     Navigator.push(
              //       context,
              //       MaterialPageRoute(builder: (_) => const BeneficiaryPage()),
              //     );
              //   },
              //   textColor: textColor,
              // ),
              const SizedBox(height: 10),
              // FutureBuilder<bool>(
              //   future: PinLock.hasPin(),
              //   builder: (context, snapshot) {
              //     final hasPin = snapshot.data ?? false;
              //     return Column(
              //       children: [
              //         _buildActionButton(
              //           icon: Icons.pin_rounded,
              //           label: hasPin ? 'Change App PIN' : 'Set up App PIN',
              //           color: themeButtonPin,
              //           onTap: () async {
              //             await _showPinModal(hasPin: hasPin);
              //           },
              //           textColor: textColor,
              //         ),
              //       ],
              //     );
              //   },
              // ),
              // const SizedBox(height: 8),
              _buildActionButton(
                icon: Icons.lock_reset_rounded,
                label: 'Change Password',
                color: themeButtonChangePw,
                onTap: _openChangePasswordDialog,
                textColor: textColor,
              ),
              const SizedBox(height: 8),
              // _buildActionButton(
              //   icon: Icons.logout_rounded,
              //   label: _loggingOut ? '' : 'Logout',
              //   color: themeButtonLogout,
              //   onTap: _loggingOut ? null : () => handleLogout(context),
              //   trailing: _loggingOut
              //       ? const SizedBox(
              //           width: 18,
              //           height: 18,
              //           child: CircularProgressIndicator(
              //             color: Colors.white,
              //             strokeWidth: 2.5,
              //           ),
              //         )
              //       : null,
              // ),
            ],
          );
        },
      );
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    Widget? trailing,
    Color textColor = Colors.white,
  }) {
    return Container(
      width: double.infinity,
      height: 44,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ElevatedButton.icon(
        icon: Icon(icon, color: textColor, size: 16),
        label: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
                fontFamily: 'Montserrat',
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing],
          ],
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        onPressed: onTap,
      ),
    );
  }

  // Widget _buildCertificatesSection(Color themeCard, Color themeText) {
  //   return Column(
  //     crossAxisAlignment: CrossAxisAlignment.start,
  //     children: [
  //       Text(
  //         'Certificates',
  //         style: TextStyle(
  //           fontSize: 14,
  //           fontWeight: FontWeight.w600,
  //           color: themeText,
  //           fontFamily: 'Montserrat',
  //         ),
  //       ),
  //       const SizedBox(height: 12),
  //       Container(
  //         padding: const EdgeInsets.all(16),
  //         decoration: BoxDecoration(
  //           color: themeCard,
  //           borderRadius: BorderRadius.circular(8),
  //         ),
  //         child: Column(
  //           children: [
  //             _certificateRow(
  //               label: 'Birth Certificate',
  //               url: birthCertificateUrl,
  //               onUpload: () => _uploadCertificate(type: 'birth'),
  //               onView: () => _openCertificate(birthCertificateUrl ?? ''),
  //               labelColor: themeText,
  //             ),
  //             const SizedBox(height: 8),
  //             _certificateRow(
  //               label: 'Marriage Certificate',
  //               url: marriageCertificateUrl,
  //               onUpload: () => _uploadCertificate(type: 'marriage'),
  //               onView: () => _openCertificate(marriageCertificateUrl ?? ''),
  //               labelColor: themeText,
  //             ),
  //             const SizedBox(height: 8),
  //             _certificateRow(
  //               label: 'Valid ID',
  //               url: validIdUrl,
  //               onUpload: () => _uploadCertificate(type: 'valid'),
  //               onView: () => _openCertificate(validIdUrl ?? ''),
  //               labelColor: themeText,
  //             ),
  //             const SizedBox(height: 8),
  //             _certificateRow(
  //               label: 'Proof of Residency',
  //               url: proofOfResidencyUrl,
  //               onUpload: () => _uploadCertificate(type: 'residency'),
  //               onView: () => _openCertificate(proofOfResidencyUrl ?? ''),
  //               labelColor: themeText,
  //             ),
  //           ],
  //         ),
  //       ),
  //     ],
  //   );
  // }

  //   Widget _buildDayungManagement(
  //     Color themeCard,
  //     Color themeText,
  //     Color themeSubText,
  //   ) {
  //     return Column(
  //       children: [
  //         Container(
  //           padding: const EdgeInsets.all(16),
  //           decoration: BoxDecoration(
  //             color: themeCard,
  //             borderRadius: BorderRadius.circular(8),
  //           ),

  //           child: InkWell(
  //             onTap: () {
  //               Navigator.push(
  //                 context,
  //                                MaterialPageRoute(builder: (_) => const DayungProfile()),
  //               );
  //             },
  //             borderRadius: BorderRadius.circular(8),
  //             child: Row(
  //               children: [
  //                 Container(
  //                   padding: const EdgeInsets.all(8),
  //                   decoration: BoxDecoration(
  //                     color: kPrimary.withOpacity(0.08),
  //                     borderRadius: BorderRadius.circular(6),
  //                   ),
  //                   child: const Icon(
  //                     Icons.home_rounded,
  //                     color: kPrimary,
  //                     size: 18,
  //                   ),
  //                 ),
  //                 const SizedBox(width: 12),
  //                 Expanded(
  //                   child: Column(
  //                     crossAxisAlignment: CrossAxisAlignment.start,
  //                     children: [
  //                       Text(
  //                         'Manage Dayung',
  //                         style: TextStyle(
  //                           fontSize: 14,
  //                           fontWeight: FontWeight.w600,
  //                           color: themeText,
  //                           fontFamily: 'Montserrat',
  //                         ),
  //                       ),
  //                       const SizedBox(height: 4),
  //                       Text(
  //                         'View current Dayung, apply or change',
  //                         style: TextStyle(
  //                           color: themeSubText,
  //                           fontSize: 12,
  //                           fontFamily: 'OpenSans',
  //                         ),
  //                       ),
  //                     ],
  //                   ),
  //                 ),
  //                 const Icon(
  //                   Icons.chevron_right_rounded,
  //                   color: kPrimary,
  //                   size: 18,
  //                 ),
  //               ],
  //             ),
  //           ),
  //         ),
  //       ],
  //     );
  //   }
  // }
}

enum _PickSource { camera, gallery }
