import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/utils/input_safety.dart';

List<Map<String, dynamic>> buildAnnouncementNotificationRows({
  required int announcementId,
  required int dayungUnitId,
  required String title,
  required String body,
  required String? senderId,
  required Iterable<String> recipientIds,
}) {
  final createdAt = DateTime.now().toIso8601String();
  return recipientIds
      .where((recipientId) => recipientId.trim().isNotEmpty)
      .map(
        (recipientId) => {
          'announcement_id': announcementId,
          'recipient_id': recipientId,
          'type': 'announcement',
          'title': title,
          'body': body,
          'dayung_unit_id': dayungUnitId,
          'sender_id': senderId,
          'created_at': createdAt,
          'read_at': null,
        },
      )
      .toList();
}

// Additional colors for post announcement specific styling
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimaryLight = Color(0xFF3B82F6);
const kAccentDark = Color(0xFF059669);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);

const _announcementCategories = [
  'General Announcement',
  'Contribution Reminder',
  'Death Notice / Death Assistance',
  'Meeting Schedule',
  'Payment Deadline',
  'Important Update',
  'Emergency Notice',
];

class PostAnnouncementPage extends StatefulWidget {
  const PostAnnouncementPage({super.key});

  @override
  State<PostAnnouncementPage> createState() => _PostAnnouncementPageState();
}

class _PostAnnouncementPageState extends State<PostAnnouncementPage> {
  final sb = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _units = [];
  int? _unitId;
  String? _category;

  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  Future<void> _loadUnits() async {
    setState(() => _loading = true);
    try {
      final uid = sb.auth.currentUser?.id;
      final res = await sb
          .from('dayung_units')
          .select('id,name')
          .eq('president_id', uid as Object)
          .order('name');
      _units = List<Map<String, dynamic>>.from(res);
      if (_units.isNotEmpty) {
        _unitId = int.tryParse('${_units.first['id']}');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasAuthorizedUnit {
    return _unitId != null &&
        _units.any((unit) => int.tryParse('${unit['id']}') == _unitId);
  }

  Future<void> _save() async {
    final title = AppInputSecurity.sanitizePlainText(
      _title.text,
      maxLength: 120,
    );
    final body = AppInputSecurity.sanitizePlainText(
      _body.text,
      allowNewLines: true,
      maxLength: 1000,
    );

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final category = _category;
    if (!_hasAuthorizedUnit || category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You are not authorized to post announcements for this unit.',
          ),
        ),
      );
      return;
    }

    if (AppInputSecurity.validateSafeText(
              title,
              fieldName: 'Title',
              minLength: 4,
              maxLength: 120,
            ) !=
            null ||
        AppInputSecurity.validateSafeText(
              body,
              fieldName: 'Body',
              minLength: 8,
              maxLength: 1000,
              allowNewLines: true,
            ) !=
            null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please review the announcement details and try again.',
          ),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final insertedAnnouncement = await sb
          .from('announcements')
          .insert({
            'dayung_unit_id': _unitId,
            'title': title,
            'body': body,
            'category': category,
            'created_by': sb.auth.currentUser?.id,
          })
          .select('id')
          .single();

      final announcementId = (insertedAnnouncement['id'] as int?) ?? 0;
      final recipientResponse = await sb
          .from('applications')
          .select('user_id')
          .eq('dayung_unit_id', _unitId!)
          .eq('status', 'approved');

      final recipientIds = <String>{
        for (final row in List<Map<String, dynamic>>.from(recipientResponse))
          if (row['user_id'] != null) row['user_id'].toString(),
      }.toList();

      if (recipientIds.isNotEmpty) {
        final notificationRows = buildAnnouncementNotificationRows(
          announcementId: announcementId,
          dayungUnitId: _unitId!,
          title: title,
          body: body,
          senderId: sb.auth.currentUser?.id,
          recipientIds: recipientIds,
        );

        if (notificationRows.isNotEmpty) {
          debugPrint(
            '[Announcement] inserting ${notificationRows.length} notification rows. First row: ${notificationRows.first}',
          );
          try {
            await sb.from('notifications').insert(notificationRows);
            debugPrint(
              '[Announcement] notifications insert SUCCESS: ${notificationRows.length} rows',
            );

            try {
              debugPrint('[Announcement] calling notify-announcement');

              final notifyResponse = await sb.functions.invoke(
                'notify-announcement',
                body: {'notifications': notificationRows},
              );

              debugPrint(
                '[Announcement] push function invoke SUCCESS: $notifyResponse',
              );
            } catch (e, st) {
              debugPrint('[Announcement] push function invoke FAILED: $e');
              debugPrintStack(stackTrace: st);
            }
          } catch (e, st) {
            debugPrint('[Announcement] notifications insert FAILED: $e');
            debugPrintStack(stackTrace: st);
            rethrow;
          }
        }
      }

      if (!mounted) return;
      await _showAnnouncementPostedDialog(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to post announcement. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showAnnouncementPostedDialog(BuildContext context) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: kSuccess.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(16),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: kSuccess,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Announcement Posted!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: kSuccess,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your announcement has been successfully posted.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: kText,
                  fontFamily: 'OpenSans',
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop(); // Go back to previous page
                  },
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String helpText,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: kPrimary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: kText,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      helpText,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: kSubText,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({required String hintText}) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      hintText: hintText,
      hintStyle: const TextStyle(
        color: kSubText,
        fontSize: 16,
        fontFamily: 'OpenSans',
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBorderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPrimary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kDanger, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kDanger, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 20, 18),
                decoration: BoxDecoration(
                  color: kPrimary,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimary.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      child: IconButton(
                        tooltip: 'Back',
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Post Announcement',
                            style: TextStyle(
                              fontSize: 22,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              fontFamily: 'Montserrat',
                            ),
                          ),
                          // SizedBox(height: 4),
                          // Text(
                          //   'Share an update with your members',
                          //   style: TextStyle(
                          //     fontSize: 14,
                          //     color: Colors.white,
                          //     fontFamily: 'OpenSans',
                          //   ),
                          // ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: kPrimary,
                          strokeWidth: 3,
                        ),
                      )
                    : _units.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.lock_outline_rounded,
                                size: 52,
                                color: kAccentDark,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'You are not authorized to post announcements.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: kText,
                                  fontFamily: 'OpenSans',
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Only the president assigned to a dayung unit can send announcements.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.45,
                                  color: kSubText,
                                  fontFamily: 'OpenSans',
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        child: SingleChildScrollView(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionCard(
                                  icon: Icons.title_rounded,
                                  title: 'Title',
                                  helpText:
                                      'Give your announcement a clear title.',
                                  child: TextFormField(
                                    controller: _title,
                                    inputFormatters:
                                        AppInputSecurity.singleLineFormatters(
                                          maxLength: 120,
                                        ),
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      color: kText,
                                      fontFamily: 'OpenSans',
                                    ),
                                    decoration: _fieldDecoration(
                                      hintText: 'Example: Monthly meeting',
                                    ),
                                    validator: (value) {
                                      final text = value?.trim() ?? '';
                                      if (text.isEmpty) {
                                        return 'Please enter a title.';
                                      }
                                      if (text.length < 4) {
                                        return 'Title must be at least 4 characters.';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _sectionCard(
                                  icon: Icons.category_rounded,
                                  title: 'Category',
                                  helpText:
                                      'Choose the type that best describes this post.',
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _category,
                                    isExpanded: true,
                                    decoration: _fieldDecoration(
                                      hintText: 'Choose a category',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: kText,
                                      fontFamily: 'OpenSans',
                                    ),
                                    items: _announcementCategories
                                        .map(
                                          (category) =>
                                              DropdownMenuItem<String>(
                                                value: category,
                                                child: Text(
                                                  category,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                        )
                                        .toList(),
                                    onChanged: (value) =>
                                        setState(() => _category = value),
                                    validator: (value) => value == null
                                        ? 'Please choose a category.'
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _sectionCard(
                                  icon: Icons.groups_rounded,
                                  title: 'Audience',
                                  helpText:
                                      'All approved members in the selected Dayung Unit will be notified.',
                                  child: DropdownButtonFormField<int>(
                                    initialValue: _unitId,
                                    isExpanded: true,
                                    items: _units
                                        .map(
                                          (unit) => DropdownMenuItem<int>(
                                            value: int.tryParse(
                                              '${unit['id']}',
                                            ),
                                            child: Text(
                                              (unit['name'] ?? 'Dayung Unit')
                                                  .toString(),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) =>
                                        setState(() => _unitId = value),
                                    decoration: _fieldDecoration(
                                      hintText: 'Choose a Dayung Unit',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: kText,
                                      fontFamily: 'OpenSans',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _sectionCard(
                                  icon: Icons.calendar_today_rounded,
                                  title: 'Date',
                                  helpText:
                                      'The post date is set automatically.',
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 17,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F6FA),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: kBorderColor),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.event_available_rounded,
                                          color: kPrimary,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          MaterialLocalizations.of(
                                            context,
                                          ).formatMediumDate(DateTime.now()),
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                            color: kText,
                                            fontFamily: 'OpenSans',
                                          ),
                                        ),
                                        // const Spacer(),
                                        // const Text(
                                        //   'Automatic',
                                        //   style: TextStyle(
                                        //     fontSize: 13,
                                        //     fontWeight: FontWeight.w600,
                                        //     color: kSubText,
                                        //     fontFamily: 'OpenSans',
                                        //   ),
                                        // ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _sectionCard(
                                  icon: Icons.description_rounded,
                                  title: 'Message',
                                  helpText:
                                      'Include the details members need to know.',
                                  child: TextFormField(
                                    controller: _body,
                                    inputFormatters:
                                        AppInputSecurity.multiLineFormatters(
                                          maxLength: 1000,
                                        ),
                                    minLines: 5,
                                    maxLines: null,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      height: 1.45,
                                      color: kText,
                                      fontFamily: 'OpenSans',
                                    ),
                                    decoration: _fieldDecoration(
                                      hintText:
                                          'Write your announcement here...',
                                    ),
                                    validator: (value) {
                                      final text = value?.trim() ?? '';
                                      if (text.isEmpty) {
                                        return 'Please enter the announcement details.';
                                      }
                                      if (text.length < 8) {
                                        return 'Message must be at least 8 characters.';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _save,
                                    icon: const Icon(
                                      Icons.send_rounded,
                                      size: 22,
                                    ),
                                    label: const Text(
                                      'Post Announcement',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 18,
                                        fontFamily: 'Montserrat',
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(58),
                                      backgroundColor: kPrimary,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
