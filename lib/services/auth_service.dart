import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:golden_p/data/local/secure_storage_service.dart';

class AuthService {
  /// Override with `--dart-define=API_BASE_URL=https://host/api/v1`
  static const String apiRoot = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://127.0.0.1:3000/api/v1',
  );

  static String get authBaseUrl => '$apiRoot/auth';
  static String get adminBaseUrl => '$apiRoot/admin';

  static http.Client httpClient = http.Client();
  static SecureStorageService secureStorage = SecureStorageService();

  static String? currentUserEmail = 'tester@goldenp.ai';
  static String? currentToken = 'test_session_active';
  static String? currentUserRole = 'admin';

  static bool get isAdmin => currentUserRole == 'admin';

  // 🧪 โหมดทดสอบ: ข้ามหน้า Login เข้าสู่ระบบโดยตรง
  static bool get hasValidSession => true;

  static Future<void> checkSession() async {
    try {
      final token = await secureStorage.readToken(SecureStorageService.tokenKey);
      final email = await secureStorage.readToken(SecureStorageService.emailKey);
      final role = await secureStorage.readToken(SecureStorageService.roleKey);

      if (token != null && token.isNotEmpty && token != 'mock_token_123') {
        currentToken = token;
        currentUserEmail = email;
        currentUserRole = role ?? 'admin';
        return;
      }

      // Default testing session (ไม่ต้อง Login ก่อนในระหว่างทดสอบ)
      currentUserEmail = 'tester@goldenp.ai';
      currentToken = 'test_session_active';
      currentUserRole = 'admin';
    } catch (e) {
      debugPrint('[AUTH] checkSession: $e');
      currentUserEmail = 'tester@goldenp.ai';
      currentToken = 'test_session_active';
      currentUserRole = 'admin';
    }
  }

  static Future<void> logout() async {
    try {
      await secureStorage.deleteAll();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('email');
      await prefs.remove('token');
      await prefs.remove('role');
    } catch (_) {}
    currentUserEmail = null;
    currentToken = null;
    currentUserRole = null;
  }

  static Future<void> _saveSession(String email, String token, String role) async {
    final safeRole = _sanitizeRole(role);
    await secureStorage.saveToken(SecureStorageService.emailKey, email);
    await secureStorage.saveToken(SecureStorageService.tokenKey, token);
    await secureStorage.saveToken(SecureStorageService.roleKey, safeRole);
    currentUserEmail = email;
    currentToken = token;
    currentUserRole = safeRole;
  }

  static String _sanitizeRole(String? role) {
    final normalized = (role ?? 'user').trim().toLowerCase();
    if (normalized == 'admin' || normalized == 'user') return normalized;
    return 'user';
  }

  static Map<String, dynamic> _decodeBody(String body) {
    if (body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{};
  }

  static String? _extractToken(Map<String, dynamic> data) {
    final nested = data['data'];
    if (nested is Map) {
      final nestedToken = nested['token'] ?? nested['accessToken'] ?? nested['access_token'];
      if (nestedToken is String && nestedToken.isNotEmpty) return nestedToken;
    }
    final token = data['token'] ?? data['accessToken'] ?? data['access_token'];
    if (token is String && token.isNotEmpty) return token;
    return null;
  }

  static String _extractRole(Map<String, dynamic> data) {
    final user = data['user'];
    if (user is Map && user['role'] is String) {
      return _sanitizeRole(user['role'] as String);
    }
    final nested = data['data'];
    if (nested is Map) {
      if (nested['role'] is String) return _sanitizeRole(nested['role'] as String);
      final nestedUser = nested['user'];
      if (nestedUser is Map && nestedUser['role'] is String) {
        return _sanitizeRole(nestedUser['role'] as String);
      }
    }
    if (data['role'] is String) return _sanitizeRole(data['role'] as String);
    return 'user';
  }

  static String _extractEmail(Map<String, dynamic> data, String fallback) {
    final user = data['user'];
    if (user is Map && user['email'] is String && (user['email'] as String).isNotEmpty) {
      return user['email'] as String;
    }
    final nested = data['data'];
    if (nested is Map && nested['email'] is String && (nested['email'] as String).isNotEmpty) {
      return nested['email'] as String;
    }
    if (data['email'] is String && (data['email'] as String).isNotEmpty) {
      return data['email'] as String;
    }
    return fallback;
  }

  static Future<bool> checkUserExists(String email) async {
    try {
      final response = await httpClient.post(
        Uri.parse('$authBaseUrl/check-user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) {
        final data = _decodeBody(response.body);
        return data['exists'] == true;
      }
      return false;
    } catch (e) {
      throw Exception('Network error or server down: $e');
    }
  }

  static Future<bool> register(String email, String password) async {
    if (email.isEmpty || password.isEmpty) return false;
    try {
      final response = await httpClient.post(
        Uri.parse('$authBaseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        return false;
      }
      return _persistAuthResponse(response.body, email);
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }

  static Future<bool> login(String email, String password) async {
    if (email.isEmpty || password.isEmpty) return false;
    try {
      final response = await httpClient.post(
        Uri.parse('$authBaseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (response.statusCode != 200) {
        return false;
      }
      return _persistAuthResponse(response.body, email);
    } catch (e) {
      throw Exception('Login failed: $e');
    }
  }

  static Future<bool> _persistAuthResponse(String body, String fallbackEmail) async {
    final data = _decodeBody(body);
    final token = _extractToken(data);
    if (token == null || token.isEmpty || token == 'mock_token_123') {
      return false;
    }
    final role = _extractRole(data);
    final email = _extractEmail(data, fallbackEmail);
    await _saveSession(email, token, role);
    return true;
  }
}
