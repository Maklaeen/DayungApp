import 'package:capstone_app/SuperAdmin/superadmin_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';

class SuperAdminOrganizationPage extends StatefulWidget {
  const SuperAdminOrganizationPage({super.key});

  @override
  State<SuperAdminOrganizationPage> createState() =>
      _SuperAdminOrganizationPageState();
}

class _SuperAdminOrganizationPageState
    extends State<SuperAdminOrganizationPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _barangayController = TextEditingController();
  final _cityController = TextEditingController();
  final _provinceController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _unitSearchController = TextEditingController();

  bool _saving = false;
  String _unitSearchQuery = '';
  int _unitPage = 0;
  late Future<List<Map<String, dynamic>>> _unitsFuture;

  @override
  void initState() {
    super.initState();
    _unitsFuture = _loadUnits();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _barangayController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _unitSearchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadUnits() async {
    final response = await Supabase.instance.client
        .from('dayung_units')
        .select('id, name, barangay, city, province, latitude, longitude')
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> _saveOrganization() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('dayung_units').insert({
        'name': _nameController.text.trim(),
        'barangay': _barangayController.text.trim(),
        'city': _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        'province': _provinceController.text.trim().isEmpty
            ? null
            : _provinceController.text.trim(),
        'latitude': double.parse(_latitudeController.text.trim()),
        'longitude': double.parse(_longitudeController.text.trim()),
      });

      if (!mounted) return;
      _nameController.clear();
      _barangayController.clear();
      _cityController.clear();
      _provinceController.clear();
      _latitudeController.clear();
      _longitudeController.clear();
      setState(() => _unitsFuture = _loadUnits());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dayung organization saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SuperAdminAccessGuard(
      title: 'Dayung Organization',
      child: Scaffold(
        backgroundColor: superAdminBackground(context),
        appBar: AppBar(title: const Text('Dayung Organization')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OrganizationForm(
                      formKey: _formKey,
                      nameController: _nameController,
                      barangayController: _barangayController,
                      cityController: _cityController,
                      provinceController: _provinceController,
                      latitudeController: _latitudeController,
                      longitudeController: _longitudeController,
                      saving: _saving,
                      onSave: _saveOrganization,
                      onPickCoordinates: _pickCoordinates,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Saved Dayung Units',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: kSuperAdminText,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _unitSearchController,
                      onChanged: (value) => setState(() {
                        _unitSearchQuery = value.trim().toLowerCase();
                        _unitPage = 0;
                      }),
                      decoration: InputDecoration(
                        hintText: 'Search by name, location, or coordinates',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _unitSearchQuery.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () => _unitSearchController.clear(),
                                icon: const Icon(Icons.clear_rounded),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _unitsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        if (snapshot.hasError) {
                          return _UnitMessage(
                            message: snapshot.error.toString(),
                          );
                        }
                        final units = (snapshot.data ?? []).where((unit) {
                          if (_unitSearchQuery.isEmpty) return true;
                          final searchableText = [
                            unit['name'],
                            unit['barangay'],
                            unit['city'],
                            unit['province'],
                            unit['latitude'],
                            unit['longitude'],
                          ].whereType<Object>().join(' ').toLowerCase();
                          return searchableText.contains(_unitSearchQuery);
                        }).toList();
                        if (units.isEmpty) {
                          return _UnitMessage(
                            message: _unitSearchQuery.isEmpty
                                ? 'No Dayung units have been added yet.'
                                : 'No Dayung units match your search.',
                          );
                        }
                        final pageCount = (units.length / 10).ceil();
                        final start = _unitPage * 10;
                        final pageUnits = units.sublist(
                          start,
                          (start + 10).clamp(0, units.length),
                        );
                        return Column(
                          children: [
                            ...pageUnits.map((unit) {
                              final location =
                                  [
                                        unit['barangay'],
                                        unit['city'],
                                        unit['province'],
                                      ]
                                      .where((value) {
                                        return value != null &&
                                            value.toString().trim().isNotEmpty;
                                      })
                                      .join(', ');
                              final coordinates =
                                  '${unit['latitude'] ?? '-'}, ${unit['longitude'] ?? '-'}';
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.account_balance_rounded,
                                    color: kSuperAdminPrimary,
                                  ),
                                  title: Text(
                                    unit['name']?.toString() ?? 'Unnamed unit',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${location.isEmpty ? 'Location not set' : location}\nCoordinates: $coordinates',
                                  ),
                                  onTap: () => _showUnitApplications(
                                    (unit['id'] ?? '').toString(),
                                  ),
                                ),
                              );
                            }),
                            if (pageCount > 1) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _unitPage == 0
                                        ? null
                                        : () => setState(() => _unitPage--),
                                    icon: const Icon(
                                      Icons.chevron_left_rounded,
                                    ),
                                    label: const Text('Previous'),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Text(
                                      'Page ${_unitPage + 1} of $pageCount',
                                      style: const TextStyle(
                                        color: kSuperAdminMuted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _unitPage >= pageCount - 1
                                        ? null
                                        : () => setState(() => _unitPage++),
                                    icon: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                    label: const Text('Next'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickCoordinates() async {
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    final result = await showDialog<ll.LatLng>(
      context: context,
      builder: (_) => _CoordinatePickerDialog(
        initialPosition: latitude != null && longitude != null
            ? ll.LatLng(latitude, longitude)
            : null,
      ),
    );
    if (!mounted || result == null) return;
    _latitudeController.text = result.latitude.toStringAsFixed(6);
    _longitudeController.text = result.longitude.toStringAsFixed(6);
  }

  Future<void> _showUnitApplications(String dayungUnitId) async {
    if (dayungUnitId.isEmpty) return;
    final sb = Supabase.instance.client;
    try {
      final response = await sb
          .from('applications')
          .select('id, user_id, status, user:users(id, full_name, email)')
          .eq('dayung_unit_id', dayungUnitId)
          .order('applied_at', ascending: true);

      final apps = List<Map<String, dynamic>>.from(response);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return _ApplicationListDialog(applications: apps);
        },
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _OrganizationForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController barangayController;
  final TextEditingController cityController;
  final TextEditingController provinceController;
  final TextEditingController latitudeController;
  final TextEditingController longitudeController;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onPickCoordinates;

  const _OrganizationForm({
    required this.formKey,
    required this.nameController,
    required this.barangayController,
    required this.cityController,
    required this.provinceController,
    required this.latitudeController,
    required this.longitudeController,
    required this.saving,
    required this.onSave,
    required this.onPickCoordinates,
  });

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return 'This field is required';
    return null;
  }

  String? _latitude(String? value) {
    final number = double.tryParse(value?.trim() ?? '');
    if (number == null || number < -90 || number > 90) {
      return 'Enter a latitude from -90 to 90';
    }
    return null;
  }

  String? _longitude(String? value) {
    final number = double.tryParse(value?.trim() ?? '');
    if (number == null || number < -180 || number > 180) {
      return 'Enter a longitude from -180 to 180';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Dayung Organization',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: kSuperAdminText,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enter the organization name and its barangay. City and province are optional.',
                style: TextStyle(color: kSuperAdminMuted, height: 1.4),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                validator: _required,
                decoration: const InputDecoration(
                  labelText: 'Dayung name',
                  hintText: 'Spring Valley Dayung',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: barangayController,
                textCapitalization: TextCapitalization.words,
                validator: _required,
                decoration: const InputDecoration(
                  labelText: 'Barangay',
                  hintText: 'Buhangin',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: cityController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'City'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: provinceController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Province'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Coordinates',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: kSuperAdminText,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter them manually or choose the organization point on the map.',
                style: TextStyle(color: kSuperAdminMuted),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: latitudeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      validator: _latitude,
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        hintText: '7.0731',
                        prefixIcon: Icon(Icons.north),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: longitudeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      validator: _longitude,
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        hintText: '125.6128',
                        prefixIcon: Icon(Icons.east),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onPickCoordinates,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Choose on Map / Use My Location'),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: saving ? null : onSave,
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(saving ? 'Saving...' : 'Save Organization'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoordinatePickerDialog extends StatefulWidget {
  final ll.LatLng? initialPosition;

  const _CoordinatePickerDialog({this.initialPosition});

  @override
  State<_CoordinatePickerDialog> createState() =>
      _CoordinatePickerDialogState();
}

class _CoordinatePickerDialogState extends State<_CoordinatePickerDialog> {
  static const _defaultPosition = ll.LatLng(12.8797, 121.7740);
  final _mapController = MapController();
  late ll.LatLng _selected;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialPosition ?? _defaultPosition;
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied.');
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Location services are turned off.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final selected = ll.LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _selected = selected);
      _mapController.move(selected, 17);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose Organization Location'),
      content: SizedBox(
        width: 700,
        height: 430,
        child: Column(
          children: [
            Expanded(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _selected,
                  initialZoom: 15,
                  onTap: (_, point) => setState(() => _selected = point),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'capstone_app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _selected,
                        width: 48,
                        height: 48,
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: Colors.redAccent,
                          size: 42,
                        ),
                      ),
                    ],
                  ),
                  const RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution('OpenStreetMap contributors'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Selected: ${_selected.latitude.toStringAsFixed(6)}, ${_selected.longitude.toStringAsFixed(6)}',
                style: const TextStyle(color: kSuperAdminMuted),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _locating ? null : _useMyLocation,
                  icon: _locating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded),
                  label: Text(_locating ? 'Locating...' : 'Use My Location'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('Use This Point'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplicationListDialog extends StatefulWidget {
  final List<Map<String, dynamic>> applications;

  const _ApplicationListDialog({required this.applications});

  @override
  State<_ApplicationListDialog> createState() => _ApplicationListDialogState();
}

class _ApplicationListDialogState extends State<_ApplicationListDialog> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  late List<Map<String, dynamic>> _applications;
  bool _approving = false;

  @override
  void initState() {
    super.initState();
    _applications = List.from(widget.applications);
  }

  List<Map<String, dynamic>> get _filteredApplications {
    if (_searchQuery.isEmpty) return _applications;
    return _applications.where((app) {
      final user = app['user'] as Map<String, dynamic>?;
      final userId = (app['user_id'] ?? user?['id'])?.toString() ?? '';
      final name = user?['full_name']?.toString() ?? '';
      final email = user?['email']?.toString() ?? '';
      final status = app['status']?.toString() ?? '';
      final searchableText = [
        userId,
        name,
        email,
        status,
      ].where((value) => value.isNotEmpty).join(' ').toLowerCase();
      return searchableText.contains(_searchQuery);
    }).toList();
  }

  String _formatApprovedAt(DateTime value) {
    return value
        .toUtc()
        .toIso8601String()
        .replaceFirst('T', ' ')
        .replaceFirst('Z', '+00');
  }

  Future<void> _confirmApprove(
    String userId,
    String applicationId,
    int index,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm approval'),
          content: const Text(
            'Are you sure you want to approve this application? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Approve'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _approveApplication(userId, applicationId, index);
    }
  }

  Future<void> _approveApplication(
    String userId,
    String applicationId,
    int index,
  ) async {
    setState(() => _approving = true);
    try {
      if (applicationId.isEmpty) {
        throw Exception('Application ID is missing.');
      }

      final applicationIdValue = int.tryParse(applicationId);
      if (applicationIdValue == null) {
        throw Exception('Invalid application ID.');
      }

      final approverId = Supabase.instance.client.auth.currentUser?.id;
      if (approverId == null || approverId.isEmpty) {
        throw Exception('Unable to identify the approving user.');
      }

      final approvedAt = _formatApprovedAt(DateTime.now());
      await Supabase.instance.client.rpc(
        'approve_application',
        params: {
          'p_application_id': applicationIdValue,
          'p_approved_by': approverId,
        },
      );

      if (!mounted) return;
      setState(() {
        _applications[index]['status'] = 'approved';
        _applications[index]['is_agree'] = true;
        _applications[index]['approved_at'] = approvedAt;
        _applications[index]['approved_by'] = approverId;
        _approving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _approving = false);
      final message = error is PostgrestException
          ? 'Approve failed: ${error.message}'
          : error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _statusBadge(String status) {
    final normalized = status.toLowerCase();
    final color = normalized == 'approved'
        ? Colors.green
        : normalized == 'pending'
        ? Colors.orange
        : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final apps = _filteredApplications;
    return AlertDialog(
      title: const Text('Unit Applications'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() {
                _searchQuery = value.trim().toLowerCase();
              }),
              decoration: InputDecoration(
                hintText: 'Search by user name, email or status',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () => setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        }),
                        icon: const Icon(Icons.clear_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            if (apps.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No applications match your search.'),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(_applications.length, (index) {
                      if (!_filteredApplications.contains(
                        _applications[index],
                      )) {
                        return const SizedBox.shrink();
                      }
                      final app = _applications[index];
                      final user = app['user'] as Map<String, dynamic>?;
                      final applicationId = app['id']?.toString() ?? '';
                      final userId =
                          (app['user_id'] ?? user?['id'])?.toString() ?? '';
                      final name = user?['full_name']?.toString() ?? '';
                      final email = user?['email']?.toString() ?? '';
                      final status = app['status']?.toString() ?? 'unknown';
                      final isPending = status.toLowerCase() == 'pending';
                      return ListTile(
                        title: Text(name.isNotEmpty ? name : 'Application'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [if (email.isNotEmpty) Text(email)],
                        ),
                        trailing: isPending
                            ? OutlinedButton.icon(
                                onPressed: _approving
                                    ? null
                                    : () => _confirmApprove(
                                        userId,
                                        applicationId,
                                        index,
                                      ),
                                icon: _approving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.check_rounded),
                                label: const Text('Approve'),
                              )
                            : _statusBadge(status),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _UnitMessage extends StatelessWidget {
  final String message;

  const _UnitMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(message, style: const TextStyle(color: kSuperAdminMuted)),
      ),
    );
  }
}
