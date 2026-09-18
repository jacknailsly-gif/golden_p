import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:golden_p/viewmodels/sequence_analyzer_viewmodel.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/models/history_entry.dart';
import 'package:golden_p/models/webview_tab.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/widgets/overlay_buttons_panel.dart';

// ─── Midnight Azure Dark Theme Colors ───
class ChromeColors {
  static const Color tabBarBg = Color(0xFF0F172A); // Dark background
  static const Color activeTab = Color(0xFF1E293B); // Surface for active tab
  static const Color addressBarBg = Color(0xFF0F172A); // Dark address bar
  static const Color textPrimary = Color(0xFFF8FAFC); // White text
  static const Color textSecondary = Color(0xFF94A3B8); // Grey text
  static const Color iconColor = Color(0xFF94A3B8);
  static const Color iconHover = Color(0xFF3B82F6); // Azure Blue hover
  static const Color progressBar = Color(0xFF3B82F6); // Azure Blue progress
  static const Color divider = Color(0xFF1E293B);
  static const Color tabCloseBg = Color(0xFF1E293B);
}

class SequenceAnalyzerView extends StatefulWidget {
  final GameMode gameMode;

  const SequenceAnalyzerView({
    super.key,
    this.gameMode = GameMode.towers,
  });

  @override
  State<SequenceAnalyzerView> createState() => _SequenceAnalyzerViewState();
}

class _SequenceAnalyzerViewState extends State<SequenceAnalyzerView> {
  // ─── Dedicated ViewModel per GameMode (History & Balance 100% Isolated) ───
  late final SequenceAnalyzerViewModel _viewModel;

  // ─── Tab Management ───
  final List<WebViewTab> _tabs = [];
  int _currentTabIndex = 0;
  int _tabCounter = 1;
  final GlobalKey _webViewKey = GlobalKey(); // สำหรับวัดตำแหน่ง WebView

  // V123: Auto-start flag
  bool _autoStarted = false;

  // Get current tab
  WebViewTab get _currentTab => _tabs[_currentTabIndex];

  @override
  void initState() {
    super.initState();
    _viewModel = SequenceAnalyzerViewModel(gameMode: widget.gameMode);
    // Create initial tab with GameMode default URL
    _createNewTab(widget.gameMode.defaultUrl);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Update offset after the route transition completes to ensure accurate coordinates
    ModalRoute.of(context)?.animation?.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _updateWebViewOffset();
      }
    });
  }

  @override
  void dispose() {
    for (var tab in _tabs) {
      tab.dispose();
    }
    _viewModel.dispose();
    super.dispose();
  }

  // ─── Create New Tab ───
  void _createNewTab([String? initialUrl]) {
    final tab = WebViewTab(
      id: 'tab_${DateTime.now().millisecondsSinceEpoch}_${_tabCounter++}',
      url: initialUrl ?? widget.gameMode.defaultUrl,
    );

    // Add focus listener for URL bar
    tab.urlFocusNode.addListener(() {
      if (mounted) {
        setState(() {
          if (tab.urlFocusNode.hasFocus) {
            tab.urlController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: tab.urlController.text.length,
            );
          }
        });
      }
    });

    setState(() {
      _tabs.add(tab);
      _currentTabIndex = _tabs.length - 1;
      _updateWebViewOffset();
    });
  }

  // ─── Close Tab ───
  void _closeTab(int index) {
    if (_tabs.length <= 1) {
      // Don't close the last tab, just reset it
      _tabs[0].controller?.loadUrl(
        urlRequest: URLRequest(url: WebUri("about:blank")),
      );
      return;
    }

    setState(() {
      _tabs[index].dispose();
      _tabs.removeAt(index);

      // Adjust current index if needed
      if (_currentTabIndex >= index && _currentTabIndex > 0) {
        _currentTabIndex--;
      }
      if (_currentTabIndex >= _tabs.length) {
        _currentTabIndex = _tabs.length - 1;
      }
      _updateWebViewOffset();
    });
  }

  // ─── Switch to Tab ───
  void _switchToTab(int index) {
    if (index >= 0 && index < _tabs.length) {
      setState(() {
        _currentTabIndex = index;
        _updateWebViewOffset();
      });
      _bindActiveTabControllers();
    }
  }

  void _bindActiveTabControllers() {
    if (!mounted || _tabs.isEmpty) return;
    final controller = _currentTab.controller;
    if (controller == null) return;
    final overlayViewModel = Provider.of<OverlayButtonsViewModel>(
      context,
      listen: false,
    );
    _viewModel.setWebViewController(controller, mode: widget.gameMode);
    overlayViewModel.setWebViewController(controller, mode: widget.gameMode);
    overlayViewModel.setSequenceAnalyzerViewModel(_viewModel, mode: widget.gameMode);
    _updateWebViewOffset();
  }

  // ─── Chrome Tab Bar ───
  Widget _buildTabBar() {
    return Container(
      height: 40,
      color: ChromeColors.tabBarBg,
      child: Row(
        children: [
          // Scrollable tabs
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              itemBuilder: (context, index) {
                final tab = _tabs[index];
                final isActive = index == _currentTabIndex;

                return GestureDetector(
                  onTap: () => _switchToTab(index),
                  child: Container(
                    width: 160,
                    margin: const EdgeInsets.only(left: 4, top: 4, right: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isActive
                          ? ChromeColors.activeTab
                          : ChromeColors.tabBarBg,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                      border: isActive
                          ? Border(
                              top: BorderSide(
                                color: ChromeColors.progressBar.withValues(
                                  alpha: 0.6,
                                ),
                                width: 2,
                              ),
                            )
                          : null,
                    ),
                    child: Row(
                      children: [
                        // Favicon placeholder or loading indicator
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: tab.isLoading && isActive
                              ? CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: ChromeColors.progressBar,
                                )
                              : Icon(
                                  tab.isSecure
                                      ? Icons.lock_rounded
                                      : Icons.public,
                                  size: 14,
                                  color: ChromeColors.textSecondary,
                                ),
                        ),
                        const SizedBox(width: 8),
                        // Tab title
                        Expanded(
                          child: Text(
                            tab.title,
                            style: TextStyle(
                              color: isActive
                                  ? ChromeColors.textPrimary
                                  : ChromeColors.textSecondary,
                              fontSize: 12,
                              fontWeight: isActive
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Close button
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _closeTab(index),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: isActive
                                    ? ChromeColors.textPrimary
                                    : ChromeColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // New Tab button
          _buildNavButton(
            icon: Icons.add_rounded,
            tooltip: 'New Tab',
            onPressed: () => _createNewTab(),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  // ─── Chrome Omnibox Address Bar ───
  Widget _buildChromeAddressBar() {
    final tab = _currentTab;

    return Container(
      color: ChromeColors.activeTab,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Back button
              _buildNavButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onPressed: () => tab.controller?.goBack(),
              ),
              // Forward button
              _buildNavButton(
                icon: Icons.arrow_forward_rounded,
                tooltip: 'Forward',
                onPressed: () => tab.controller?.goForward(),
              ),
              // Reload / Stop button
              _buildNavButton(
                icon: tab.isLoading
                    ? Icons.close_rounded
                    : Icons.refresh_rounded,
                tooltip: tab.isLoading ? 'Stop' : 'Reload',
                onPressed: () {
                  if (tab.isLoading) {
                    tab.controller?.stopLoading();
                  } else {
                    tab.controller?.reload();
                  }
                },
              ),
              const SizedBox(width: 4),
              // Omnibox
              Expanded(
                child: Container(
                  height: 34,
                  decoration: BoxDecoration(
                    color: ChromeColors.addressBarBg,
                    borderRadius: BorderRadius.circular(20),
                    border: tab.urlFocusNode.hasFocus
                        ? Border.all(
                            color: ChromeColors.progressBar.withValues(
                              alpha: 0.6,
                            ),
                            width: 1.5,
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      // Security icon
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Icon(
                          tab.isSecure
                              ? Icons.lock_rounded
                              : Icons.info_outline_rounded,
                          size: 16,
                          color: ChromeColors.textSecondary,
                        ),
                      ),
                      // URL field
                      Expanded(
                        child: TextField(
                          controller: tab.urlController,
                          focusNode: tab.urlFocusNode,
                          style: const TextStyle(
                            color: ChromeColors.textPrimary,
                            fontSize: 14,
                          ),
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 0,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            hintText: 'Search or type URL',
                            hintStyle: TextStyle(
                              color: ChromeColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          onSubmitted: (url) {
                            if (!url.startsWith('http://') &&
                                !url.startsWith('https://')) {
                              url = 'https://$url';
                            }
                            tab.controller?.loadUrl(
                              urlRequest: URLRequest(url: WebUri(url)),
                            );
                            tab.urlFocusNode.unfocus();
                          },
                        ),
                      ),
                      // Clear button (only when focused)
                      if (tab.urlFocusNode.hasFocus)
                        GestureDetector(
                          onTap: () => tab.urlController.clear(),
                          child: const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: ChromeColors.textSecondary,
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Menu button
              _buildNavButton(
                icon: Icons.more_vert_rounded,
                tooltip: 'More',
                onPressed: () {},
              ),
            ],
          ),
          // Progress bar
          if (tab.isLoading)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: tab.progress > 0 ? tab.progress : null,
                  backgroundColor: Colors.transparent,
                  color: ChromeColors.progressBar,
                  minHeight: 2.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Navigation Button Helper ───
  Widget _buildNavButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 20, color: ChromeColors.iconColor),
          ),
        ),
      ),
    );
  }

  // ─── Title Bar ───
  Widget _buildTitleBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      color: ChromeColors.tabBarBg,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Text(
              widget.gameMode.fullTitle,
              style: const TextStyle(
                color: Color(0xFF3B82F6), // Azure Blue
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Positioned(
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF3B82F6), size: 20),
              onPressed: () {
                // Ensure bot stops when going back
                final overlayViewModel = Provider.of<OverlayButtonsViewModel>(context, listen: false);
                if (overlayViewModel.isSequenceRunning) {
                  overlayViewModel.toggleSequence();
                }
                Navigator.of(context).pop();
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  void _updateWebViewOffset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final RenderBox? renderBox =
          _webViewKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final offset = renderBox.localToGlobal(Offset.zero);
        final overlayViewModel = Provider.of<OverlayButtonsViewModel>(
          context,
          listen: false,
        );
        overlayViewModel.setWebViewOffset(offset);
        debugPrint('WebView Offset Updated: $offset');
      }
    });
  }

  // ─── Build WebView for Current Tab ───
  Widget _buildWebView(SequenceAnalyzerViewModel viewModel) {
    // Show blocking overlay if WebView is locked
    if (viewModel.isWebViewLocked) {
      // Get overall highest balance from all tracked coins
      String highestBalance = viewModel.overallHighestBalance ?? '0';
      String highestCoin = viewModel.overallHighestCoin ?? '';

      return Container(
        color: Colors.black.withValues(alpha: 0.8),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 80, color: Colors.red[600]),
              const SizedBox(height: 20),
              Text(
                'WebView Locked',
                style: TextStyle(
                  color: Colors.red[600],
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Balance dropped below -0.31%',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 5),
              Text(
                'Highest balance was: $highestCoin $highestBalance',
                style: TextStyle(
                  color: Colors.amber[300]!,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red[400]!),
                ),
                child: Column(
                  children: [
                    Text(
                      'Auto-restart in:',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Consumer<SequenceAnalyzerViewModel>(
                      builder: (context, vm, _) {
                        final remainingSeconds = vm.remainingLockSeconds;
                        final minutes = remainingSeconds ~/ 60;
                        final seconds = remainingSeconds % 60;
                        return Text(
                          '$minutes:${seconds.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: Colors.red[400],
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      key: _webViewKey,
      child: IndexedStack(
        index: _currentTabIndex,
        children: _tabs.map((t) {
          return InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(t.url)),
            initialSettings: InAppWebViewSettings(
              useShouldOverrideUrlLoading: true,
              useWideViewPort: false,
              loadWithOverviewMode: false,
              supportZoom: false,
            ),
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final url = navigationAction.request.url;
              if (url == null) {
                return NavigationActionPolicy.ALLOW;
              }

              final currentUri = Uri.tryParse(t.url);
              final newUri = Uri.tryParse(url.toString());

              if (currentUri != null && newUri != null) {
                final currentHost = currentUri.host;
                final newHost = newUri.host;

                // ถ้า domain ไม่เหมือนกัน ให้เปิด Tab ใหม่
                if (currentHost.isNotEmpty &&
                    newHost.isNotEmpty &&
                    currentHost != newHost) {
                  // เปิด Tab ใหม่ด้วย URL นี้
                  _createNewTab(url.toString());
                  // ยกเลิกการ navigation ใน Tab ปัจจุบัน
                  return NavigationActionPolicy.CANCEL;
                }
              }

              return NavigationActionPolicy.ALLOW;
            },
            onWebViewCreated: (controller) {
              t.controller = controller;
              if (t == _currentTab) {
                _bindActiveTabControllers();
              }

              // Add a handler to receive click events from JavaScript
              controller.addJavaScriptHandler(
                handlerName: 'webViewClick',
                callback: (args) {
                  viewModel.updateBalance();
                },
              );
            },
            onLoadStart: (controller, url) {
              if (url != null && mounted) {
                setState(() {
                  t.isLoading = true;
                  t.isSecure = url.scheme == "https";
                  t.url = url.toString();
                  if (!t.urlFocusNode.hasFocus) {
                    t.urlController.text = t.url;
                  }
                });
              }
            },
            onLoadStop: (controller, url) async {
              if (url != null && mounted) {
                // Get page title
                String? title;
                try {
                  title = await controller.getTitle();
                } catch (_) {}

                setState(() {
                  t.isLoading = false;
                  t.progress = 0;
                  t.url = url.toString();
                  t.title = title ?? t.url;
                  if (!t.urlFocusNode.hasFocus) {
                    t.urlController.text = t.url;
                  }
                });

                // Inject a global click listener and apply native viewport scaling
                if (!mounted) return;
                final overlayVM = Provider.of<OverlayButtonsViewModel>(
                  context,
                  listen: false,
                );
                final zoom = overlayVM.webViewTextZoom;

                // Auto-start bot on launch for Towers
                if (!_autoStarted &&
                    widget.gameMode == GameMode.towers &&
                    t.url.contains('faucetpay.io/play/towers')) {
                  _autoStarted = true;
                  debugPrint('[AUTO-START] 🚀 Auto-starting Towers bot in 5 seconds...');
                  Future.delayed(const Duration(seconds: 5), () async {
                    if (mounted) {
                      debugPrint('[AUTO-START] 🔧 Ensuring Towers difficulty is Medium (Level 7: 42%)...');
                      await overlayVM.ensureDifficulty(mode: GameMode.towers);
                      
                      await Future.delayed(const Duration(seconds: 2));
                      if (mounted && !overlayVM.isRunningForMode(GameMode.towers)) {
                        debugPrint('[AUTO-START] 🟢 Executing Auto-Start for Towers!');
                        overlayVM.startSequence(mode: GameMode.towers);
                      }
                    }
                  });
                }


                controller.evaluateJavascript(
                  source:
                      """
                  if (!window.__goldenPClickHookInstalled) {
                    window.__goldenPClickHookInstalled = true;
                    window.addEventListener('click', function() {
                      window.flutter_inappwebview.callHandler('webViewClick');
                    });
                  }
                  var scale = $zoom / 100;
                  var meta = document.querySelector('meta[name="viewport"]');
                  if (meta) meta.remove();
                  var m = document.createElement('meta');
                  m.name = 'viewport';
                  m.content = 'width=device-width, initial-scale=1, maximum-scale=1, minimum-scale=1, user-scalable=no, shrink-to-fit=no';
                  document.head.appendChild(m);
                  // Optional: Disable scrolling to lock layout
                  document.body.style.overscrollBehavior = 'none';
                  document.documentElement.style.overscrollBehavior = 'none';
                  
                  // Clean up old CSS zoom if any from previous versions
                  var oldStyle = document.getElementById('golden-zoom-style');
                  if (oldStyle) oldStyle.remove();
                """,
                );
              }
            },
            onProgressChanged: (controller, progress) {
              if (mounted) {
                setState(() {
                  t.progress = progress / 100;
                });
              }
            },
            onUpdateVisitedHistory: (controller, url, isReload) {
              if (url != null && mounted) {
                setState(() {
                  t.url = url.toString();
                  t.urlController.text = t.url;
                });
              }
            },
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: ChromeColors.tabBarBg,
          body: SafeArea(
            child: Stack(
              children: [
                // Main Content Column
                Column(
                  children: [
                    _buildTitleBar(), // Always clickable!
                    Expanded(
                      child: Consumer<OverlayButtonsViewModel>(
                        builder: (context, overlayViewModel, _) {
                          return AbsorbPointer(
                            absorbing: overlayViewModel.shouldAbsorbMainContentForMode(widget.gameMode),
                            child: Column(
                              children: [
                                _buildCompactPredictor(_viewModel),
                                _buildTabBar(),
                                _buildChromeAddressBar(),
                                _buildBalanceDisplay(_viewModel),
                                Expanded(child: _buildWebView(_viewModel)),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                // Overlay Buttons Panel (on top)
                Consumer<OverlayButtonsViewModel>(
                  builder: (context, overlayViewModel, _) {
                    // Initialize overlay buttons
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (overlayViewModel.buttons.isNotEmpty &&
                          overlayViewModel.buttons.every(
                            (b) => b.position == const Offset(0, 0),
                          )) {
                        overlayViewModel.initialize();
                      }
                    });

                    return OverlayButtonsPanel(
                      screenSize: MediaQuery.of(context).size,
                      gameMode: widget.gameMode,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Builds the top compact predictor UI
  Widget _buildCompactPredictor(SequenceAnalyzerViewModel viewModel) {
    final Map<String, Color> currentButtonColors = {
      for (var item in viewModel.buttonValues) item: const Color(0xFF1E293B),
    };
    if (viewModel.lastPredictedChar != null) {
      currentButtonColors[viewModel.lastPredictedChar!] = const Color(0xFF3B82F6);
    }

    // Compact UI Tweak: Reduced height and font size for wider game view
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      color: ChromeColors.tabBarBg,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: viewModel.buttonValues.map((item) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3.0, vertical: 2.0),
                  child: SizedBox(
                    height: 28,
                    child: ElevatedButton(
                      onPressed: viewModel.isCalculating
                          ? null
                          : () {
                              viewModel.recordInput(item);
                            },
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.all<Color>(
                          currentButtonColors[item]!,
                        ),
                        foregroundColor: WidgetStateProperty.all<Color>(
                          Colors.white,
                        ),
                        padding: WidgetStateProperty.all<EdgeInsetsGeometry>(
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        ),
                        shape: WidgetStateProperty.all<OutlinedBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                        ),
                      ),
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 2),
          _buildHistoryText(viewModel.inputs),
        ],
      ),
    );
  }



  /// Builds the history display (compact version)
  Widget _buildHistoryText(Queue<HistoryEntry> inputs) {
    const int maxHistoryLength = 20;
    final Iterable<HistoryEntry> recentInputs = inputs.length > maxHistoryLength
        ? inputs.skip(inputs.length - maxHistoryLength)
        : inputs;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Wrap(
        spacing: 5.0,
        runSpacing: 5.0,
        alignment: WrapAlignment.center,
        children: recentInputs.map((entry) {
          return Text(
            entry.selectedPos ?? entry.value,
            style: TextStyle(
              color: entry.isRed ? Colors.red[400] : ChromeColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Builds the balance and prediction count display
  Widget _buildBalanceDisplay(SequenceAnalyzerViewModel viewModel) {
    final mode = widget.gameMode;
    final profit = viewModel.getProfitForMode(mode);
    final profitColor = profit >= 0 ? Colors.green : Colors.red;

    // Isolated balance per GameMode
    Color balanceColor = ChromeColors.textPrimary;
    String balanceText = viewModel.getBalanceForMode(mode) ?? 'Loading...';
    String coinType = viewModel.getCoinTypeForMode(mode) ?? (mode == GameMode.mines ? 'POL' : 'DOGE');

    if (balanceText == "Checking...") {
      balanceColor = Colors.amber[300]!;
    } else if (balanceText == "Error" || balanceText == "Not Found") {
      balanceColor = Colors.red[400]!;
    } else if (balanceText != "Loading..." && balanceText != "N/A") {
      balanceColor = Colors.green[400]!;
    }

    // Check for WebView lock state
    if (viewModel.isWebViewLocked) {
      balanceColor = Colors.red[600]!;
      final remainingSeconds = viewModel.remainingLockSeconds;
      final minutes = remainingSeconds ~/ 60;
      final seconds = remainingSeconds % 60;
      balanceText =
          "$balanceText (LOCKED $minutes:${seconds.toString().padLeft(2, '0')})";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: viewModel.isWebViewLocked
            ? Colors.red.withValues(alpha: 0.2)
            : ChromeColors.activeTab,
        border: Border(
          bottom: BorderSide(
            color: viewModel.isWebViewLocked
                ? Colors.red[400]!
                : ChromeColors.divider,
            width: viewModel.isWebViewLocked ? 2 : 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                viewModel.isWebViewLocked
                    ? Icons.lock_rounded
                    : Icons.account_balance_wallet_rounded,
                color: viewModel.isWebViewLocked
                    ? Colors.red[600]!
                    : ChromeColors.textSecondary,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                "Balance $coinType: $balanceText",
                style: TextStyle(
                  color: balanceColor,
                  fontSize: 13,
                  fontWeight:
                      (balanceText == "Checking..." ||
                          viewModel.isWebViewLocked)
                      ? FontWeight.w500
                      : FontWeight.normal,
                ),
              ),
              if (balanceText == "Checking...") const SizedBox(width: 8),
              if (balanceText == "Checking...")
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.amber[300]!,
                    ),
                  ),
                ),
              if (viewModel.isWebViewLocked) ...[
                const SizedBox(width: 8),
                Icon(Icons.warning_rounded, color: Colors.red[600]!, size: 16),
              ],
            ],
          ),
          Text(
            "Profit: ${profit.toStringAsFixed(3)}%",
            style: TextStyle(
              color: profit <= -0.31
                  ? Colors.red[600]!
                  : profitColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
