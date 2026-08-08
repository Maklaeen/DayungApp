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
const double kEdge = 16;

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

    if (!_hasAuthorizedUnit ||
        AppInputSecurity.validateSafeText(
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
            'You are not authorized to post announcements for this unit, or the announcement data is invalid.',
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
                'Your announcement has been successfully posted and push notifications will be sent.',
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
              // Custom App Bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: kPrimary,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimary.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_rounded,
                        size: 24,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Back',
                    ),
                    Expanded(
                      child: Text(
                        'Post Announcement',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontFamily: 'Montserrat',
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Content
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
                                  fontSize: 16,
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
                                  fontSize: 14,
                                  color: kSubText,
                                  fontFamily: 'OpenSans',
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(20),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Dayung Unit Dropdown
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: kCardBg,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: kBorderColor.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.05,
                                      ),
                                      blurRadius: 15,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: kPrimary.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.location_on_rounded,
                                            color: kPrimary,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Dayung Unit',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            color: kText,
                                            fontFamily: 'Montserrat',
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    DropdownButtonFormField<int>(
                                      initialValue: _unitId,
                                      items: _units
                                          .map(
                                            (u) => DropdownMenuItem<int>(
                                              value: int.tryParse('${u['id']}'),
                                              child: Text(
                                                (u['name'] ?? 'Unit')
                                                    .toString(),
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontFamily: 'OpenSans',
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) =>
                                          setState(() => _unitId = v),
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: kCardBg,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: kBorderColor,
                                            width: 1,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: kBorderColor,
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: kPrimary,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Title Field
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: kCardBg,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: kBorderColor.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.05,
                                      ),
                                      blurRadius: 15,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: kPrimary.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.title_rounded,
                                            color: kPrimary,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Title',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            color: kText,
                                            fontFamily: 'Montserrat',
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _title,
                                      inputFormatters:
                                          AppInputSecurity.singleLineFormatters(
                                            maxLength: 120,
                                          ),
                                      style: const TextStyle(
                                        fontFamily: 'OpenSans',
                                        fontWeight: FontWeight.w600,
                                      ),
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: kCardBg,
                                        hintText: 'Enter announcement title...',
                                        hintStyle: TextStyle(
                                          color: kSubText,
                                          fontFamily: 'OpenSans',
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: kBorderColor,
                                            width: 1,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: kBorderColor,
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: kPrimary,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Body Field
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: kCardBg,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: kBorderColor.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.05,
                                      ),
                                      blurRadius: 15,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: kPrimary.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.description_rounded,
                                            color: kPrimary,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Body',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            color: kText,
                                            fontFamily: 'Montserrat',
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _body,
                                      inputFormatters:
                                          AppInputSecurity.multiLineFormatters(
                                            maxLength: 1000,
                                          ),
                                      minLines: 5,
                                      maxLines: null,
                                      style: const TextStyle(
                                        fontFamily: 'OpenSans',
                                        fontWeight: FontWeight.w600,
                                      ),
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: kCardBg,
                                        hintText:
                                            'Enter announcement details...',
                                        hintStyle: TextStyle(
                                          color: kSubText,
                                          fontFamily: 'OpenSans',
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: kBorderColor,
                                            width: 1,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: kBorderColor,
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: kPrimary,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Post Button
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _save,
                                  icon: const Icon(
                                    Icons.send_rounded,
                                    size: 20,
                                  ),
                                  label: const Text(
                                    'Post',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      fontFamily: 'Montserrat',
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kPrimary,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 18,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    shadowColor: kPrimary.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
