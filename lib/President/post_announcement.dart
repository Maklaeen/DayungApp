import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<void> _save() async {
    if (_unitId == null ||
        _title.text.trim().isEmpty ||
        _body.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Fill all fields')));
      return;
    }
    setState(() => _loading = true);
    try {
      await sb.from('announcements').insert({
        'dayung_unit_id': _unitId,
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'created_by': sb.auth.currentUser?.id,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Announcement posted')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      appBar: AppBar(title: const Text('Post Announcement')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButtonFormField<int>(
                    value: _unitId,
                    items: _units
                        .map(
                          (u) => DropdownMenuItem<int>(
                            value: int.tryParse('${u['id']}'),
                            child: Text(
                              (u['name'] ?? 'Unit').toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _unitId = v),
                    decoration: const InputDecoration(
                      labelText: 'Dayung Unit',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _body,
                    minLines: 5,
                    maxLines: null,
                    decoration: const InputDecoration(
                      labelText: 'Body',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.send),
                      label: const Text('Post'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
