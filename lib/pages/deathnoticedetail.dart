import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

class DeathNoticeDetail extends StatefulWidget {
  final String name;
  final String date;
  final String birthDate;
  final double? latitude;   // <-- Add these
  final double? longitude;

  const DeathNoticeDetail({
    Key? key,
    required this.name,
    required this.date,
    this.birthDate = 'Sept 21, 1958',
    this.latitude,
    this.longitude,
  }) : super(key: key);

  @override
  State<DeathNoticeDetail> createState() => _DeathNoticeDetailState();
}

class _DeathNoticeDetailState extends State<DeathNoticeDetail> {
  String? _locationName;
  bool _loadingLocation = true;

  @override
  void initState() {
    super.initState();
    _resolveLocation();
  }

  Future<void> _resolveLocation() async {
    if (widget.latitude == null || widget.longitude == null) {
      setState(() {
        _loadingLocation = false;
        _locationName = "Location unavailable";
      });
      return;
    }
    try {
      final placemarks = await placemarkFromCoordinates(
        widget.latitude!,
        widget.longitude!,
      ).timeout(const Duration(seconds: 10), onTimeout: () => []);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          if (p.street?.isNotEmpty == true) p.street!,
          if (p.locality?.isNotEmpty == true) p.locality!,
          if (p.administrativeArea?.isNotEmpty == true) p.administrativeArea!,
          if (p.country?.isNotEmpty == true) p.country!,
        ];
        setState(() {
          _locationName = parts.isNotEmpty
              ? parts.join(', ')
              : "Location unavailable";
          _loadingLocation = false;
        });
      } else {
        setState(() {
          _locationName = "Location unavailable";
          _loadingLocation = false;
        });
      }
    } catch (_) {
      setState(() {
        _locationName = "Location unavailable";
        _loadingLocation = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.of(context).textScaleFactor.clamp(1.0, 1.3);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        automaticallyImplyLeading: false,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Text(
          'Dayung',
          style: TextStyle(
            fontSize: 24 * scale,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: Icon(
                  Icons.notifications_none,
                  size: 36,
                  color: Colors.orange,
                ),
                onPressed: () {},
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  child: Text(
                    '1',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.blue,
              child: Icon(
                Icons.account_circle,
                size: 36 * scale,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ... existing UI ...
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => Navigator.pop(context),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back,
                          size: 28 * scale,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Image.asset(
                      'assets/images/headstone.png',
                      width: 36 * scale,
                      height: 36 * scale,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'In loving\nmemory of:',
                        style: TextStyle(
                          fontSize: 28 * scale,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ... name card, dates, etc ...
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 30,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        widget.name,
                        style: TextStyle(
                          fontSize: 34 * scale,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '${widget.birthDate} – ${widget.date}',
                        style: TextStyle(
                          fontSize: 20 * scale,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Aged 67 years',
                        style: TextStyle(
                          fontSize: 18 * scale,
                          fontWeight: FontWeight.w400,
                          color: Colors.black54,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Location of Vigil:',
                  style: TextStyle(
                    fontSize: 22 * scale,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 180,
                    width: double.infinity,
                    color: Colors.grey.shade200,
                    child: (widget.latitude == null || widget.longitude == null)
                        ? const Center(child: Text("Location unavailable"))
                        : Center(
                            child: Text(
                              'Lat: ${widget.latitude!.toStringAsFixed(4)}\n'
                              'Lng: ${widget.longitude!.toStringAsFixed(4)}',
                              style: TextStyle(
                                fontSize: 18 * scale,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                                height: 1.3,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
                ),
              ),
              if (_locationName != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _locationName!,
                    style: TextStyle(
                      fontSize: 18 * scale,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'With deepest respect and remembrance.',
                  style: TextStyle(
                    fontSize: 26 * scale,
                    fontStyle: FontStyle.italic,
                    fontFamily: 'DancingScript',
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}