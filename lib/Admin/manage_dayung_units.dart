import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageDayungUnitsPage extends StatefulWidget {
  const ManageDayungUnitsPage({super.key});

  @override
  State<ManageDayungUnitsPage> createState() => _ManageDayungUnitsPageState();
}

class _ManageDayungUnitsPageState extends State<ManageDayungUnitsPage> {
  List<Map<String, dynamic>> units = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchUnits();
  }

  Future<void> _fetchUnits() async {
    setState(() => _loading = true);
    final data = await Supabase.instance.client
        .from('dayung_units')
        .select()
        .order('name', ascending: true);
    setState(() {
      units = List<Map<String, dynamic>>.from(data);
      _loading = false;
    });
  }

  Future<void> _deleteUnit(int id) async {
    await Supabase.instance.client.from('dayung_units').delete().eq('id', id);
    _fetchUnits();
  }

  Future<void> _showUnitDialog({Map<String, dynamic>? unit}) async {
    final nameController = TextEditingController(text: unit?['name'] ?? '');
    final barangayController = TextEditingController(
      text: unit?['barangay'] ?? '',
    );
    final cityController = TextEditingController(text: unit?['city'] ?? '');
    final provinceController = TextEditingController(
      text: unit?['province'] ?? '',
    );
    final latitudeController = TextEditingController(
      text: unit?['latitude']?.toString() ?? '',
    );
    final longitudeController = TextEditingController(
      text: unit?['longitude']?.toString() ?? '',
    );

    final isEdit = unit != null;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? 'Edit Dayung Unit' : 'Add Dayung Unit'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: barangayController,
                decoration: const InputDecoration(labelText: 'Barangay'),
              ),
              TextField(
                controller: cityController,
                decoration: const InputDecoration(labelText: 'City'),
              ),
              TextField(
                controller: provinceController,
                decoration: const InputDecoration(labelText: 'Province'),
              ),
              TextField(
                controller: latitudeController,
                decoration: const InputDecoration(labelText: 'Latitude'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: longitudeController,
                decoration: const InputDecoration(labelText: 'Longitude'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final barangay = barangayController.text.trim();
              final city = cityController.text.trim();
              final province = provinceController.text.trim();
              final latitude = double.tryParse(latitudeController.text.trim());
              final longitude = double.tryParse(
                longitudeController.text.trim(),
              );

              if (name.isEmpty || barangay.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Name and Barangay are required'),
                  ),
                );
                return;
              }

              final values = {
                'name': name,
                'barangay': barangay,
                'city': city.isEmpty ? null : city,
                'province': province.isEmpty ? null : province,
                'latitude': latitude,
                'longitude': longitude,
              };

              if (isEdit) {
                await Supabase.instance.client
                    .from('dayung_units')
                    .update(values)
                    .eq('id', unit!['id']);
              } else {
                await Supabase.instance.client
                    .from('dayung_units')
                    .insert(values);
              }
              if (mounted) Navigator.pop(context);
              _fetchUnits();
            },
            child: Text(isEdit ? 'Update' : 'Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Dayung Units'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Dayung Unit',
            onPressed: () => _showUnitDialog(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: units.length,
              itemBuilder: (context, i) {
                final unit = units[i];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    title: Text(unit['name'] ?? ''),
                    subtitle: Text(
                      '${unit['barangay'] ?? ''}'
                      '${unit['city'] != null ? ', ${unit['city']}' : ''}'
                      '${unit['province'] != null ? ', ${unit['province']}' : ''}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showUnitDialog(unit: unit),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Dayung Unit'),
                                content: Text(
                                  'Are you sure you want to delete "${unit['name']}"?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              _deleteUnit(unit['id']);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
