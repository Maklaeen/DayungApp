import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

    for (final section in sections) {
      final title = section.title.trim();
      final description = section.description.trim();
      if (title.isEmpty && description.isEmpty) {
        continue;
      }
      rows.add({
        'title': title,
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
    setState(() => _loading = true);
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
      if (mounted) setState(() => _loading = false);
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
        maxLength: 500,
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
      final titleError = AppInputSecurity.validateSafeText(
        section.title,
        fieldName: 'Section title ${i + 1}',
        minLength: 2,
        maxLength: 120,
      );
      final descriptionError = AppInputSecurity.validateSafeText(
        section.description,
        fieldName: 'Section description ${i + 1}',
        minLength: 8,
        maxLength: 500,
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
      if (dayungUnitId == null) {
        dayungUnitId = await _resolveDayungUnitId(userId);
      }

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
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8, bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          border: Border.all(color: const Color(0xFF2E7D32), width: 1.2),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: agreed
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFF4CAF50),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Click if you agree to the terms and rules so you can pay the membership fee.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFF1B5E20),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: _toggleAgreement,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: agreed
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFF4CAF50),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  agreed ? 'Agreed ✓' : 'I Agree',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
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
              maxLength: 500,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 36, 20, 28),
              decoration: const BoxDecoration(
                color: kAccent,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: kAccent,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 16),
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
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    Card(
                      elevation: 4,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _editing || _content.isEmpty
                                  ? 'Add your required application'
                                  : 'Your application',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 28,
                                color: kAccent,
                                fontFamily: 'Montserrat',
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (_editing || _content.isEmpty)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: kBg,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Boxes',
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
                                    label: const Text('Add another box'),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      _loading
                                          ? const CircularProgressIndicator()
                                          : ElevatedButton.icon(
                                              icon: const Icon(Icons.save),
                                              label: Text(
                                                _content.isEmpty
                                                    ? 'Save'
                                                    : 'Update',
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: kSuccess,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                              ),
                                              onPressed:
                                                  _addOrUpdateApplication,
                                            ),
                                      if (_editing && !_content.isEmpty)
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                  for (final section in _content.sections)
                                    Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: kBg,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            section.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: kAccent,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            section.description,
                                            style: const TextStyle(
                                              color: kSubText,
                                              fontSize: 15,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(height: 12),
                                  if (RequiredApplicationsPage.shouldShowAgreementNotice(
                                    hasApplicationRecord: _hasApplicationRecord,
                                  ))
                                    _buildAgreementNotice(),
                                  const SizedBox(height: 4),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.edit),
                                    label: const Text('Edit'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kAccent,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
