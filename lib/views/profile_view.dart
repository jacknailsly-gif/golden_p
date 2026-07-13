import 'package:flutter/material.dart';
import 'package:golden_p/services/auth_service.dart';
import 'package:golden_p/views/login_view.dart';
import 'package:golden_p/views/admin_dashboard_view.dart';
import 'package:golden_p/views/settings/profile_info_view.dart';
import 'package:golden_p/views/settings/security_settings_view.dart';
import 'package:golden_p/views/settings/notification_settings_view.dart';
import 'package:golden_p/views/settings/language_settings_view.dart';
import 'package:golden_p/views/settings/privacy_policy_view.dart';
class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  Future<void> _handleLogout(BuildContext context) async {
    await AuthService.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginView()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = AuthService.currentUserEmail ?? 'user@secure.com';
    final userName = email.split('@').first;
    final uid = 'UID-8492-${userName.hashCode.abs().toString().substring(0, 4)}';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
            child: Column(
              children: [
                _buildProfileHeader(userName, email, uid, theme, context),
                const SizedBox(height: 32),
                _buildSettingsList(theme, context),
                const SizedBox(height: 40),
                _buildLogoutButton(context, theme),
                const SizedBox(height: 100), // Padding for BottomNav
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(String name, String email, String uid, ThemeData theme, BuildContext context) {
    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1E293B),
                  border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3), width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.person_rounded, size: 50, color: Color(0xFF3B82F6)),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0F172A), width: 2),
                  ),
                  child: const Icon(Icons.edit_rounded, size: 14, color: Colors.white),
                ),
              )
            ],
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tag_rounded, size: 14, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Text(
                  uid,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF5F6368),
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {},
                  child: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF3B82F6)),
                ),
              ],
            ),
          ),
          if (AuthService.currentUserRole == 'admin') ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardView()));
              },
              icon: const Icon(Icons.admin_panel_settings_rounded, size: 18),
              label: const Text('Admin Dashboard'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF3B82F6),
                side: const BorderSide(color: Color(0xFF3B82F6)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsList(ThemeData theme, BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          _buildSettingsTile(Icons.person_outline_rounded, 'Profile Information', theme, context: context, destination: const ProfileInfoView()),
          _buildDivider(),
          _buildSettingsTile(Icons.shield_outlined, 'Security & Password', theme, context: context, destination: const SecuritySettingsView()),
          _buildDivider(),
          _buildSettingsTile(Icons.notifications_none_rounded, 'Notification Preferences', theme, context: context, destination: const NotificationSettingsView()),
          _buildDivider(),
          _buildSettingsTile(Icons.language_rounded, 'Language', theme, trailing: 'English', context: context, destination: const LanguageSettingsView()),
          _buildDivider(),
          _buildSettingsTile(Icons.privacy_tip_outlined, 'Privacy Policy', theme, context: context, destination: const PrivacyPolicyView()),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(IconData icon, String title, ThemeData theme, {String? trailing, BuildContext? context, Widget? destination}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF3B82F6), size: 20),
      ),
      title: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(fontSize: 15, color: const Color(0xFFF8FAFC)),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null)
            Text(
              trailing,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
            ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
        ],
      ),
      onTap: () {
        if (context != null && destination != null) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => destination));
        }
      },
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, color: Colors.white.withValues(alpha: 0.05), indent: 64);
  }

  Widget _buildLogoutButton(BuildContext context, ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: () => _handleLogout(context),
        icon: const Icon(Icons.logout_rounded, color: Color(0xFFD93025)),
        label: const Text(
          'Log Out',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFFD93025),
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xFF1E293B),
          side: BorderSide(color: const Color(0xFFD93025).withValues(alpha: 0.3), width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
    );
  }
}
