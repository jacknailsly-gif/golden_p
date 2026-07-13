/*
สำคัญ: กฎการทำนายของ AI

Error Memory (หน่วยจำความผิดพลาด)
- เก็บ context ที่ทำนายผิด, ค่าที่ทำนาย, ค่าจริง และกฎที่ใช้
- ครั้งต่อไปถ้า context เหมือนเดิม → ลดคะแนน prediction เดิมลงอย่างหนัก (penalty)

Meta-Reasoning (การใช้ความผิดพลาดเดิมมาปรับการตัดสินใจ)
- ถ้าลักษณะการทำนายเคยผิดมาก่อนใน context คล้ายกัน → ลดน้ำหนัก prediction นั้น

Dynamic Weighting (การปรับน้ำหนักตามสถานการณ์)
- ถ้าทำนายผิดติดกันหลายครั้ง → ลดน้ำหนักตัวเลือกนั้นลง (เช่น -50%)
- ถ้าทำนายถูกติดกัน 3+ ครั้ง → เพิ่มน้ำหนัก prediction (+40%)

Loop Protection (ป้องกันการติดลูปผิดซ้ำๆ)
- ถ้าผิด pattern เดิมเกิน 3 ครั้ง → reset หน่วยความจำบางส่วน + ลด momentum เพื่อหลีกเลี่ยงลูป

Streak Mode (โหมดต่อเนื่อง)
- ถ้าทำนายถูกต่อเนื่องหลายครั้ง → จะ boost prediction เดิมให้มีคะแนนสูงขึ้น

Pattern Recognition (การจดจำรูปแบบ)
- เรียนรู้ pattern จาก sequence ยาวๆ เช่น LSTM, Markov, context-based, auto-learned patterns
- เก็บไว้ในหน่วยความจำ แล้วใช้คะแนน pattern เพื่อช่วยเลือกตัวถัดไป

Bayesian Prediction
- ใช้ความน่าจะเป็นตาม context ล่าสุด เพื่อเลือกตัวถัดไป

Reinforcement Learning (Q-Learning)
- ใช้ค่า reward (+1 ถูก, -1 ผิด, ปรับเพิ่ม/ลดตาม streaks) อัปเดต Q-Table
- ปรับ learning rate ตาม accuracy และจำนวนครั้งที่ผิดติดกัน

Safety Valve (วาล์วนิรภัย)
- ถ้าตัวเลือกทั้งหมดโดนห้ามทำนาย (forbidden) → จะ reset การห้ามเหลือแค่ตัวที่ผิดล่าสุด เพื่อป้องกัน deadlock
- ถ้ายังไม่มีตัวเลือกเลย → เลือกสุ่ม 1 ตัวแทน

Reset System
- มีฟังก์ชัน reset() สำหรับล้างหน่วยความจำและค่าเรียนรู้ทั้งหมด กลับสู่สภาพเริ่มต้น

🔹 กฎพิเศษ
Special Pattern Rules เช่น
- ถ้าเห็น "AB" → เดาตัวถัดไปเป็น "C"
- ถ้าเห็น "CA" → เดาตัวถัดไปเป็น "B"
(แต่บางส่วนถูกปิดไว้/คอมเมนต์ ไม่ได้ใช้งานจริง)

Auto-Learned Patterns → ระบบจะสร้างกฎใหม่จากข้อมูลที่เล่นจริงๆ

Continuity Factor → ถ้า input ต่อเนื่องซ้ำๆ มาก → จะปรับ factor ใน Q-Learning

🔹 วิธีตัดสินใจขั้นสุดท้าย
- รวมคะแนนจากทุกโมเดลด้วย dynamic weights
- ปรับด้วย error memory, penalties, dynamic adjustments
- ห้ามใช้ค่าที่อยู่ใน forbidden predictions
- เลือกตัวที่มีคะแนนสูงสุด → ถ้าคะแนนสูสีก็ใช้ confidence คำนวณ
- ถ้าไม่มีตัวเลือก → เลือกสุ่ม
*/
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_p/services/local_storage_service.dart';
import 'package:golden_p/utils/app_theme.dart';
import 'package:golden_p/views/splash_view.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:golden_p/services/security_service.dart';
import 'dart:io';
import 'package:golden_p/viewmodels/sequence_analyzer_viewmodel.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/providers/websocket_provider.dart';

// Auto-connect to WebSocket Backend on app start
class WebSocketInitializer extends ConsumerWidget {
  final Widget child;
  const WebSocketInitializer({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(websocketServiceProvider);
    return child;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalStorageService.init();

  // เปิดใช้งานความปลอดภัย
  await SecurityService.checkSecurity();

  // หน้าจอไม่ดับ และ ป้องกัน screenshot
  if (Platform.isAndroid) {
    await FlutterWindowManagerPlus.addFlags(
      FlutterWindowManagerPlus.FLAG_SECURE |
          FlutterWindowManagerPlus.FLAG_KEEP_SCREEN_ON,
    );
  }

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => SequenceAnalyzerViewModel()),
        ChangeNotifierProvider(create: (context) => OverlayButtonsViewModel()),
      ],
      child: WebSocketInitializer(
        child: MaterialApp(
          title: 'Midnight Azure',
          theme: AppTheme.darkTheme,
          home: const SplashView(),
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
