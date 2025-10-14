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

  Future<void> refreshRoles(int? newUnitId) async {
    unitId = newUnitId;
    if (newUnitId == null) {
      isPresident = isSecretary = isTreasurer = isCollector = false;
      notifyListeners();
      return;
    }

    loading = true;
    notifyListeners();

    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      isPresident = isSecretary = isTreasurer = isCollector = false;
      loading = false;
      notifyListeners();
      return;
    }

    try {
      // Get officer IDs for this unit
      final du = await _sb
          .from('dayung_units')
          .select('president_id, secretary_id, treasurer_id')
          .eq('id', newUnitId)
          .maybeSingle();

      isPresident = (du?['president_id']?.toString() ?? '') == uid;
      isSecretary = (du?['secretary_id']?.toString() ?? '') == uid;
      isTreasurer = (du?['treasurer_id']?.toString() ?? '') == uid;

      // Collector membership
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
    } catch (_) {
      // If RLS blocks, assume no officer/collector role for this unit
      isPresident = isSecretary = isTreasurer = isCollector = false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}