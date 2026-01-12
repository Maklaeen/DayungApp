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
  final List<Map<String, dynamic>> _applications = [];
  bool _loading = false;
  int? _editingIndex;

  @override
  void initState() {
    super.initState();
    _fetchApplications();
  }

  Future<void> _fetchApplications() async {
    setState(() => _loading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final data = await Supabase.instance.client
          .from('required_applications')
          .select('id, title, description')
          .eq('user_id', userId)
          .order('id', ascending: false);
      setState(() {
        _applications.clear();
        _applications.addAll(List<Map<String, dynamic>>.from(data));
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

      if (_editingIndex == null) {
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
          _applications.insert(0, inserted);
        });
      } else {
        // Edit existing
        final app = _applications[_editingIndex!];
        final id = app['id'];
        await Supabase.instance.client
            .from('required_applications')
            .update({'title': title, 'description': description})
            .eq('id', id);
        setState(() {
          _applications[_editingIndex!] = {
            ...app,
            'title': title,
            'description': description,
          };
        });
      }
      _titleController.clear();
      _descController.clear();
      _editingIndex = null;
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  void _startEdit(int index) {
    setState(() {
      _editingIndex = index;
      _titleController.text = _applications[index]['title'] ?? '';
      _descController.text = _applications[index]['description'] ?? '';
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
                      'Required Applications',
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
            // Application Form Card
            Card(
              elevation: 3,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _descController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                      minLines: 6,
                      maxLines: 12,
                      keyboardType: TextInputType.multiline,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _loading
                            ? const CircularProgressIndicator()
                            : ElevatedButton.icon(
                                icon: Icon(
                                  _editingIndex == null
                                      ? Icons.send
                                      : Icons.edit,
                                ),
                                label: Text(
                                  _editingIndex == null ? 'Add' : 'Update',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kSuccess,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: _addOrUpdateApplication,
                              ),
                        if (_editingIndex != null)
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _editingIndex = null;
                                _titleController.clear();
                                _descController.clear();
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
            const SizedBox(height: 24),
            // Applications List Card
            Expanded(
              child: Card(
                elevation: 3,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _applications.isEmpty
                      ? const Center(child: Text('No applications added yet.'))
                      : ListView.builder(
                          itemCount: _applications.length,
                          itemBuilder: (context, index) => Card(
                            elevation: 1,
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            margin: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 2,
                            ),
                            child: ListTile(
                              title: Text(
                                _applications[index]['title'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: kText,
                                ),
                              ),
                              subtitle: Text(
                                _applications[index]['description'] ?? '',
                                style: const TextStyle(color: kSubText),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit, color: kAccent),
                                onPressed: () => _startEdit(index),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
