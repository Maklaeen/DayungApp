import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RequiredApplicationsPage extends StatefulWidget {
  const RequiredApplicationsPage({super.key});

  @override
  State<RequiredApplicationsPage> createState() => _RequiredApplicationsPageState();
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
      debugPrint('Fetching required applications for user_id: $userId'); // <-- Add this line
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load: $e')),
      );
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
            .update({
              'title': title,
              'description': description,
            })
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
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
      appBar: AppBar(
        title: const Text(''),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
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
            const SizedBox(height: 8),
            Row(
              children: [
                _loading
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        icon: Icon(_editingIndex == null ? Icons.send : Icons.edit),
                        label: Text(_editingIndex == null ? 'Add' : 'Update'),
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
            const SizedBox(height: 24),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _applications.isEmpty
                      ? const Center(child: Text('No applications added yet.'))
                      : ListView.builder(
                          itemCount: _applications.length,
                          itemBuilder: (context, index) => ListTile(
                            title: Text(_applications[index]['title'] ?? ''),
                            subtitle: Text(_applications[index]['description'] ?? ''),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _startEdit(index),
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