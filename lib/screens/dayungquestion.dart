// ignore_for_file: non_constant_identifier_names

import 'dart:math';

import 'package:capstone_app/Members/dashboard.dart';
import 'package:capstone_app/screens/dayung_map_page.dart';
import 'package:capstone_app/screens/dayung_suggestions.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

const Color kPrimary = Color(0xFF3B82F6);
const Color kPrimaryDark = Color(0xFF1E40AF);
const Color kAccent = Color(0xFF10B981);
const Color kWarn = Color(0xFFF59E0B);
const Color kDanger = Color(0xFFEF4444);
const Color kBg = Color(0xFFF8FAFC);
const Color kCardBg = Color(0xFFFFFFFF);
const Color kSubText = Color(0xFF6B7280);
const Color kText = Color(0xFF111827);

class QuestionnaireScreen extends StatefulWidget {
  final String userId;
  final String role;

  const QuestionnaireScreen({
    super.key,
    required this.userId,
    required this.role,
  });

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  final _formKey = GlobalKey<FormState>();

  String? contribution_amount;
  String? membership_payment;
  String? penalty_payment;
  String? payment_method;
  String? openForAll;
  String? organizational_model;
  String? participation_method;
  String? meeting_frequency;
  String? penalty_policy;
  List<dynamic> suggestedUnits = [];
  bool isLoading = false;
  bool isSubmitting = false;

  String _digits(String? s) => (s ?? '').replaceAll(RegExp(r'[^\d]'), '');
  String _trimLower(String? s) => (s ?? '').trim().toLowerCase();

  Future<void> applyToDayungUnit(String userId, int dayungUnitId) async {
    await Supabase.instance.client.from('applications').insert({
      'user_id': userId,
      'dayung_unit_id': dayungUnitId,
      'status': 'pending',
    });
  }

  List<double> _generatePreferenceVector() {
    // Organization Model (3 positions)
    double orgRotational =
        (organizational_model == 'Rotational Leadership' ||
            organizational_model == 'Any')
        ? 1.0
        : 0.0;
    double orgConsensus =
        (organizational_model == 'Consensus-Based' ||
            organizational_model == 'Any')
        ? 1.0
        : 0.0;
    double orgElected =
        (organizational_model == 'Elected Committee / Leaders' ||
            organizational_model == 'Any')
        ? 1.0
        : 0.0;

    // Participation Method (3 positions)
    double partVoluntary =
        (participation_method == 'Voluntary' || participation_method == 'Any')
        ? 1.0
        : 0.0;
    double partInvitation =
        (participation_method == 'Invitation-Based' ||
            participation_method == 'Any')
        ? 1.0
        : 0.0;
    double partCommunity =
        (participation_method == 'Community-Based' ||
            participation_method == 'Any')
        ? 1.0
        : 0.0;

    // Meeting Frequency (3 positions)
    double meetWeekly =
        (meeting_frequency == 'Weekly' || meeting_frequency == 'Any')
        ? 1.0
        : 0.0;
    double meetMonthly =
        (meeting_frequency == 'Monthly' || meeting_frequency == 'Any')
        ? 1.0
        : 0.0;
    double meetAsNeeded =
        (meeting_frequency == 'As Needed' || meeting_frequency == 'Any')
        ? 1.0
        : 0.0;

    // Payment Method (2 positions)
    double payCash =
        (payment_method == 'Cash' ||
            payment_method == 'Both' ||
            payment_method == 'Any')
        ? 1.0
        : 0.0;
    double payGcash =
        (payment_method == 'GCash' ||
            payment_method == 'Both' ||
            payment_method == 'Any')
        ? 1.0
        : 0.0;

    // Contribution Amount (7 positions)
    double contrib50_100 =
        (contribution_amount == '50-100' || contribution_amount == 'Any')
        ? 1.0
        : 0.0;
    double contrib100_150 =
        (contribution_amount == '100-150' || contribution_amount == 'Any')
        ? 1.0
        : 0.0;
    double contrib150_200 =
        (contribution_amount == '150-200' || contribution_amount == 'Any')
        ? 1.0
        : 0.0;
    double contrib250_300 =
        (contribution_amount == '250-300' || contribution_amount == 'Any')
        ? 1.0
        : 0.0;
    double contrib350_400 =
        (contribution_amount == '350-400' || contribution_amount == 'Any')
        ? 1.0
        : 0.0;
    double contrib450_500 =
        (contribution_amount == '450-500' || contribution_amount == 'Any')
        ? 1.0
        : 0.0;
    double contrib500_up =
        (contribution_amount == '500 and up' || contribution_amount == 'Any')
        ? 1.0
        : 0.0;

    // Penalty Policy (5 positions)
    double penaltySmall =
        (penalty_policy == 'Small Fine' || penalty_policy == 'Any') ? 1.0 : 0.0;
    double penaltyWarning =
        (penalty_policy == 'Warning' || penalty_policy == 'Any') ? 1.0 : 0.0;
    double penaltyCounseling =
        (penalty_policy == 'Counseling' || penalty_policy == 'Any') ? 1.0 : 0.0;
    double penaltyExtra =
        (penalty_policy == 'Extra Contribution' || penalty_policy == 'Any')
        ? 1.0
        : 0.0;
    double penaltySuspension =
        (penalty_policy == 'Suspension' || penalty_policy == 'Any') ? 1.0 : 0.0;

    // Open For All (1 position)
    double openAll = (openForAll == 'Yes' || openForAll == null) ? 1.0 : 0.0;

    return [
      orgRotational,
      orgConsensus,
      orgElected,
      partVoluntary,
      partInvitation,
      partCommunity,
      meetWeekly,
      meetMonthly,
      meetAsNeeded,
      payCash,
      payGcash,
      contrib50_100,
      contrib100_150,
      contrib150_200,
      contrib250_300,
      contrib350_400,
      contrib450_500,
      contrib500_up,
      penaltySmall,
      penaltyWarning,
      penaltyCounseling,
      penaltyExtra,
      penaltySuspension,
      openAll,
    ];
  }

  /// Computes the cosine similarity between the user's preference vector `u`
  /// and a Dayung unit's vector `d`.
  ///
  /// Formula:
  /// cosine_similarity(U, D) = (U ⋅ D) / (||U|| * ||D||)
  ///
  /// Where:
  /// - U ⋅ D is the dot product of the two vectors
  /// - ||U|| and ||D|| are the magnitudes (lengths) of the vectors
  ///
  /// The result ranges from -1 to 1:
  /// - 1 → vectors are very similar
  /// - 0 → vectors are orthogonal (no relation)
  /// - -1 → vectors are opposite
  ///
  /// This is used to rank Dayung units based on how closely they match
  /// the user's preferences

  double cosineSimilarity(List<double> u, List<double> d) {
    if (u.length != d.length || u.isEmpty) return 0.0;
    double dot = 0, magU = 0, magD = 0;
    for (int i = 0; i < u.length; i++) {
      dot += u[i] * d[i];
      magU += u[i] * u[i];
      magD += d[i] * d[i];
    }
    const eps = 1e-10;
    if (magU < eps || magD < eps) return 0.0;
    return dot / (sqrt(magU) * sqrt(magD));
  }

  //various vector shapes from PostgREST
  List<double> _parseVector(dynamic v) {
    if (v == null) return [];
    try {
      if (v is List) return v.map((e) => (e as num).toDouble()).toList();
      if (v is String) {
        final s = v.replaceAll(RegExp(r'[\[\]\(\)\s]'), '');
        return s.isEmpty
            ? []
            : s.split(',').map((e) => double.parse(e)).toList();
      }
      if (v is Map && v['data'] != null) {
        return _parseVector(v['data']);
      }
    } catch (e, st) {
      debugPrint('DEBUG: _parseVector failed: $e\n$st\nraw=$v');
    }
    return [];
  }

  List<double> _buildUnitVectorFromRow(Map<String, dynamic> m) {
    String norm(String? s) => (s ?? '').trim().toLowerCase();
    String clean(String? s) => norm(s).replaceAll(RegExp(r'[^a-z0-9]+'), ' ');

    final orgKey = clean(m['organizational_model']?.toString());
    final partKey = clean(m['participation_method']?.toString());
    final meetKey = clean(m['meeting_frequency']?.toString());
    final payKey = clean(m['payment_method']?.toString());
    final contribKey = clean(m['contribution_amount']?.toString());
    final penKey = clean(m['penalty_policy']?.toString());

    // open_for_all can be bool, string, or number
    final openRaw = m['open_for_all'];
    bool open = false;
    if (openRaw is bool) {
      open = openRaw;
    } else if (openRaw is num) {
      open = openRaw != 0;
    } else if (openRaw is String) {
      final s = norm(openRaw);
      open = s == 'yes' || s == 'true' || s == '1' || s == 'y';
    }

    // Organizational Model (neutral if unknown)
    double orgRot = 0, orgCon = 0, orgElec = 0;
    if (orgKey.isEmpty) {
      orgRot = orgCon = orgElec = 1;
    } else {
      if (orgKey.contains('rotational')) orgRot = 1;
      if (orgKey.contains('consensus')) orgCon = 1;
      if (orgKey.contains('elected') ||
          orgKey.contains('committee') ||
          orgKey.contains('leader'))
        orgElec = 1;
      if (orgRot + orgCon + orgElec == 0) orgRot = orgCon = orgElec = 1;
    }

    // Participation Method
    double partVol = 0, partInv = 0, partComm = 0;
    if (partKey.isEmpty) {
      partVol = partInv = partComm = 1;
    } else {
      if (partKey.contains('voluntar')) partVol = 1;
      if (partKey.contains('invitation') || partKey.contains('invite'))
        partInv = 1;
      if (partKey.contains('community')) partComm = 1;
      if (partVol + partInv + partComm == 0) partVol = partInv = partComm = 1;
    }

    // Meeting Frequency
    double meetW = 0, meetM = 0, meetN = 0;
    if (meetKey.isEmpty) {
      meetW = meetM = meetN = 1;
    } else {
      if (meetKey.contains('weekly') || meetKey.contains('week')) meetW = 1;
      if (meetKey.contains('monthly') || meetKey.contains('month')) meetM = 1;
      if (meetKey.contains('needed') || meetKey.contains('need')) meetN = 1;
      if (meetW + meetM + meetN == 0) meetW = meetM = meetN = 1;
    }

    // Payment Method
    double payCash = 0, payGcash = 0;
    if (payKey.isEmpty) {
      payCash = payGcash = 1;
    } else {
      if (payKey.contains('both')) {
        payCash = 1;
        payGcash = 1;
      }
      if (payKey.contains('cash')) payCash = 1;
      if (payKey.contains('gcash') || payKey.contains('g cash')) payGcash = 1;
      if (payCash + payGcash == 0) payCash = payGcash = 1;
    }

    // Contribution Amount buckets
    double c50_100 = 0,
        c100_150 = 0,
        c150_200 = 0,
        c250_300 = 0,
        c350_400 = 0,
        c450_500 = 0,
        c500_up = 0;
    double pickRange(String key) {
      final nums = RegExp(
        r'\d+',
      ).allMatches(key).map((m) => int.tryParse(m.group(0)!) ?? 0).toList();
      if (nums.isEmpty) return -1;
      final lo = nums.first;
      final hi = nums.length > 1 ? nums[1] : lo;
      final mid = ((lo + hi) / 2).toDouble();
      return mid;
    }

    if (contribKey.isEmpty) {
      c50_100 = c100_150 = c150_200 = c250_300 = c350_400 = c450_500 = c500_up =
          1;
    } else {
      final mid = pickRange(contribKey);
      if (mid < 0) {
        c50_100 = c100_150 = c150_200 = c250_300 = c350_400 = c450_500 =
            c500_up = 1;
      } else {
        if (mid <= 100)
          c50_100 = 1;
        else if (mid <= 150)
          c100_150 = 1;
        else if (mid <= 200)
          c150_200 = 1;
        else if (mid <= 300)
          c250_300 = 1;
        else if (mid <= 400)
          c350_400 = 1;
        else if (mid <= 500)
          c450_500 = 1;
        else
          c500_up = 1;
      }
    }

    // Penalty Policy
    double pSmall = 0, pWarn = 0, pCouns = 0, pExtra = 0, pSusp = 0;
    if (penKey.isEmpty) {
      pSmall = pWarn = pCouns = pExtra = pSusp = 1;
    } else {
      if (penKey.contains('small') && penKey.contains('fine')) pSmall = 1;
      if (penKey.contains('warning') || penKey.contains('warn')) pWarn = 1;
      if (penKey.contains('counsel')) pCouns = 1;
      if (penKey.contains('extra') || penKey.contains('contribution'))
        pExtra = 1;
      if (penKey.contains('susp')) pSusp = 1;
      if (pSmall + pWarn + pCouns + pExtra + pSusp == 0)
        pSmall = pWarn = pCouns = pExtra = pSusp = 1;
    }

    final openAll = open ? 1.0 : 0.0;

    return [
      orgRot.toDouble(),
      orgCon.toDouble(),
      orgElec.toDouble(),
      partVol.toDouble(),
      partInv.toDouble(),
      partComm.toDouble(),
      meetW.toDouble(),
      meetM.toDouble(),
      meetN.toDouble(),
      payCash.toDouble(),
      payGcash.toDouble(),
      c50_100.toDouble(),
      c100_150.toDouble(),
      c150_200.toDouble(),
      c250_300.toDouble(),
      c350_400.toDouble(),
      c450_500.toDouble(),
      c500_up.toDouble(),
      pSmall.toDouble(),
      pWarn.toDouble(),
      pCouns.toDouble(),
      pExtra.toDouble(),
      pSusp.toDouble(),
      openAll,
    ];
  }

  Future<void> _fetchSuggestionsLocal() async {
    setState(() => isLoading = true);
    try {
      final userVector = _generatePreferenceVector();
      debugPrint(
        'DEBUG: User Preference Vector len=${userVector.length}: $userVector',
      );

      final resp = await Supabase.instance.client
          .from('dayung_units')
          .select(
            'id,name,barangay,city,province,latitude,longitude,vector,organizational_model,participation_method,meeting_frequency,payment_method,contribution_amount,penalty_policy,open_for_all',
          );

      debugPrint('DEBUG: dayung_units resp type=${resp.runtimeType}');
      if (resp is! List) {
        debugPrint('DEBUG: Unexpected resp: $resp');
        setState(() => suggestedUnits = []);
        return;
      }

      debugPrint('DEBUG: Total rows fetched: ${resp.length}');
      final units = <Map<String, dynamic>>[];
      int nullVectorCount = 0;
      int derivedCount = 0;
      int badLengthCount = 0;

      for (final raw in resp) {
        final m = Map<String, dynamic>.from(raw as Map);
        final rawVector = m['vector'];
        final parsed = _parseVector(rawVector);

        if (parsed.isEmpty) {
          nullVectorCount++;
          final derived = _buildUnitVectorFromRow(m);
          if (derived.length == userVector.length) {
            m['__parsedVector'] = derived;
            m['__vectorStatus'] = 'derived_from_fields';
            derivedCount++;
            debugPrint(
              'DEBUG: Derived vector for id=${m['id']} name=${m['name']}: $derived',
            );
          } else {
            m['__parsedVector'] = List<double>.filled(userVector.length, 0.0);
            m['__vectorStatus'] = 'fallback_zero';
          }
          units.add(m);
          continue;
        }

        if (parsed.length != userVector.length) {
          badLengthCount++;
          debugPrint(
            'DEBUG: Length mismatch id=${m['id']} name=${m['name']} parsedLen=${parsed.length} expected=${userVector.length}',
          );
          // Keep anyway; similarity will be 0
        }

        m['__parsedVector'] = parsed;
        m['__vectorStatus'] = 'ok';
        units.add(m);
      }

      debugPrint(
        'DEBUG: Kept units=${units.length} | null/empty=${nullVectorCount} | derived=${derivedCount} | len-mismatch=${badLengthCount}',
      );

      for (var u in units) {
        final vec = (u['__parsedVector'] as List<double>? ?? []);
        final sim = cosineSimilarity(userVector, vec);
        debugPrint(
          'DEBUG: Unit "${u['name']}" status=${u['__vectorStatus']} sim=${sim.toStringAsFixed(3)} vecLen=${vec.length}',
        );
      }

      units.sort((a, b) {
        final va = (a['__parsedVector'] as List<double>? ?? const []);
        final vb = (b['__parsedVector'] as List<double>? ?? const []);
        final simA = cosineSimilarity(userVector, va);
        final simB = cosineSimilarity(userVector, vb);
        return simB.compareTo(simA);
      });

      setState(() => suggestedUnits = units);

      debugPrint('DEBUG: Suggested count=${suggestedUnits.length}');
      for (var u in suggestedUnits) {
        final vec = (u['__parsedVector'] as List<double>? ?? const []);
        final sim = cosineSimilarity(userVector, vec);
        debugPrint(
          ' - ID:${u['id']} "${u['name']}" status=${u['__vectorStatus']} sim=${sim.toStringAsFixed(3)}',
        );
      }
    } catch (e) {
      debugPrint('DEBUG: Local fetch error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local similarity error: $e')));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _fetchSuggestions() async {
    await _fetchSuggestionsLocal();
  }

  Future<void> _savePreferences({int? selectedUnitId}) async {
    final payload = {
      'user_id': widget.userId,
      'organizational_model': organizational_model,
      'participation_method': participation_method,
      'meeting_frequency': meeting_frequency,
      'penalty_policy': penalty_policy,
      'contribution_amount': contribution_amount,
      'membership_payment': membership_payment,
      'penalty_payment': penalty_payment,
      'payment_method': payment_method,
      'open_for_all': openForAll == null ? null : (openForAll == 'Yes'),
      'selected_unit_id': selectedUnitId,
    };

    final existing = await Supabase.instance.client
        .from('user_preferences')
        .select('id')
        .eq('user_id', widget.userId)
        .limit(1);

    if ((existing as List).isNotEmpty) {
      await Supabase.instance.client
          .from('user_preferences')
          .update(payload)
          .eq('user_id', widget.userId);
    } else {
      await Supabase.instance.client.from('user_preferences').insert(payload);
    }
  }

  Future<void> _completeRegistration({int? selectedUnitId}) async {
    setState(() => isSubmitting = true);
    try {
      await _savePreferences(selectedUnitId: selectedUnitId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preferences saved'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
            backgroundColor: Colors.blue,
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MemberDashboardPage()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    return Scaffold(
      backgroundColor: kBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kPrimaryDark, kPrimary, kBg],
            stops: [0.0, 0.15, 0.15],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Find a Dayung',
                        style: TextStyle(
                          fontSize: isWide ? 24 : 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontFamily: 'Montserrat',
                          letterSpacing: 0.3,
                          shadows: const [
                            Shadow(
                              color: Colors.black26,
                              offset: Offset(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: kBg,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 20,
                        offset: Offset(0, -5),
                      ),
                    ],
                  ),
                  child: _buildBody(context, isWide),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool isWide) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }

    return RefreshIndicator(
      onRefresh: () async => _fetchSuggestions(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 2,
            color: kCardBg,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildDropdown(
                      label: 'Organizational Model',
                      value: organizational_model,
                      items: [
                        'Any',
                        'Rotational Leadership',
                        'Consensus-Based',
                        'Elected Committee / Leaders',
                      ],
                      onChanged: (val) {
                        setState(() => organizational_model = val);
                        _fetchSuggestions();
                      },
                    ),
                    _buildDropdown(
                      label: 'Participation Method',
                      value: participation_method,
                      items: [
                        'Any',
                        'Voluntary',
                        'Invitation-Based',
                        'Community-Based',
                      ],
                      onChanged: (val) {
                        setState(() => participation_method = val);
                        _fetchSuggestions();
                      },
                    ),
                    _buildDropdown(
                      label: 'Meeting Frequency',
                      value: meeting_frequency,
                      items: ['Any', 'Weekly', 'Monthly', 'As Needed'],
                      onChanged: (val) {
                        setState(() => meeting_frequency = val);
                        _fetchSuggestions();
                      },
                    ),
                    _buildDropdown(
                      label: 'Registration Fee Range',
                      value: contribution_amount,
                      items: [
                        'Any',
                        '50-100',
                        '100-150',
                        '150-200',
                        '250-300',
                        '350-400',
                        '450-500',
                        '500 and up',
                      ],
                      onChanged: (val) {
                        setState(() => contribution_amount = val);
                        _fetchSuggestions();
                      },
                    ),
                    _buildDropdown(
                      label: 'Membership Payment',
                      value: membership_payment,
                      items: [
                        'Any',
                        '50-100',
                        '100-150',
                        '150-200',
                        '250-300',
                        '350-400',
                        '450-500',
                        '500 and up',
                      ],
                      onChanged: (val) {
                        setState(() => membership_payment = val);
                        _fetchSuggestions();
                      },
                    ),
                    _buildDropdown(
                      label: 'Penalty Payment',
                      value: penalty_payment,
                      items: ['100', '200', '300', '500'],
                      onChanged: (val) {
                        setState(() => penalty_payment = val);
                        _fetchSuggestions();
                      },
                    ),
                    _buildDropdown(
                      label: 'Payment Method',
                      value: payment_method,
                      items: ['Any', 'Cash', 'GCash', 'Both'],
                      onChanged: (val) {
                        setState(() => payment_method = val);
                        _fetchSuggestions();
                      },
                    ),
                    _buildDropdown(
                      label: 'Open for All?',
                      value: openForAll,
                      items: ['Yes', 'No'],
                      onChanged: (val) {
                        setState(() => openForAll = val);
                        _fetchSuggestions();
                      },
                    ),
                    _buildDropdown(
                      label: 'Penalty Policy',
                      value: penalty_policy,
                      items: [
                        'Any',
                        'Small Fine',
                        'Suspension',
                        'Counseling',
                        'Warning',
                        'Extra Contribution',
                      ],
                      onChanged: (val) {
                        setState(() => penalty_policy = val);
                        _fetchSuggestions();
                      },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.search),
                        label: const Text('Find Matching Units'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          if (organizational_model == null &&
                              participation_method == null &&
                              meeting_frequency == null &&
                              contribution_amount == null &&
                              membership_payment == null &&
                              penalty_payment == null &&
                              payment_method == null &&
                              openForAll == null &&
                              penalty_policy == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please fill at least one preference or skip.',
                                ),
                              ),
                            );
                            return;
                          }
                          _fetchSuggestions();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (suggestedUnits.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Suggested Dayung Units',
                style: TextStyle(
                  fontSize: isWide ? 20 : 18,
                  fontWeight: FontWeight.w800,
                  color: kPrimaryDark,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...suggestedUnits.map((unit) {
              return Card(
                elevation: 2,
                color: kCardBg,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            backgroundColor: kPrimary.withOpacity(0.12),
                            child: const Icon(Icons.home, color: kPrimary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  unit['name'] ?? 'Unnamed Unit',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: kText,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  [
                                        if (unit['barangay'] != null)
                                          unit['barangay'],
                                        if (unit['city'] != null) unit['city'],
                                        if (unit['province'] != null)
                                          unit['province'],
                                      ]
                                      .where(
                                        (e) => (e ?? '').toString().isNotEmpty,
                                      )
                                      .join(', '),
                                  style: const TextStyle(
                                    color: kSubText,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // --- Map preview here ---
                      Builder(
                        builder: (context) {
                          final lat = double.tryParse('${unit['latitude']}');
                          final lng = double.tryParse('${unit['longitude']}');
                          if (lat != null && lng != null) {
                            return Padding(
                              padding: const EdgeInsets.only(
                                top: 10.0,
                                bottom: 8.0,
                              ),
                              child: DayungMapPreview(
                                latitude: lat,
                                longitude: lng,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.map),
                            label: const Text('Map'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kPrimary,
                              side: const BorderSide(color: kPrimary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              final selected = Map<String, dynamic>.from(
                                unit as Map,
                              );
                              final all = suggestedUnits
                                  .map(
                                    (e) => Map<String, dynamic>.from(e as Map),
                                  )
                                  .toList();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DayungMapPage(
                                    dayung: selected,
                                    isApplied: false,
                                    isMember: false,
                                    allDayungs: all,
                                    nearbyRadiusMeters: 5000,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Select'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kPrimary,
                              side: const BorderSide(color: kPrimary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => _completeRegistration(
                              selectedUnitId: unit['id'] as int,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ] else if (contribution_amount != null ||
              membership_payment != null ||
              penalty_payment != null ||
              payment_method != null ||
              openForAll != null ||
              penalty_policy != null) ...[
            const SizedBox(height: 8),
            const Text(
              'No suggestions found with the given preferences.',
              style: TextStyle(color: kSubText),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Skip & Continue'),
              style: TextButton.styleFrom(
                foregroundColor: kPrimaryDark,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onPressed: () async {
                await _savePreferences();
                if (!mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const DayungSuggestionsPage(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required List<String> items,
    required String? value,
    required Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
        items: items
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: onChanged,
        validator: (_) => null,
      ),
    );
  }
}

class DayungMapPreview extends StatefulWidget {
  final double latitude;
  final double longitude;

  const DayungMapPreview({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<DayungMapPreview> createState() => _DayungMapPreviewState();
}

class _DayungMapPreviewState extends State<DayungMapPreview> {
  ml.MaplibreMapController? _controller;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _StaticOsmTilePreview(
        latitude: widget.latitude,
        longitude: widget.longitude,
        height: 120,
        zoom: 14,
      );
    }

    return SizedBox(
      height: 120,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ml.MapLibreMap(
          styleString:
              'https://api.maptiler.com/maps/basic-v2/style.json?key=ZgS5pYNNGTrRGUAnlS71',
          initialCameraPosition: ml.CameraPosition(
            target: ml.LatLng(widget.latitude, widget.longitude),
            zoom: 14,
          ),
          onMapCreated: (ml.MaplibreMapController controller) {
            _controller = controller;
          },
          onStyleLoadedCallback: () {
            _controller?.addSymbol(
              ml.SymbolOptions(
                geometry: ml.LatLng(widget.latitude, widget.longitude),
                iconImage: 'marker-15',
                iconSize: 1.4,
              ),
            );
          },
          myLocationEnabled: false,
          compassEnabled: false,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          scrollGesturesEnabled: false,
          zoomGesturesEnabled: false,
          attributionButtonMargins: const Point(8, 8),
          logoViewMargins: const Point(8, 8),
        ),
      ),
    );
  }
}

class _StaticOsmTilePreview extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double height;
  final int zoom;

  const _StaticOsmTilePreview({
    required this.latitude,
    required this.longitude,
    this.height = 120,
    this.zoom = 14,
  });

  (int x, int y) _latLngToTile(double lat, double lon, int z) {
    final n = pow(2.0, z).toDouble();
    final xtile = ((lon + 180.0) / 360.0 * n).floor();
    final latRad = lat * pi / 180.0;
    final ytile = ((1.0 - (log(tan(latRad) + 1 / cos(latRad)) / pi)) / 2.0 * n)
        .floor();
    return (xtile, ytile);
  }

  @override
  Widget build(BuildContext context) {
    final (x, y) = _latLngToTile(latitude, longitude, zoom);
    final url = 'https://tile.openstreetmap.org/$zoom/$x/$y.png';

    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
            ),
            // Center marker overlay
            const IgnorePointer(
              child: Center(
                child: Icon(
                  Icons.location_on,
                  color: Colors.redAccent,
                  size: 28,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
