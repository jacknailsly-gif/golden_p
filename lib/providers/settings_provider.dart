import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_p/services/local_storage_service.dart';

class SettingsState {
  final bool systemAlerts;
  final bool securityUpdates;
  final bool marketingEmails;
  final String language;
  final bool twoFactorEnabled;

  SettingsState({
    required this.systemAlerts,
    required this.securityUpdates,
    required this.marketingEmails,
    required this.language,
    required this.twoFactorEnabled,
  });

  SettingsState copyWith({
    bool? systemAlerts,
    bool? securityUpdates,
    bool? marketingEmails,
    String? language,
    bool? twoFactorEnabled,
  }) {
    return SettingsState(
      systemAlerts: systemAlerts ?? this.systemAlerts,
      securityUpdates: securityUpdates ?? this.securityUpdates,
      marketingEmails: marketingEmails ?? this.marketingEmails,
      language: language ?? this.language,
      twoFactorEnabled: twoFactorEnabled ?? this.twoFactorEnabled,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    return SettingsState(
      systemAlerts: LocalStorageService.getBool('systemAlerts', defaultValue: true),
      securityUpdates: LocalStorageService.getBool('securityUpdates', defaultValue: true),
      marketingEmails: LocalStorageService.getBool('marketingEmails', defaultValue: false),
      language: LocalStorageService.getString('language', defaultValue: 'en'),
      twoFactorEnabled: LocalStorageService.getBool('twoFactorEnabled', defaultValue: true),
    );
  }

  void toggleSystemAlerts(bool value) {
    LocalStorageService.setBool('systemAlerts', value);
    state = state.copyWith(systemAlerts: value);
  }

  void toggleSecurityUpdates(bool value) {
    LocalStorageService.setBool('securityUpdates', value);
    state = state.copyWith(securityUpdates: value);
  }

  void toggleMarketingEmails(bool value) {
    LocalStorageService.setBool('marketingEmails', value);
    state = state.copyWith(marketingEmails: value);
  }

  void setLanguage(String value) {
    LocalStorageService.setString('language', value);
    state = state.copyWith(language: value);
  }

  void toggleTwoFactor(bool value) {
    LocalStorageService.setBool('twoFactorEnabled', value);
    state = state.copyWith(twoFactorEnabled: value);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
