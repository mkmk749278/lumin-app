/// Update banner — sits above [NavShell], appears when a newer signed
/// APK is available on GitHub Releases.
///
/// Tap → request Android's ``REQUEST_INSTALL_PACKAGES`` permission →
/// download APK with progress bar → hand off to system installer via
/// ``open_filex``.  User taps "Install" in the system dialog → app
/// updates → relaunches.
///
/// Failure modes:
/// * Permission denied → banner shows hint to enable in app settings;
///   re-tapping triggers permission_handler's ``openAppSettings``.
/// * Download fails → banner returns to "Update available" with error
///   text; re-tap retries.
/// * APK signature mismatch on install → Android shows its own error;
///   user manually uninstalls and reinstalls.  Documented in the PR;
///   shouldn't happen in practice (CI signs with the same keystore).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:permission_handler/permission_handler.dart';

import '../../data/update_service.dart';
import '../../shared/tokens.dart';

/// Stateful so we can show download progress + error states inline.
/// One service instance per banner is fine — banner lives for the whole
/// NavShell lifetime.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

enum _BannerState {
  idle,            // not checked yet, or check returned no update
  available,       // newer release exists; show "Update — vX"
  downloading,     // user tapped, download in flight
  installing,      // download complete, hand-off to installer pending
  permissionMissing, // REQUEST_INSTALL_PACKAGES denied
  failed,          // download or install hand-off threw
}

class _UpdateBannerState extends State<UpdateBanner> {
  final UpdateService _service = UpdateService();
  _BannerState _state = _BannerState.idle;
  UpdateAvailable? _update;
  double _progress = 0.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    final result = await _service.check();
    if (!mounted) return;
    if (result == null) return;
    setState(() {
      _state = _BannerState.available;
      _update = result;
    });
  }

  Future<void> _startInstall() async {
    final update = _update;
    if (update == null) return;

    // 1. Permission gate.  Android 8+ requires REQUEST_INSTALL_PACKAGES
    // before the system installer will accept our hand-off.
    final perm = await Permission.requestInstallPackages.request();
    if (!perm.isGranted) {
      if (!mounted) return;
      setState(() => _state = _BannerState.permissionMissing);
      return;
    }

    // 2. Download with progress.  Save under app's external cache dir
    // so we don't need WRITE_EXTERNAL_STORAGE on Android 10+.
    setState(() {
      _state = _BannerState.downloading;
      _progress = 0.0;
      _error = null;
    });
    final dir = await path_provider.getExternalStorageDirectory()
        ?? await path_provider.getApplicationDocumentsDirectory();
    final apkPath = '${dir.path}/lumin-${update.versionName}.apk';
    final dio = Dio();
    try {
      await dio.download(
        update.apkUrl,
        apkPath,
        onReceiveProgress: (rcvd, total) {
          if (total <= 0 || !mounted) return;
          setState(() => _progress = rcvd / total);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _BannerState.failed;
        _error = 'Download failed: $e';
      });
      return;
    } finally {
      dio.close(force: true);
    }

    // 3. Hand off to system installer.  Returns immediately; the user
    // sees Android's install confirmation dialog next.
    if (!mounted) return;
    setState(() => _state = _BannerState.installing);
    final result = await OpenFilex.open(apkPath, type: 'application/vnd.android.package-archive');
    if (!mounted) return;
    if (result.type != ResultType.done) {
      setState(() {
        _state = _BannerState.failed;
        _error = 'Could not open installer: ${result.message}';
      });
    }
    // On success the system installer takes over; if the user confirms
    // the install, the app process is killed + relaunched into the new
    // build, so this widget never renders the success state.
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _BannerState.idle) return const SizedBox.shrink();
    return Material(
      color: LuminColors.bgElevated,
      child: InkWell(
        onTap: _onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: LuminSpacing.lg,
            vertical: LuminSpacing.md,
          ),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: LuminColors.cardBorder, width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _icon(),
                color: _iconColor(),
                size: 20,
              ),
              const SizedBox(width: LuminSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _title(),
                      style: const TextStyle(
                        color: LuminColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_subtitle().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(),
                        style: const TextStyle(
                          color: LuminColors.textSecondary,
                          fontSize: 11,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (_state == _BannerState.downloading) ...[
                      const SizedBox(height: LuminSpacing.sm),
                      LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        minHeight: 3,
                        backgroundColor: LuminColors.cardBorder,
                        valueColor: const AlwaysStoppedAnimation(LuminColors.accent),
                      ),
                    ],
                  ],
                ),
              ),
              if (_state == _BannerState.available ||
                  _state == _BannerState.failed ||
                  _state == _BannerState.permissionMissing) ...[
                const SizedBox(width: LuminSpacing.sm),
                const Icon(
                  Icons.chevron_right,
                  color: LuminColors.textMuted,
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _onTap() {
    switch (_state) {
      case _BannerState.available:
      case _BannerState.failed:
        _startInstall();
        break;
      case _BannerState.permissionMissing:
        _openSettings();
        break;
      case _BannerState.idle:
      case _BannerState.downloading:
      case _BannerState.installing:
        break;
    }
  }

  IconData _icon() {
    switch (_state) {
      case _BannerState.available:
        return Icons.system_update_alt;
      case _BannerState.downloading:
        return Icons.cloud_download_outlined;
      case _BannerState.installing:
        return Icons.install_mobile;
      case _BannerState.permissionMissing:
        return Icons.lock_outline;
      case _BannerState.failed:
        return Icons.error_outline;
      case _BannerState.idle:
        return Icons.system_update_alt;
    }
  }

  Color _iconColor() {
    switch (_state) {
      case _BannerState.failed:
      case _BannerState.permissionMissing:
        return LuminColors.warn;
      default:
        return LuminColors.accent;
    }
  }

  String _title() {
    final name = _update?.versionName ?? '';
    switch (_state) {
      case _BannerState.available:
        return 'Update available — $name';
      case _BannerState.downloading:
        return 'Downloading $name…';
      case _BannerState.installing:
        return 'Opening installer…';
      case _BannerState.permissionMissing:
        return 'Tap to allow installs from Lumin';
      case _BannerState.failed:
        return 'Update failed — tap to retry';
      case _BannerState.idle:
        return '';
    }
  }

  String _subtitle() {
    if (_state == _BannerState.failed && _error != null) return _error!;
    if (_state == _BannerState.available && (_update?.releaseNotes ?? '').isNotEmpty) {
      return _update!.releaseNotes;
    }
    if (_state == _BannerState.downloading && _progress > 0) {
      return '${(_progress * 100).toStringAsFixed(0)}%';
    }
    if (_state == _BannerState.permissionMissing) {
      return 'Android requires \"Install unknown apps\" permission once per source.';
    }
    return '';
  }
}

