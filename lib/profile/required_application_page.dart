import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/utils/input_safety.dart';

// Color palette
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);
const kSuccess = Color(0xFF059669);

class RequiredApplicationSection {
  final String title;
  final String description;

  const RequiredApplicationSection({
    required this.title,
    required this.description,
  });
}

class RequiredApplicationContent {
  final String mainTitle;
  final List<RequiredApplicationSection> sections;
  final int? dayungUnitId;

  const RequiredApplicationContent({
    required this.mainTitle,
    required this.sections,
    this.dayungUnitId,
  });

  factory RequiredApplicationContent.empty() {
    return const RequiredApplicationContent(mainTitle: '', sections: []);
  }

  factory RequiredApplicationContent.fromRows(List<Map<String, dynamic>> rows) {
    var mainTitle = '';
    final sections = <RequiredApplicationSection>[];
    int? dayungUnitId;

    for (final row in rows) {
      final title = (row['title'] ?? '').toString().trim();
      final description = (row['description'] ?? '').toString().trim();
      final parsedUnitId = _parseDayungUnitId(row['dayung_unit_id']);

      if (parsedUnitId != null && dayungUnitId == null) {
        dayungUnitId = parsedUnitId;
      }

      if (title.isEmpty && description.isEmpty) {
        continue;
      }

      if (mainTitle.isEmpty && description.isEmpty && title.isNotEmpty) {
        mainTitle = title;
      } else {
        sections.add(
          RequiredApplicationSection(title: title, description: description),
        );
      }
    }

    return RequiredApplicationContent(
      mainTitle: mainTitle,
      sections: sections,
      dayungUnitId: dayungUnitId,
    );
  }

  static int? _parseDayungUnitId(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  List<Map<String, dynamic>> toRows({
    required String userId,
    int? dayungUnitId,
  }) {
    final rows = <Map<String, dynamic>>[];
    final resolvedUnitId = dayungUnitId ?? this.dayungUnitId;
    if (mainTitle.trim().isNotEmpty) {
      rows.add({
        'title': mainTitle.trim(),
        'description': '',
        'user_id': userId,
        'dayung_unit_id': resolvedUnitId,
      });
    }

    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      final title = section.title.trim();
      final description = section.description.trim();
      if (title.isEmpty && description.isEmpty) {
        continue;
      }
      final normalizedTitle = (i == 0 && title.isEmpty) ? 'NO TITLE' : title;
      rows.add({
        'title': normalizedTitle,
        'description': description,
        'user_id': userId,
        'dayung_unit_id': resolvedUnitId,
      });
    }

    return rows;
  }

  RequiredApplicationContent copyWith({
    String? mainTitle,
    List<RequiredApplicationSection>? sections,
    int? dayungUnitId,
  }) {
    return RequiredApplicationContent(
      mainTitle: mainTitle ?? this.mainTitle,
      sections: sections ?? this.sections,
      dayungUnitId: dayungUnitId ?? this.dayungUnitId,
    );
  }

  bool get isEmpty {
    return mainTitle.trim().isEmpty &&
        sections.every(
          (section) =>
              section.title.trim().isEmpty &&
              section.description.trim().isEmpty,
        );
  }
}

class RequiredApplicationsPage extends StatefulWidget {
  const RequiredApplicationsPage({super.key});

  static bool shouldShowAgreementNotice({required bool hasApplicationRecord}) {
    return hasApplicationRecord;
  }

  @override
  State<RequiredApplicationsPage> createState() =>
      _RequiredApplicationsPageState();
}

class _RequiredApplicationsPageState extends State<RequiredApplicationsPage> {
  final TextEditingController _mainTitleController = TextEditingController();
  final List<TextEditingController> _titleControllers = [];
  final List<TextEditingController> _descControllers = [];
  RequiredApplicationContent _content = RequiredApplicationContent.empty();
  bool _loading = false;
  bool _fetching = false;
  bool _editing = false;
  bool _agreedToTerms = false;
  bool _hasApplicationRecord = false;

  @override
  void initState() {
    super.initState();
    _populateForm();
    _fetchApplication();
  }

  @override
  void dispose() {
    _mainTitleController.dispose();
    for (final controller in [..._titleControllers, ..._descControllers]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _populateForm({RequiredApplicationContent? content}) {
    final targetContent = content ?? _content;
    _mainTitleController.text = targetContent.mainTitle;

    for (final controller in [..._titleControllers, ..._descControllers]) {
      controller.dispose();
    }
    _titleControllers.clear();
    _descControllers.clear();

    if (targetContent.sections.isEmpty) {
      _titleControllers.add(TextEditingController());
      _descControllers.add(TextEditingController());
      return;
    }

    for (final section in targetContent.sections) {
      _titleControllers.add(TextEditingController(text: section.title));
      _descControllers.add(TextEditingController(text: section.description));
    }
  }

  Future<int?> _resolveDayungUnitId(String userId) async {
    if (_content.dayungUnitId != null) {
      return _content.dayungUnitId;
    }

    try {
      final unitRows = await Supabase.instance.client
          .from('dayung_units')
          .select('id')
          .eq('president_id', userId)
          .limit(1);
      if (unitRows.isNotEmpty) {
        final unitRow = Map<String, dynamic>.from(unitRows.first as Map);
        final parsedId = RequiredApplicationContent._parseDayungUnitId(
          unitRow['id'],
        );
        if (parsedId != null) return parsedId;
      }
    } catch (_) {}

    try {
      final applicationRows = await Supabase.instance.client
          .from('applications')
          .select('dayung_unit_id')
          .eq('user_id', userId)
          .limit(1);
      if (applicationRows.isNotEmpty) {
        final applicationRow = Map<String, dynamic>.from(
          applicationRows.first as Map,
        );
        return RequiredApplicationContent._parseDayungUnitId(
          applicationRow['dayung_unit_id'],
        );
      }
    } catch (_) {}

    return null;
  }

  Future<void> _fetchApplication() async {
    setState(() => _fetching = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final applicationRows = await Supabase.instance.client
          .from('applications')
          .select('id')
          .eq('user_id', userId)
          .limit(1);
      final hasApplicationRecord = applicationRows.isNotEmpty;

      final dayungUnitId = await _resolveDayungUnitId(userId);
      var request = Supabase.instance.client
          .from('required_applications')
          .select('title, description, dayung_unit_id');

      if (dayungUnitId != null) {
        request = request.eq('dayung_unit_id', dayungUnitId);
      } else {
        request = request.eq('user_id', userId);
      }

      final rows = await request.order('id', ascending: true);
      if (!mounted) return;
      final parsedRows = rows
          .whereType<Map<String, dynamic>>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      setState(() {
        _content = RequiredApplicationContent.fromRows(
          parsedRows,
        ).copyWith(dayungUnitId: dayungUnitId);
        _hasApplicationRecord = hasApplicationRecord;
        _editing = false;
        _populateForm(content: _content);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  RequiredApplicationContent _buildContentFromForm() {
    final sections = <RequiredApplicationSection>[];
    for (var i = 0; i < _titleControllers.length; i++) {
      final title = AppInputSecurity.sanitizePlainText(
        _titleControllers[i].text,
        maxLength: 120,
      );
      final description = AppInputSecurity.sanitizePlainText(
        _descControllers[i].text,
        allowNewLines: true,
        maxLength: 2000,
      );
      sections.add(
        RequiredApplicationSection(title: title, description: description),
      );
    }

    return RequiredApplicationContent(
      mainTitle: AppInputSecurity.sanitizePlainText(
        _mainTitleController.text,
        maxLength: 120,
      ),
      sections: sections,
      dayungUnitId: _content.dayungUnitId,
    );
  }

  Future<void> _addOrUpdateApplication() async {
    final content = _buildContentFromForm();
    final titleValidation = AppInputSecurity.validateSafeText(
      content.mainTitle,
      fieldName: 'Main title',
      minLength: 2,
      maxLength: 120,
    );

    if (titleValidation != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(titleValidation)));
      return;
    }

    for (var i = 0; i < content.sections.length; i++) {
      final section = content.sections[i];
      final titleError = i == 0
          ? null
          : AppInputSecurity.validateSafeText(
              section.title,
              fieldName: 'Section title ${i + 1}',
              minLength: 2,
              maxLength: 120,
            );
      final descriptionError = AppInputSecurity.validateSafeText(
        section.description,
        fieldName: 'Section description ${i + 1}',
        minLength: 8,
        maxLength: 2000,
        allowNewLines: true,
      );

      if (titleError != null || descriptionError != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              titleError ?? descriptionError ?? 'Please complete this section.',
            ),
          ),
        );
        return;
      }
    }

    setState(() => _loading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      var dayungUnitId = content.dayungUnitId;
      dayungUnitId ??= await _resolveDayungUnitId(userId);

      if (dayungUnitId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to determine the Dayung unit. Please set your unit or contact support.',
            ),
          ),
        );
        return;
      }

      final contentWithUnit = content.copyWith(dayungUnitId: dayungUnitId);
      final rows = contentWithUnit.toRows(
        userId: userId,
        dayungUnitId: dayungUnitId,
      );
      await Supabase.instance.client
          .from('required_applications')
          .delete()
          .eq('user_id', userId);

      if (rows.isNotEmpty) {
        await Supabase.instance.client
            .from('required_applications')
            .insert(rows);
      }

      if (!mounted) return;
      setState(() {
        _content = contentWithUnit;
        _editing = false;
        _populateForm(content: _content);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startEdit() {
    setState(() {
      _editing = true;
      _populateForm(content: _content);
    });
  }

  void _addSection() {
    setState(() {
      _titleControllers.add(TextEditingController());
      _descControllers.add(TextEditingController());
    });
  }

  void _removeSection(int index) {
    if (_titleControllers.length <= 1) return;
    setState(() {
      _titleControllers[index].dispose();
      _descControllers[index].dispose();
      _titleControllers.removeAt(index);
      _descControllers.removeAt(index);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _populateForm(content: _content);
    });
  }

  void _toggleAgreement() {
    setState(() {
      _agreedToTerms = !_agreedToTerms;
    });

    if (_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thank you! You agreed to the terms and rules.'),
        ),
      );
    }
  }

  Widget _buildAgreementNotice() {
    final agreed = _agreedToTerms;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            border: Border.all(
              color: agreed ? const Color(0xFF2E7D32) : const Color(0xFF81C784),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final agreeButton = FilledButton.icon(
                onPressed: _toggleAgreement,
                icon: Icon(
                  agreed ? Icons.check_rounded : Icons.verified_user_outlined,
                  size: 18,
                ),
                label: Text(agreed ? 'Agreed' : 'I Agree'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              );
              final message = Text(
                'Agree to these rules to continue to membership payment.',
                style: const TextStyle(
                  color: Color(0xFF1B5E20),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.35,
                ),
              );

              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [message, const SizedBox(height: 10), agreeButton],
                );
              }

              return Row(
                children: [
                  Icon(
                    agreed
                        ? Icons.verified_user_rounded
                        : Icons.shield_outlined,
                    color: const Color(0xFF2E7D32),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: message),
                  const SizedBox(width: 12),
                  agreeButton,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSectionEditor(int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Box ${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kAccent,
                  ),
                ),
              ),
              if (_titleControllers.length > 1)
                IconButton(
                  onPressed: () => _removeSection(index),
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.redAccent,
                  splashRadius: 20,
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _titleControllers[index],
            inputFormatters: AppInputSecurity.singleLineFormatters(
              maxLength: 120,
            ),
            decoration: InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descControllers[index],
            inputFormatters: AppInputSecurity.multiLineFormatters(
              maxLength: 2000,
            ),
            decoration: InputDecoration(
              labelText: 'Description',
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            minLines: 4,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(RequiredApplicationSection section, int index) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5EAF0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: kAccent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title.isEmpty
                      ? 'Section ${index + 1}'
                      : section.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kAccent,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  section.description,
                  style: const TextStyle(
                    color: kSubText,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              decoration: const BoxDecoration(
                color: kAccent,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: kAccent,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Required Application',
                      style: TextStyle(
                        fontSize: 20,
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
            Expanded(
              child: _fetching && !_editing && _content.isEmpty
                  ? const DayungPageSkeleton(
                      layout: DayungSkeletonLayout.detail,
                      padding: EdgeInsets.fromLTRB(16, 20, 16, 24),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1100),
                              child: Card(
                                elevation: 4,
                                color: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                margin: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _editing || _content.isEmpty
                                            ? 'Application rules'
                                            : 'Your application',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 24,
                                          color: kAccent,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      if (_editing || _content.isEmpty)
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            TextField(
                                              controller: _mainTitleController,
                                              inputFormatters:
                                                  AppInputSecurity.singleLineFormatters(
                                                    maxLength: 120,
                                                  ),
                                              decoration: InputDecoration(
                                                labelText: 'Dayung Name',
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                filled: true,
                                                fillColor: kBg,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            const Text(
                                              'Application sections',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: kText,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            for (
                                              var i = 0;
                                              i < _titleControllers.length;
                                              i++
                                            )
                                              _buildSectionEditor(i),
                                            const SizedBox(height: 8),
                                            TextButton.icon(
                                              onPressed: _addSection,
                                              icon: const Icon(Icons.add),
                                              label: const Text(
                                                'Add a section',
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                _loading
                                                    ? const CircularProgressIndicator()
                                                    : ElevatedButton.icon(
                                                        icon: const Icon(
                                                          Icons.save,
                                                        ),
                                                        label: Text(
                                                          _content.isEmpty
                                                              ? 'Save'
                                                              : 'Update',
                                                        ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              kSuccess,
                                                          foregroundColor:
                                                              Colors.white,
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  10,
                                                                ),
                                                          ),
                                                        ),
                                                        onPressed:
                                                            _addOrUpdateApplication,
                                                      ),
                                                if (_editing &&
                                                    !_content.isEmpty)
                                                  TextButton(
                                                    onPressed: _cancelEdit,
                                                    child: const Text('Cancel'),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        )
                                      else
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _content.mainTitle,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 24,
                                                color: kText,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            for (
                                              var index = 0;
                                              index < _content.sections.length;
                                              index++
                                            )
                                              _buildSectionCard(
                                                _content.sections[index],
                                                index,
                                              ),
                                            ElevatedButton.icon(
                                              icon: const Icon(Icons.edit),
                                              label: const Text('Edit'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: kAccent,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                              ),
                                              onPressed: _startEdit,
                                            ),
                                          ],
                                        ),
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
            if (!_editing &&
                !_content.isEmpty &&
                RequiredApplicationsPage.shouldShowAgreementNotice(
                  hasApplicationRecord: _hasApplicationRecord,
                ))
              _buildAgreementNotice(),
          ],
        ),
      ),
    );
  }
}
