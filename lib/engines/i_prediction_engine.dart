import 'package:golden_p/models/history_entry.dart';

/// มาตรฐานกลางสำหรับ Engine พยากรณ์ทั้งหมด
/// เพื่อให้ง่ายต่อการดูแลรักษา (Maintainability) และสลับเปลี่ยน (Polymorphism)
abstract class IPredictionEngine {
  /// ชื่อของ Engine
  String get name;

  /// เวอร์ชันของ Engine
  String get version;

  /// เมธอดหลักสำหรับการพยากรณ์
  /// ต้องรับข้อมูลประวัติ (history) และส่งคืนค่าความน่าจะเป็นของแต่ละตัวเลือก (A, B, C)
  Map<String, double> predictProbs(List<HistoryEntry> history);
}
