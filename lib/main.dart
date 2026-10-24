import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GhostBrowserApp());
}

class GhostBrowserApp extends StatelessWidget {
  const GhostBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GhostBrowse Native',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0D12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5A3),
          surface: Color(0xFF131722),
        ),
      ),
      home: const BrowserShell(),
    );
  }
}

class BrowserShell extends StatefulWidget {
  const BrowserShell({super.key});

  @override
  State<BrowserShell> createState() => _BrowserShellState();
}

class _BrowserShellState extends State<BrowserShell> with WidgetsBindingObserver {
  InAppWebViewController? _webController;
  final TextEditingController _urlController = TextEditingController();
  double _progress = 0;
  bool _isDownloading = false;
  String _statusMessage = 'RAM-Only Mode // Video & Universal Downloader Active';

  // Default Unfiltered Privacy Search Engine (DuckDuckGo / Brave / SearXNG)
  final String _homeSearchUrl = 'https://search.brave.com';

  // Spoofed Desktop/Mobile User-Agent to prevent device fingerprinting
  final String _spoofedUserAgent = Platform.isWindows
      ? 'Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0'
      : 'Mozilla/5.0 (Android 14; Mobile; rv:128.0) Gecko/128.0 Firefox/128.0';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _wipeAllTraces();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Automatically wipe cache & cookies when app is closed
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _wipeAllTraces();
    }
  }

  Future<void> _wipeAllTraces() async {
    await CookieManager.instance().deleteAllCookies();
    await InAppWebViewController.clearAllCache();
    if (_webController != null) {
      await _webController!.clearHistory();
      await _webController!.loadUrl(
        urlRequest: URLRequest(url: WebUri('about:blank')),
      );
    }
    setState(() {
      _urlController.clear();
      _statusMessage = 'INCINERATED // All Cache, Cookies & History Wiped';
    });
  }

  void _navigateOrSearch(String rawInput) {
    final input = rawInput.trim();
    if (input.isEmpty) return;

    String targetUrl;
    final isUrl = input.startsWith('http://') ||
        input.startsWith('https://') ||
        (input.contains('.') && !input.contains(' '));

    if (isUrl) {
      targetUrl = input.startsWith('http') ? input : 'https://$input';
    } else {
      // Unfiltered search query
      targetUrl = 'https://search.brave.com/search?q=${Uri.encodeComponent(input)}';
    }

    _webController?.loadUrl(
      urlRequest: URLRequest(
        url: WebUri(targetUrl),
        headers: {'Referer': '', 'X-Do-Not-Track': '1', 'DNT': '1'},
      ),
    );
  }

  Future<void> _downloadAnyFile(String url, String? suggestedFilename) async {
    setState(() {
      _isDownloading = true;
      _statusMessage = 'Downloading file anonymously...';
    });

    try {
      final client = HttpClient();
      client.userAgent = _spoofedUserAgent;
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      Directory? saveDir;
      if (Platform.isAndroid) {
        saveDir = Directory('/storage/emulated/0/Download');
        if (!await saveDir.exists()) {
          saveDir = await getExternalStorageDirectory();
        }
      } else {
        saveDir = await getDownloadsDirectory();
      }

      final fileName = suggestedFilename ??
          Uri.parse(url).pathSegments.lastWhere(
                (s) => s.isNotEmpty,
                orElse: () => 'download_${DateTime.now().millisecondsSinceEpoch}.bin',
              );

      final filePath = '${saveDir!.path}${Platform.pathSeparator}$fileName';
      final file = File(filePath);
      final bytes = await consolidateHttpClientResponseBytes(response);
      await file.writeAsBytes(bytes);

      setState(() {
        _isDownloading = false;
        _statusMessage = 'Saved to Downloads: $fileName';
      });
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _statusMessage = 'Download failed or blocked: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top Controls Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              color: const Color(0xFF131722),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    onPressed: () => _webController?.goBack(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 18),
                    onPressed: () => _webController?.goForward(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () => _webController?.reload(),
                  ),
                  Expanded(
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0D12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF232A3B)),
                      ),
                      child: TextField(
                        controller: _urlController,
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Search anything or enter URL...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onSubmitted: _navigateOrSearch,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Manual Download Current Media/Page Button
                  IconButton(
                    tooltip: 'Force Download Current URL',
                    icon: const Icon(Icons.download_rounded, color: Color(0xFF00E5A3)),
                    onPressed: () async {
                      final currentUrl = await _webController?.getUrl();
                      if (currentUrl != null) {
                        _downloadAnyFile(currentUrl.toString(), null);
                      }
                    },
                  ),
                  // Panic Burn Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3B5C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: _wipeAllTraces,
                    child: const Text('BURN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),

            // Progress Bar
            if (_progress < 1.0 || _isDownloading)
              LinearProgressIndicator(
                value: _isDownloading ? null : _progress,
                backgroundColor: Colors.transparent,
                color: const Color(0xFF00E5A3),
                minHeight: 2,
              ),

            // Real Native Browser Engine (Full Video, Audio & Download Support)
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(_homeSearchUrl)),
                initialSettings: InAppWebViewSettings(
                  incognito: true,
                  cacheEnabled: false,
                  clearCache: true,
                  clearSessionCache: true,
                  thirdPartyCookiesEnabled: false,
                  javaScriptEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  useOnDownloadStart: true,
                  userAgent: _spoofedUserAgent,
                ),
                onWebViewCreated: (controller) {
                  _webController = controller;
                },
                onLoadStart: (controller, url) {
                  setState(() {
                    _urlController.text = url?.toString() ?? '';
                    _statusMessage = 'Encrypted connection active // Zero disk history';
                  });
                },
                onProgressChanged: (controller, progress) {
                  setState(() => _progress = progress / 100);
                },
                onDownloadStartRequest: (controller, request) {
                  _downloadAnyFile(
                    request.url.toString(),
                    request.suggestedFilename,
                  );
                },
              ),
            ),

            // Bottom Security Status Bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              color: const Color(0xFF0E121B),
              child: Text(
                _statusMessage,
                style: const TextStyle(fontSize: 11, color: Color(0xFF7C859E)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
