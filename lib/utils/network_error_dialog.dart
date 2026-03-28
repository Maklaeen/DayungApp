import 'dart:async';

import 'package:capstone_app/config/app_config.dart';
import 'package:capstone_app/main.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class NetworkMonitor {
  static final NetworkMonitor _instance = NetworkMonitor._internal();
  factory NetworkMonitor() => _instance;
  NetworkMonitor._internal();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _retryTimer;

  bool _started = false;
  bool _isOffline = false;
  bool _dialogVisible = false;
  bool _isChecking = false;

  void start() {
    if (_started) return;
    _started = true;

    _subscription = Connectivity().onConnectivityChanged.listen((_) async {
      await _syncConnectionState();
    });

    unawaited(_syncConnectionState());
  }

  Future<void> checkNow() async {
    await _syncConnectionState();
  }

  Future<void> _syncConnectionState() async {
    final offline = !(await _hasInternetAccess());

    if (offline) {
      if (!_isOffline) {
        _isOffline = true;
        _showNoInternetDialog();
      }
      _startRetryLoop();
    } else {
      _isOffline = false;
      _stopRetryLoop();
      _hideDialog();
    }
  }

  void _startRetryLoop() {
    _retryTimer ??= Timer.periodic(const Duration(seconds: 3), (_) async {
      final hasInternet = await _hasInternetAccess();
      if (hasInternet) {
        _isOffline = false;
        _stopRetryLoop();
        _hideDialog();
      }
    });
  }

  void _stopRetryLoop() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<bool> _hasInternetAccess() async {
    final hasNetworkInterface = await _hasAnyNetworkInterface();
    final probes = <_NetworkProbe>[
      if (kIsWeb)
        _NetworkProbe(
          uri: _buildWebProbeUri(),
          acceptsStatus: (statusCode) => statusCode >= 200 && statusCode < 400,
        ),
      ..._buildBackendProbes(),
      _NetworkProbe(
        uri: Uri.parse('https://clients3.google.com/generate_204'),
        acceptsStatus: (statusCode) => statusCode == 204,
      ),
      _NetworkProbe(
        uri: Uri.parse('https://www.gstatic.com/generate_204'),
        acceptsStatus: (statusCode) => statusCode == 204,
      ),
      _NetworkProbe(
        uri: Uri.parse('https://example.com/'),
        acceptsStatus: (statusCode) => statusCode >= 200 && statusCode < 500,
      ),
    ];

    for (final probe in probes) {
      try {
        final response = await http
            .get(probe.uri)
            .timeout(const Duration(seconds: 5));
        if (probe.acceptsStatus(response.statusCode)) {
          return true;
        }
      } catch (_) {
        continue;
      }
    }

    return hasNetworkInterface &&
        !_isExplicitOffline(connectivityFallback: hasNetworkInterface);
  }

  Future<bool> _hasAnyNetworkInterface() async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      return connectivityResults.any(
        (result) => result != ConnectivityResult.none,
      );
    } catch (_) {
      return false;
    }
  }

  List<_NetworkProbe> _buildBackendProbes() {
    final supabaseUrl = AppConfig.supabaseUrl.trim();
    if (supabaseUrl.isEmpty) {
      return const [];
    }

    final baseUri = Uri.tryParse(supabaseUrl);
    if (baseUri == null) {
      return const [];
    }

    return [
      _NetworkProbe(
        uri: baseUri,
        acceptsStatus: (statusCode) => statusCode >= 200 && statusCode < 500,
      ),
      _NetworkProbe(
        uri: baseUri.resolve('/auth/v1/health'),
        acceptsStatus: (statusCode) => statusCode >= 200 && statusCode < 500,
      ),
      _NetworkProbe(
        uri: baseUri.resolve('/rest/v1/'),
        acceptsStatus: (statusCode) => statusCode >= 200 && statusCode < 500,
      ),
    ];
  }

  Uri _buildWebProbeUri() {
    final probeUri = Uri.base.resolve('manifest.json');
    final queryParameters = Map<String, String>.from(probeUri.queryParameters)
      ..['_networkProbe'] = DateTime.now().millisecondsSinceEpoch.toString();

    return probeUri.replace(queryParameters: queryParameters, fragment: '');
  }

  bool _isExplicitOffline({required bool connectivityFallback}) {
    return !connectivityFallback;
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _stopRetryLoop();
    _started = false;
  }

  void _showNoInternetDialog() {
    if (_dialogVisible) return;

    final context = globalNavigatorKey.currentContext;
    if (context == null) return;

    _dialogVisible = true;

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'No Internet Connection',
      barrierColor: const Color(0x66000000),
      useRootNavigator: true,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, _, __) {
        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              Future<void> handleRefresh() async {
                if (_isChecking) return;

                setDialogState(() => _isChecking = true);

                final hasInternet = await _hasInternetAccess();

                if (hasInternet) {
                  _isOffline = false;
                  _stopRetryLoop();
                  _hideDialog();
                } else {
                  if (dialogContext.mounted) {
                    setDialogState(() => _isChecking = false);
                  }
                }
              }

              return SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        width: 420,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDFDFD),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 32,
                              offset: Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFF7A59),
                                    Color(0xFFFF3D54),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Icon(
                                Icons.wifi_off_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'No Internet Connection',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF161616),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Your device is currently offline. Reconnect to the internet and tap Refresh, or wait for this dialog to close automatically.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4F6F8),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 18,
                                    color: Color(0xFF6B7280),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'The app checks periodically and closes this dialog once internet access is restored.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _isChecking ? null : handleRefresh,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF111827),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: _isChecking
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Refresh',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    ).then((_) {
      _dialogVisible = false;
      _isChecking = false;
    });
  }

  void _hideDialog() {
    if (!_dialogVisible) return;

    final navigator = globalNavigatorKey.currentState;
    if (navigator == null) return;

    navigator.pop();
    _dialogVisible = false;
    _isChecking = false;
  }
}

class _NetworkProbe {
  const _NetworkProbe({required this.uri, required this.acceptsStatus});

  final Uri uri;
  final bool Function(int statusCode) acceptsStatus;
}
