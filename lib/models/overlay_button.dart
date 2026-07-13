import 'package:flutter/material.dart';

class OverlayButtonModel {
  final String id; // Ma, Mb, Mc, M0, M1, M2, M3, M4, M5
  final String label; // ชื่อ
  final Color color; // สีปุ่ม
  Offset position; // ตำแหน่ง (x, y)
  bool isRecording; // กำลังบันทึกตำแหน่งอยู่
  int stepNumber; // ลำดับที่ใช้ใน sequence ปัจจุบัน หรือ 0 ถ้าไม่ได้ใช้
  final String type; // 'webview_click' หรือ 'predictor'
  final String? predictorValue; // 'A', 'B', or 'C' (เฉพาะ type: predictor)
  int delayMs; // ระยะเวลาหน่วงก่อนกดปุ่มถัดไป (ms)

  OverlayButtonModel({
    required this.id,
    required this.label,
    required this.color,
    this.type = 'webview_click',
    this.predictorValue,
    this.delayMs = 500,
    Offset? position,
    this.isRecording = false,
    this.stepNumber = 0,
  }) : position = position ?? const Offset(0, 0);

  // สำหรับ Serialization (บันทึก/โหลดจาก SharedPreferences)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'color': color.toARGB32(),
      'posX': position.dx,
      'posY': position.dy,
      'stepNumber': stepNumber,
      'type': type,
      'predictorValue': predictorValue,
      'delayMs': delayMs,
    };
  }

  factory OverlayButtonModel.fromJson(Map<String, dynamic> json) {
    return OverlayButtonModel(
      id: json['id'] as String,
      label: json['label'] as String,
      color: Color(json['color'] as int),
      position: Offset(
        (json['posX'] as num).toDouble(),
        (json['posY'] as num).toDouble(),
      ),
      stepNumber: (json['stepNumber'] as int?) ?? 0,
      type: (json['type'] as String?) ?? 'webview_click',
      predictorValue: json['predictorValue'] as String?,
      delayMs: (json['delayMs'] as int?) ?? 500,
    );
  }

  OverlayButtonModel copyWith({
    String? id,
    String? label,
    Color? color,
    Offset? position,
    bool? isRecording,
    int? stepNumber,
    String? type,
    String? predictorValue,
    int? delayMs,
  }) {
    return OverlayButtonModel(
      id: id ?? this.id,
      label: label ?? this.label,
      color: color ?? this.color,
      position: position ?? this.position,
      isRecording: isRecording ?? this.isRecording,
      stepNumber: stepNumber ?? this.stepNumber,
      type: type ?? this.type,
      predictorValue: predictorValue ?? this.predictorValue,
      delayMs: delayMs ?? this.delayMs,
    );
  }
}

// ชุดปุ่มเริ่มต้น
final List<OverlayButtonModel> defaultOverlayButtons = [
  // WebView Logic Markers (M0-M5)
  OverlayButtonModel(id: 'M0', label: 'M0', color: const Color(0xFF9C27B0)),
  OverlayButtonModel(id: 'M1', label: 'M1', color: const Color(0xFFF44336)),
  OverlayButtonModel(id: 'M2', label: 'M2', color: const Color(0xFF00BCD4)),
  OverlayButtonModel(id: 'M3', label: 'M3', color: const Color(0xFF8BC34A)),
];
