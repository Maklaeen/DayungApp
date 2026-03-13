import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserProvider extends ChangeNotifier {
  User? _user;
  String _fullName = '';
  String _mobileNumber = 'Not Available';
  String _userAddress = 'Not Provided';
  String? _profileUrl; // <-- Add this

  User? get user => _user;
  String get fullName => _fullName;
  String get mobileNumber => _mobileNumber;
  String get userAddress => _userAddress;
  String? get profileUrl => _profileUrl; // <-- Add this

  // Fetch user data
  Future<void> loadUserData() async {
    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser != null) {
      final userId = currentUser.id;
      final response = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response != null) {
        _user = currentUser;
        _fullName = '${_getTitle(response['sex'])} ${response['full_name']}';
        _mobileNumber = response['mobile_number'] ?? 'Not Available';
        _userAddress = response['address'] ?? 'Not Provided';
        _profileUrl = response['profile_url']; // <-- Add this
      } else {
        _fullName = 'Member';
        _mobileNumber = 'Not Available';
        _userAddress = 'Not Provided';
        _profileUrl = null; // <-- Add this
      }

      notifyListeners();
    }
  }

  void setProfileUrl(String? url) {
    _profileUrl = url;
    notifyListeners();
  }

  String _getTitle(String sex) {
    if (sex.toLowerCase() == 'male') {
      return 'Mr.';
    } else if (sex.toLowerCase() == 'female') {
      return 'Mrs.';
    }
    return '';
  }
}
