import 'package:flutter/material.dart';

class SecuritySettingsView extends StatefulWidget {
  const SecuritySettingsView({super.key});

  @override
  State<SecuritySettingsView> createState() => _SecuritySettingsViewState();
}

class _SecuritySettingsViewState extends State<SecuritySettingsView> {
  bool _is2faEnabled = false;

  void _toggle2FA(bool value) {
    setState(() {
      _is2faEnabled = value;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value ? '2FA Enabled via Authenticator' : '2FA Disabled. Not recommended!'),
        backgroundColor: value ? const Color(0xFF34A853) : const Color(0xFFEA4335),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Security & Privacy',
          style: TextStyle(
            color: Color(0xFF333333),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Color(0xFF1A73E8)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AUTHENTICATION',
              style: TextStyle(
                color: Color(0xFF666666),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            _buildSecurityCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A73E8).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.security_rounded, color: Color(0xFF1A73E8)),
                    ),
                    title: const Text('Two-Factor Authentication (2FA)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF333333))),
                    subtitle: const Text('Protect withdrawals & changes', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
                    trailing: Switch(
                      value: _is2faEnabled,
                      onChanged: _toggle2FA,
                      activeColor: const Color(0xFF1A73E8),
                    ),
                  ),
                  const Divider(color: Color(0xFFEEEEEE), height: 32),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A73E8).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.password_rounded, color: Color(0xFF1A73E8)),
                    ),
                    title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF333333))),
                    subtitle: const Text('Last changed 30 days ago', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFCCCCCC)),
                    onTap: () {
                      // Navigate to password change
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'DEVICE MANAGEMENT',
              style: TextStyle(
                color: Color(0xFF666666),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            _buildSecurityCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34A853).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.phone_iphone_rounded, color: Color(0xFF34A853)),
                    ),
                    title: const Text('Current Device', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF333333))),
                    subtitle: const Text('Windows Desktop (Active)', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
                    trailing: const Text('NOW', style: TextStyle(color: Color(0xFF34A853), fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  const Divider(color: Color(0xFFEEEEEE), height: 32),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF666666).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.laptop_mac_rounded, color: Color(0xFF666666)),
                    ),
                    title: const Text('MacBook Pro', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF333333))),
                    subtitle: const Text('Bangkok, Thailand', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
                    trailing: TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session revoked.')));
                      },
                      child: const Text('REVOKE', style: TextStyle(color: Color(0xFFEA4335), fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: child,
    );
  }
}
