import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DayungMapPage extends StatelessWidget {
  final Map<String, dynamic> dayung;
  final bool isApplied; // already applied to this dayung
  final bool isMember; // already a member of this dayung

  const DayungMapPage({
    super.key,
    required this.dayung,
    this.isApplied = false,
    this.isMember = false,
  });

  String _address(Map<String, dynamic> d) {
    final parts = <String>[
      if ((d['barangay'] ?? '').toString().isNotEmpty) d['barangay'],
      if ((d['city'] ?? '').toString().isNotEmpty) d['city'],
      if ((d['province'] ?? '').toString().isNotEmpty) d['province'],
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final lat = (dayung['latitude'] as num?)?.toDouble();
    final lng = (dayung['longitude'] as num?)?.toDouble();

    return Scaffold(
      appBar: AppBar(title: Text(dayung['name'] ?? 'Dayung Location')),
      body: (lat == null || lng == null)
          ? const Center(child: Text('No location data available.'))
          : Column(
              children: [
                SizedBox(
                  height: 320,
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(lat, lng),
                      zoom: 15,
                    ),
                    markers: {
                      Marker(
                        markerId: const MarkerId('dayung'),
                        position: LatLng(lat, lng),
                        infoWindow: InfoWindow(title: dayung['name']),
                      ),
                    },
                    myLocationEnabled: false,
                    zoomControlsEnabled: false,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dayung['name'] ?? '',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _address(dayung),
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const Spacer(),
                        if (isMember) ...[
                          Row(
                            children: const [
                              Icon(Icons.verified, color: Colors.green),
                              SizedBox(width: 8),
                              Text(
                                'This is your current Dayung',
                                style: TextStyle(color: Colors.green),
                              ),
                            ],
                          ),
                        ] else if (isApplied) ...[
                          Row(
                            children: const [
                              Icon(Icons.check_circle, color: Colors.blue),
                              SizedBox(width: 8),
                              Text(
                                'You have already applied to this Dayung',
                                style: TextStyle(color: Colors.blue),
                              ),
                            ],
                          ),
                        ] else ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => Navigator.pop(context, dayung),
                              icon: const Icon(Icons.how_to_reg),
                              label: const Text('Apply to this Dayung'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
