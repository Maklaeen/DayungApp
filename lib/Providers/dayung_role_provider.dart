import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DayungRoleProvider extends ChangeNotifier {
  final _sb = Supabase.instance.client;

  int? unitId;
  bool loading = false;

  bool isPresident = false;
  bool isSecretary = false;
  bool isTreasurer = false;
  bool isCollector = false;
  bool isMember = false;

  Future<void> refreshRoles(int? newUnitId) async {
    unitId = newUnitId;
    loading = true;
    notifyListeners();

    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      isPresident = isSecretary = isTreasurer = isCollector = isMember = false;
      loading = false;
      notifyListeners();
      return;
    }

    try {
      // Always compute presidency across ANY unit (works even if unitId is not ready yet)
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

      // If a specific unit is selected, compute other flags for that unit
      if (newUnitId != null) {
        Map<String, dynamic>? du;
        try {
          du = await _sb
              .from('dayung_units')
              .select('secretary_id, treasurer_id')
              .eq('id', newUnitId)
              .maybeSingle();
        } catch (_) {
          du = null;
        }

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
        // No selected unit yet: reset per-unit roles
        isSecretary = isTreasurer = isCollector = isMember = false;
      }
    } catch (_) {
      isPresident = isSecretary = isTreasurer = isCollector = isMember = false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
