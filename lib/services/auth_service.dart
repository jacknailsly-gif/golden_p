import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl = 'http://127.0.0.1:3000/api/v1/auth';
  
  static String? currentUserEmail;
  static String? currentToken;
  static String? currentUserRole;

  static Future<void> checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    currentUserEmail = prefs.getString('email');
    currentToken = prefs.getString('token');
    currentUserRole = prefs.getString('role');
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('email');
    await prefs.remove('token');
    await prefs.remove('role');
    currentUserEmail = null;
    currentToken = null;
    currentUserRole = null;
  }

  static Future<void> _saveSession(String email, String token, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('email', email);
    await prefs.setString('token', token);
    await prefs.setString('role', role);
    currentUserEmail = email;
    currentToken = token;
    currentUserRole = role;
  }

  static Future<bool> checkUserExists(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/check-user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['exists'] == true;
      }
      return false;
    } catch (e) {
      throw Exception('Network error or server down: $e');
    }
  }

  static Future<bool> register(String email, String password) async {
    // MOCK REGISTER FOR UI TESTING (Backend not yet active)
    await Future.delayed(const Duration(milliseconds: 800));
    if (email.isNotEmpty && password.isNotEmpty) {
      await _saveSession(email, 'mock_token_123', 'admin');
      return true;
    }
    return false;
  }

  static Future<bool> login(String email, String password) async {
    // MOCK LOGIN FOR UI TESTING (Backend not yet active)
    await Future.delayed(const Duration(milliseconds: 800));
    if (email.isNotEmpty && password.isNotEmpty) {
      await _saveSession(email, 'mock_token_123', 'admin');
      return true;
    }
    return false;
  }
}
