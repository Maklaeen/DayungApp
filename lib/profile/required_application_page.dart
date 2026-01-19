import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Color palette
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);
const kSuccess = Color(0xFF059669);

class RequiredApplicationsPage extends StatefulWidget {
  const RequiredApplicationsPage({super.key});

  @override
  State<RequiredApplicationsPage> createState() =>
      _RequiredApplicationsPageState();
}

class _RequiredApplicationsPageState extends State<RequiredApplicationsPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  Map<String, dynamic>? _application;
  bool _loading = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _fetchApplication();
  }

  Future<void> _fetchApplication() async {
    setState(() => _loading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final data = await Supabase.instance.client
          .from('required_applications')
          .select('id, title, description')
          .eq('user_id', userId)
          .maybeSingle();
      setState(() {
        _application = data;
        if (_application != null) {
          _titleController.text = _application?['title'] ?? '';
          _descController.text = _application?['description'] ?? '';
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _addOrUpdateApplication() async {
    final title = _titleController.text.trim();
    final description = _descController.text.trim();
    if (title.isEmpty || description.isEmpty) return;

    setState(() => _loading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      if (_application == null) {
        // Add new
        final inserted = await Supabase.instance.client
            .from('required_applications')
            .insert({
              'title': title,
              'description': description,
              'user_id': userId,
            })
            .select()
            .single();
        setState(() {
          _application = inserted;
        });
      } else {
        // Update existing
        final id = _application!['id'];
        await Supabase.instance.client
            .from('required_applications')
            .update({'title': title, 'description': description})
            .eq('id', id);
        setState(() {
          _application = {
            ..._application!,
            'title': title,
            'description': description,
          };
        });
      }
      _editing = false;
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  void _startEdit() {
    setState(() {
      _editing = true;
      _titleController.text = _application?['title'] ?? '';
      _descController.text = _application?['description'] ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Curved Header
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
            // Make the rest scrollable
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    // Application Form Card
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
                              _application == null
                                  ? 'Add your required application'
                                  : _editing
                                      ? 'Update your application'
                                      : 'Your application',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 30,
                                color: kAccent,
                                fontFamily: 'Montserrat',
                              ),
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _titleController,
                              enabled: _application == null || _editing,
                              decoration: InputDecoration(
                                labelText: 'Title',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: kBg,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _descController,
                              enabled: _application == null || _editing,
                              decoration: InputDecoration(
                                labelText: 'Description',
                                alignLabelWithHint: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: kBg,
                              ),
                              minLines: 5,
                              maxLines: 10,
                              keyboardType: TextInputType.multiline,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                _loading
                                    ? const CircularProgressIndicator()
                                    : (_application == null || _editing)
                                        ? ElevatedButton.icon(
                                            icon: Icon(
                                              _application == null
                                                  ? Icons.send
                                                  : Icons.save,
                                            ),
                                            label: Text(
                                              _application == null
                                                  ? 'Add'
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
                                            onPressed: _addOrUpdateApplication,
                                          )
                                        : ElevatedButton.icon(
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
                                if (_editing)
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _editing = false;
                                        _titleController.text =
                                            _application?['title'] ?? '';
                                        _descController.text =
                                            _application?['description'] ?? '';
                                      });
                                    },
                                    child: const Text('Cancel'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Application Display Card
                    if (_application != null && !_editing)
                      Card(
                        elevation: 2,
                        color: kBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _application?['title'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 30,
                                  color: kText,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Make description scrollable if too long
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final desc = _application?['description'] ?? '';
                                  if (desc.length > 1000) {
                                    return SizedBox(
                                      height: 200,
                                      child: Scrollbar(
                                        child: SingleChildScrollView(
                                          child: Text(
                                            desc,
                                            style: const TextStyle(
                                              color: kSubText,
                                              fontSize: 25,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  } else {
                                    return Text(
                                      desc,
                                      style: const TextStyle(
                                        color: kSubText,
                                        fontSize: 20,
                                      ),
                                    );
                                  }
                                },
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
  }}