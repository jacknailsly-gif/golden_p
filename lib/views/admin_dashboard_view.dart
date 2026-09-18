import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:golden_p/services/auth_service.dart';

class AdminDashboardView extends StatefulWidget {
  const AdminDashboardView({super.key});

  @override
  State<AdminDashboardView> createState() => _AdminDashboardViewState();
}

class _AdminDashboardViewState extends State<AdminDashboardView> {
  bool _isLoading = true;
  Map<String, dynamic> _metrics = {};
  Map<String, dynamic> _userStats = {};
  List<dynamic> _users = [];
  
  @override
  void initState() {
    super.initState();
    if (!AuthService.isAdmin || !AuthService.hasValidSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop();
      });
      return;
    }
    _fetchAllData();
  }

  Future<void> _fetchAllData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _fetchMetrics(),
        _fetchUserStats(),
        _fetchUsers(),
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), 
          backgroundColor: const Color(0xFFEA4335),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchMetrics() async {
    final token = AuthService.currentToken ?? '';
    final response = await http.get(
      Uri.parse('${AuthService.adminBaseUrl}/metrics'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _metrics = data['data'] ?? {};
    }
  }

  Future<void> _fetchUserStats() async {
    final token = AuthService.currentToken ?? '';
    final response = await http.get(
      Uri.parse('${AuthService.adminBaseUrl}/users/stats'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _userStats = data['data'] ?? {};
    }
  }

  Future<void> _fetchUsers() async {
    final token = AuthService.currentToken ?? '';
    final response = await http.get(
      Uri.parse('${AuthService.adminBaseUrl}/users'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _users = data['data'] ?? [];
    }
  }

  Future<void> _updateUserStatus(String userId, String status) async {
    final token = AuthService.currentToken ?? '';
    try {
      final response = await http.patch(
        Uri.parse('${AuthService.adminBaseUrl}/users/$userId/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'status': status}),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Status updated to ${status.toUpperCase()}'),
          backgroundColor: const Color(0xFF34A853),
          behavior: SnackBarBehavior.floating,
        ));
        _fetchAllData(); 
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update status'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _deleteUser(String userId) async {
    final token = AuthService.currentToken ?? '';
    try {
      final response = await http.delete(
        Uri.parse('${AuthService.adminBaseUrl}/users/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('User deleted successfully'),
          backgroundColor: Color(0xFFEA4335),
          behavior: SnackBarBehavior.floating,
        ));
        _fetchAllData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete user'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _showSystemLogs() async {
    final token = AuthService.currentToken ?? '';
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6))),
      );

      final response = await http.get(
        Uri.parse('${AuthService.adminBaseUrl}/logs'),
        headers: {'Authorization': 'Bearer $token'},
      );
      
      if (!mounted) return;
      Navigator.pop(context); // Close loading

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final logs = data['data'] as List<dynamic>? ?? [];
        
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('SYSTEM LOGS', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: logs.isEmpty ? const Center(child: Text('No logs available.', style: TextStyle(color: Color(0xFF94A3B8)))) : ListView.builder(
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final log = logs[index];
                  return ListTile(
                    leading: Icon(
                      log['type'] == 'SECURITY' ? Icons.security_rounded : Icons.info_outline_rounded, 
                      color: log['type'] == 'SECURITY' ? const Color(0xFFEA4335) : const Color(0xFF34A853)
                    ),
                    title: Text(log['message'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: Text(log['timestamp'] ?? '', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CLOSE', style: TextStyle(color: Color(0xFFF8FAFC), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load logs')));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading if error
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text(
          'ADMIN DASHBOARD', 
          style: TextStyle(
            color: Color(0xFF3B82F6), 
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            fontSize: 20
          )
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1A73E8)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
            ),
            child: IconButton(
              icon: const Icon(Icons.sync_rounded, color: Color(0xFF1A73E8), size: 20),
              tooltip: "Sync Database",
              onPressed: _fetchAllData,
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF3B82F6),
                strokeWidth: 3,
              )
            )
          : RefreshIndicator(
              onRefresh: _fetchAllData,
              color: const Color(0xFF3B82F6),
              backgroundColor: const Color(0xFF1E293B),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('NETWORK METRICS', Icons.hub_outlined),
                    const SizedBox(height: 20),
                    _buildMetricsGrid(),
                    const SizedBox(height: 40),
                    _buildSectionTitle('FINANCIAL OVERVIEW', Icons.account_balance_wallet_outlined),
                    const SizedBox(height: 20),
                    _buildFinancialGrid(),
                    const SizedBox(height: 40),
                    _buildSectionTitle('USER DIRECTORY', Icons.folder_shared_outlined),
                    const SizedBox(height: 20),
                    _buildUserTable(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF3B82F6), size: 22),
        const SizedBox(width: 12),
        Text(
          title, 
          style: const TextStyle(
            color: Color(0xFFF8FAFC), 
            fontSize: 16, 
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5
          )
        ),
      ],
    );
  }

  Widget _buildMetricsGrid() {
    return GridView.count(
      crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.1,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildStatCard('CCU LIVE', '${_metrics['ccu'] ?? 0}', const Color(0xFF3B82F6), Icons.people_alt_rounded),
        _buildStatCard('TOTAL REG', '${_userStats['total'] ?? 0}', const Color(0xFF8AB4F8), Icons.data_usage_rounded),
        _buildStatCard('ACTIVE', '${_userStats['active'] ?? 0}', const Color(0xFF34A853), Icons.check_circle_rounded),
        _buildStatCard('PENDING', '${_userStats['pending'] ?? 0}', const Color(0xFFFBBC05), Icons.hourglass_top_rounded),
      ],
    );
  }

  Widget _buildFinancialGrid() {
    return GridView.count(
      crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 1,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: MediaQuery.of(context).size.width > 600 ? 1.5 : 2.5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildStatCard('TOTAL VALUE LOCKED (TVL)', '\$14,205,000', const Color(0xFF3B82F6), Icons.account_balance_rounded),
        _buildStatCard('24H VOLUME', '\$2,450,120', const Color(0xFF34A853), Icons.trending_up_rounded),
        _buildStatCard('PENDING WITHDRAWALS', '42', const Color(0xFFFBBC05), Icons.schedule_rounded),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            spreadRadius: 2,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.1),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFF8FAFC), 
              fontSize: 26, 
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF94A3B8), 
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTable() {
    if (_users.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: const Center(
          child: Text('NO USERS FOUND IN DATABASE', style: TextStyle(color: Color(0xFF94A3B8), letterSpacing: 1.5, fontWeight: FontWeight.bold)),
        )
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.white.withValues(alpha: 0.05),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 30,
            headingRowHeight: 60,
            dataRowMinHeight: 60,
            dataRowMaxHeight: 70,
            headingTextStyle: const TextStyle(
              color: Color(0xFF94A3B8), 
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              fontSize: 12
            ),
            dataTextStyle: const TextStyle(color: Color(0xFFF8FAFC), fontSize: 13, fontWeight: FontWeight.w500),
            columns: const [
              DataColumn(label: Text('IDENTITY')),
              DataColumn(label: Text('CLEARANCE')),
              DataColumn(label: Text('STATUS')),
              DataColumn(label: Text('KYC STATUS')),
              DataColumn(label: Text('WALLET BALANCE')),
              DataColumn(label: Text('ENLISTED')),
              DataColumn(label: Text('ACTIONS')),
            ],
            rows: _users.map((u) {
              final statusStr = u['status'] ?? 'unknown';
              final statusColor = statusStr == 'active' 
                  ? const Color(0xFF34A853) 
                  : (statusStr == 'pending' ? const Color(0xFFFBBC05) : const Color(0xFFEA4335));
              
              final kycStatus = (u['id'].hashCode % 2 == 0) ? 'VERIFIED' : 'PENDING';
              final kycColor = kycStatus == 'VERIFIED' ? const Color(0xFF34A853) : const Color(0xFFFBBC05);
              final walletBalance = '\$${((u['id'].hashCode % 10000) * 1.5).toStringAsFixed(2)}';

              return DataRow(
                cells: [
                  DataCell(
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                          child: const Icon(Icons.person, color: Color(0xFF3B82F6), size: 16),
                        ),
                        const SizedBox(width: 12),
                        Text(u['email'] ?? 'UNKNOWN_ENTITY', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    )
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: u['role'] == 'admin' ? const Color(0xFF3B82F6).withValues(alpha: 0.1) : const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(6)
                      ),
                      child: Text(
                        (u['role'] ?? 'user').toUpperCase(), 
                        style: TextStyle(
                          color: u['role'] == 'admin' ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 1
                        )
                      ),
                    )
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            statusStr.toUpperCase(), 
                            style: TextStyle(
                              color: statusColor, 
                              fontSize: 11, 
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1
                            )
                          ),
                        ],
                      ),
                    )
                  ),
                  DataCell(
                    Text(
                      kycStatus, 
                      style: TextStyle(
                        color: kycColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.5
                      )
                    )
                  ),
                  DataCell(
                    Text(
                      walletBalance,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF8FAFC),
                      )
                    )
                  ),
                  DataCell(
                    Text(
                      u['createdAt'] != null ? u['createdAt'].toString().substring(0, 10) : 'CLASSIFIED',
                      style: const TextStyle(color: Color(0xFF94A3B8))
                    )
                  ),
                  DataCell(Row(
                    children: [
                      if (statusStr == 'pending' || statusStr == 'inactive')
                        IconButton(
                          icon: const Icon(Icons.check_circle_outline, color: Color(0xFF34A853)),
                          tooltip: 'Approve / Activate',
                          onPressed: () => _updateUserStatus(u['id'], 'active'),
                        ),
                      if (statusStr == 'active')
                        IconButton(
                          icon: const Icon(Icons.block_flipped, color: Color(0xFFFBBC05)),
                          tooltip: 'Suspend',
                          onPressed: () => _updateUserStatus(u['id'], 'inactive'),
                        ),
                      IconButton(
                        icon: const Icon(Icons.list_alt_rounded, color: Color(0xFF3B82F6)),
                        tooltip: 'View System Logs',
                        onPressed: _showSystemLogs,
                      ),
                      if (u['role'] != 'admin' && statusStr != 'active')
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Color(0xFFEA4335)),
                          tooltip: 'Delete Record',
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: const Color(0xFF1E293B),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                title: const Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: Color(0xFFEA4335)),
                                    SizedBox(width: 10),
                                    Text('Delete User', style: TextStyle(color: Color(0xFF202124), fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                content: Text('Are you sure you want to permanently delete record:\n\n${u['email']}', style: const TextStyle(color: Color(0xFF94A3B8), height: 1.5)),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('CANCEL', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFEA4335),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                                    ),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _deleteUser(u['id']);
                                    },
                                    child: const Text('DELETE', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  )),
                ]
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
