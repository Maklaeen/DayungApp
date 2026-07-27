import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/President/dashboard.dart';
import 'package:capstone_app/Treasurer/dashboard.dart';
import 'package:capstone_app/Collector/dashboard.dart';
import 'package:capstone_app/Members/dashboard.dart';

final _sb = Supabase.instance.client;

Future<bool> isPresident() async {
  final uid = _sb.auth.currentUser?.id;
  if (uid == null) return false;
  final rows = await _sb
      .from('dayung_units')
      .select('id')
      .eq('president_id', uid)
      .limit(1);
  return (rows as List).isNotEmpty;
}

Future<bool> isSecretary() async {
  final uid = _sb.auth.currentUser?.id;
  if (uid == null) return false;
  final rows = await _sb
      .from('dayung_units')
      .select('id')
      .eq('secretary_id', uid)
      .limit(1);
  return (rows as List).isNotEmpty;
}

Future<bool> isTreasurer() async {
  final uid = _sb.auth.currentUser?.id;
  if (uid == null) return false;
  final rows = await _sb
      .from('dayung_units')
      .select('id')
      .eq('treasurer_id', uid)
      .limit(1);
  return (rows as List).isNotEmpty;
}

Future<bool> isCollector() async {
  final uid = _sb.auth.currentUser?.id;
  if (uid == null) return false;
  final rows = await _sb
      .from('dayung_collectors')
      .select('dayung_unit_id')
      .eq('user_id', uid)
      .limit(1);
  return (rows as List).isNotEmpty;
}

Future<Widget> pickHome() async {
  if (await isPresident()) return const PresidentDashboardPage();
  if (await isTreasurer()) return const TreasurerDashboardPage();
  if (await isCollector()) return const CollectorDashboardPage();
  return const MemberDashboardPage();
}
