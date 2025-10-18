import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final membershipQualificationProvider =
    FutureProvider.family<bool, Map<String, dynamic>>((ref, params) async {
      final sb = Supabase.instance.client;
      final userId = params['userId'] as String;
      final unitId = params['unitId'] as int;

      // Fetch membership rules for the target unit
      final rulesRow = await sb
          .from('dayung_rules')
          .select('membership_rules')
          .eq('dayung_unit_id', unitId)
          .maybeSingle();

      final membershipRules =
          rulesRow?['membership_rules']?.toString().toLowerCase() ?? '';

      // Parse rules
      final openForAll = membershipRules.contains('open for all');
      final allowsMultiMembership = membershipRules.contains(
        'allow multi-membership',
      );

      // Check if user is already a member elsewhere
      final apps = await sb
          .from('applications')
          .select('dayung_unit_id')
          .eq('user_id', userId)
          .eq('status', 'approved');

      final alreadyMemberElsewhere = apps != null && apps.isNotEmpty;

      // Qualification logic
      if (openForAll) {
        return true; // Anyone can join
      }
      if (alreadyMemberElsewhere && !allowsMultiMembership) {
        return false; // Not qualified if already a member elsewhere and multi-membership not allowed
      }
      return true; // Qualified otherwise
    });
