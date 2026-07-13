import 'package:flutter/material.dart';

class SignalsView extends StatelessWidget {
  const SignalsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text('Live Signals', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        children: [
          _buildSignalCard(
            confidence: '98.5%',
            pattern: 'A-B-A',
            recommendation: 'STRONG BUY (B)',
            statusColor: const Color(0xFF10B981),
            timestamp: 'Just now',
          ),
          _buildSignalCard(
            confidence: '82.0%',
            pattern: 'C-C-A',
            recommendation: 'WAIT',
            statusColor: const Color(0xFFF59E0B),
            timestamp: '5 mins ago',
          ),
          _buildSignalCard(
            confidence: '95.2%',
            pattern: 'B-A-B',
            recommendation: 'BUY (A)',
            statusColor: const Color(0xFF3B82F6),
            timestamp: '15 mins ago',
          ),
        ],
      ),
    );
  }

  Widget _buildSignalCard({
    required String confidence,
    required String pattern,
    required String recommendation,
    required Color statusColor,
    required String timestamp,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 0,
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.radar_rounded, color: statusColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Confidence: $confidence',
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              Text(
                timestamp,
                style: const TextStyle(color: Color(0xFF5F6368), fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF2D3748)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pattern Detected', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(pattern, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('AI Recommendation', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                    child: Text(recommendation, style: TextStyle(color: statusColor, fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
