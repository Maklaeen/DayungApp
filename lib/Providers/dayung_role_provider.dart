import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DayungRoleProvider extends ChangeNotifier {
  final _sb = Supabase.instance.client;

  int? unitId;
  bool loading = false;

  bool isSuperAdmin = false;
  bool isPresident = false;
  bool isSecretary = false;
  bool isTreasurer = false;
  bool isCollector = false;
  bool isMember = false; // add this

  int _reqCounter = 0;

  // Convenience
  bool get isAssigned =>
      unitId != null &&
      (isMember || isPresident || isSecretary || isTreasurer || isCollector);

  Future<int?> ensureOfficerUnitSelection() async {
    if (unitId != null) return unitId;
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final rows = await _sb
          .from('dayung_units')
          .select('id')
          .or('president_id.eq.$uid,secretary_id.eq.$uid,treasurer_id.eq.$uid')
          .limit(1);
      final list = List<Map<String, dynamic>>.from(rows);
      if (list.isNotEmpty) {
        unitId = list.first['id'] as int?;
        notifyListeners();
        return unitId;
      }
    } catch (_) {}
    return null;
  }

  Future<void> refreshRoles(int? newUnitId) async {
    if (loading && newUnitId == unitId) {
      debugPrint('[ROLES] skip: already loading for unit=$unitId');
      return;
    }
    final req = ++_reqCounter;
    unitId = newUnitId;
    loading = true;
    notifyListeners();

    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      _reset();
      loading = false;
      notifyListeners();
      return;
    }

    try {
      // --- SUPERADMIN CHECK ---
      try {
        debugPrint('Current UID: $uid');
        final user = await _sb
            .from('users')
            .select('role')
            .eq('id', uid)
            .maybeSingle();
        debugPrint('User row: $user');
        isSuperAdmin = user?['role'] == 'superadmin';
        debugPrint('[ROLES] isSuperAdmin=$isSuperAdmin');
      } catch (_) {
        isSuperAdmin = false;
      }

      // If superadmin, skip the rest
      if (isSuperAdmin) {
        isPresident = isSecretary = isTreasurer = isCollector = isMember = false;
        loading = false;
        notifyListeners();
        return;
      }

      // President (any unit)
      try {
        final pres = await _sb
            .from('dayung_units')
            .select('id')
            .eq('president_id', uid)
            .limit(1);
        isPresident = (pres as List).isNotEmpty;
      } catch (_) {
        isPresident = false;
      }

      if (newUnitId != null) {
        Map<String, dynamic>? du;
        try {
          du = await _sb
              .from('dayung_units')
              .select('secretary_id, treasurer_id')
              .eq('id', newUnitId)
              .maybeSingle();
        } catch (_) {}
        isSecretary = (du?['secretary_id']?.toString() ?? '') == uid;
        isTreasurer = (du?['treasurer_id']?.toString() ?? '') == uid;

        try {
          final dc = await _sb
              .from('dayung_collectors')
              .select('user_id')
              .eq('dayung_unit_id', newUnitId)
              .eq('user_id', uid)
              .limit(1);
          isCollector = (dc as List).isNotEmpty;
        } catch (_) {
          isCollector = false;
        }

        try {
          final app = await _sb
              .from('applications')
              .select('id')
              .eq('user_id', uid)
              .eq('dayung_unit_id', newUnitId)
              .eq('status', 'approved')
              .limit(1);
          isMember = (app as List).isNotEmpty;
        } catch (_) {
          isMember = false;
        }
      } else {
        isSecretary = isTreasurer = isCollector = isMember = false;
      }
    } catch (e) {
      _reset();
      print('[ROLES] error: $e');
    } finally {
      if (req != _reqCounter) return; // stale
      loading = false;
      notifyListeners();
      debugPrint('[ROLES] refreshRoles finished for unit=$unitId');
    }
  }

  void _reset() {
    isSuperAdmin = false;
    isPresident = isSecretary = isTreasurer = isCollector = isMember = false;
  }
}
