import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Model สำหรับเก็บข้อมูลของแต่ละ Tab
class WebViewTab {
  final String id;
  String title;
  String url;
  bool isLoading;
  double progress;
  bool isSecure;
  InAppWebViewController? controller;
  final TextEditingController urlController;
  final FocusNode urlFocusNode;

  WebViewTab({
    required this.id,
    required this.url,
    this.title = 'New Tab',
    this.isLoading = false,
    this.progress = 0,
    this.isSecure = false,
    this.controller,
  }) : urlController = TextEditingController(text: url),
       urlFocusNode = FocusNode();

  void dispose() {
    urlController.dispose();
    urlFocusNode.dispose();
  }
}
