import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api.dart';

enum AuthStatus { loading, signedOut, signedIn }

class AuthState extends ChangeNotifier {
  AuthStatus status = AuthStatus.loading;
  AppUser? user;

  static const _tokenKey = 'auth_token';

  AuthState() {
    Api.instance.onUnauthorized = () => logout();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null) {
      status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    Api.instance.token = token;
    try {
      user = AppUser.fromJson(await Api.instance.get('/api/me'));
      status = AuthStatus.signedIn;
    } on ApiException catch (e) {
      // Haddii server-ka la heli waayo, token-ka ha tirtirin
      if (e.status == 401) {
        await _clear();
      } else {
        status = AuthStatus.signedOut;
      }
    }
    notifyListeners();
  }

  Future<void> login(String phone, String password) async {
    final res = await Api.instance.post('/api/auth/login', {'phone': phone, 'password': password});
    await _onAuth(res);
  }

  Future<void> register({
    required String name,
    required String phone,
    required String password,
    required String businessName,
    required String businessType,
    required String currency,
  }) async {
    final res = await Api.instance.post('/api/auth/register', {
      'name': name,
      'phone': phone,
      'password': password,
      'business_name': businessName,
      'business_type': businessType,
      'currency': currency,
    });
    await _onAuth(res);
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    user = AppUser.fromJson(await Api.instance.put('/api/me', data));
    notifyListeners();
  }

  Future<void> _onAuth(dynamic res) async {
    final token = res['token'] as String;
    Api.instance.token = token;
    user = AppUser.fromJson(res['user']);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    status = AuthStatus.signedIn;
    notifyListeners();
  }

  Future<void> _clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    Api.instance.token = null;
    user = null;
    status = AuthStatus.signedOut;
  }

  Future<void> logout() async {
    await _clear();
    notifyListeners();
  }
}
