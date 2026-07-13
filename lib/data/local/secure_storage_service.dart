// import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// 
// class SecureStorageService {
//   final _storage = const FlutterSecureStorage();
// 
//   IOSOptions _getIOSOptions() => const IOSOptions(
//         accessibility: KeychainAccessibility.first_unlock,
//       );
// 
//   AndroidOptions _getAndroidOptions() => const AndroidOptions(
//         encryptedSharedPreferences: true,
//       );
// 
//   Future<void> saveToken(String key, String value) async {
//     await _storage.write(
//       key: key,
//       value: value,
//       iOptions: _getIOSOptions(),
//       aOptions: _getAndroidOptions(),
//     );
//   }
// 
//   Future<String?> readToken(String key) async {
//     return await _storage.read(
//       key: key,
//       iOptions: _getIOSOptions(),
//       aOptions: _getAndroidOptions(),
//     );
//   }
// 
//   Future<void> deleteToken(String key) async {
//     await _storage.delete(
//       key: key,
//       iOptions: _getIOSOptions(),
//       aOptions: _getAndroidOptions(),
//     );
//   }
// }

