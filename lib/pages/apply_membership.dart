import 'dart:typed_data';

import 'package:capstone_app/Beneficiary/beneficiary.dart';
import 'package:capstone_app/Members/dashboard.dart';
import 'package:capstone_app/profile/required_application_page.dart';
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
     final rows = await _supabase
         .from('required_applications')
         .select('title, description')
         .eq('dayung_unit_id', widget.dayungUnitId)
         .order('id');
     final content = RequiredApplicationContent.fromRows(
       rows.map((row) => Map<String, dynamic>.from(row)).toList(),
     );
     if (!mounted) return;
     setState(() {
       _agreementTitle = content.mainTitle;
       _agreementSections = content.sections;
       _loading = false;
     });
   } catch (_) {
     if (mounted) setState(() => _loading = false);
   }
 }

 Future<void> _openBeneficiaries() async {
   await Navigator.push(
     context,
     MaterialPageRoute(builder: (_) => const BeneficiaryPage()),
   );
   if (mounted) setState(() {});
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
     if (mounted)
       ScaffoldMessenger.of(
         context,
       ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
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

 Future<void> _confirmApplication() async {
   if (_birthCertificate == null || _validId == null) {
     ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(
         content: Text('Upload your birth certificate and valid ID first.'),
       ),
     );
     return;
   }
   if (!await _hasBeneficiary()) {
     ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content: Text('Add at least one beneficiary first.')),
     );
     return;
   }
   final userId = _supabase.auth.currentUser?.id;
   if (userId == null) return;
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
             'is_agree': true,
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
     }
     if (!mounted) return;
     Navigator.pushAndRemoveUntil(
       context,
       MaterialPageRoute(builder: (_) => const MemberDashboardPage()),
       (_) => false,
     );
   } catch (e) {
     if (mounted)
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Could not submit application: $e')),
       );
   } finally {
     if (mounted) setState(() => _saving = false);
   }
 }

 void _next() {
   if (_step == 0 && !_agreed) {
     ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(
         content: Text('Please agree to the Membership Agreement.'),
       ),
     );
     return;
   }
   if (_step < 3) setState(() => _step++);
 }

 @override
 Widget build(BuildContext context) {
   const titles = ['Agreement', 'Beneficiary', 'Certificates', 'Confirm'];
   return Scaffold(
     appBar: AppBar(title: Text('Apply to ${widget.dayungName}')),
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
       return _stepCard(
         'Membership Agreement',
         Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             if (_agreementTitle?.isNotEmpty == true)
               Text(
                 _agreementTitle!,
                 style: const TextStyle(
                   fontWeight: FontWeight.w800,
                   fontSize: 18,
                 ),
               ),
             for (final section in _agreementSections) ...[
               const SizedBox(height: 12),
               Text(
                 section.title,
                 style: const TextStyle(fontWeight: FontWeight.w700),
               ),
               const SizedBox(height: 4),
               Text(section.description),
             ],
             const SizedBox(height: 18),
             CheckboxListTile(
               contentPadding: EdgeInsets.zero,
               value: _agreed,
               onChanged: (value) => setState(() => _agreed = value ?? false),
               title: const Text('I agree to the Membership Agreement.'),
             ),
           ],
         ),
       );
     case 1:
       return _stepCard(
         'Add Beneficiary',
         Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             const Text(
               'Add at least one beneficiary before submitting your membership application.',
             ),
             const SizedBox(height: 18),
             FilledButton.icon(
               onPressed: _openBeneficiaries,
               icon: const Icon(Icons.person_add_alt_1),
               label: const Text('Open Beneficiaries'),
             ),
           ],
         ),
       );
     case 2:
       return _stepCard(
         'Upload Certificates',
         Column(
           children: [
             _uploadTile(
               'Birth certificate',
               _birthCertificate,
               () => _uploadDocument(type: 'birth'),
             ),
             const SizedBox(height: 12),
             _uploadTile(
               'Valid ID',
               _validId,
               () => _uploadDocument(type: 'valid'),
             ),
           ],
         ),
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
               onPressed: _saving ? null : _confirmApplication,
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

