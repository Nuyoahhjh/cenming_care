import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

const String kHomeUrl = 'https://c.my-gun.top/';
const Color kBrandColor = Color(0xFF0D7D72);
const MethodChannel _nativeChannel = MethodChannel(
  'top.myguntop.cenming_care/native',
);
const Set<String> _externalSchemes = {
  'tel',
  'sms',
  'smsto',
  'mailto',
  'geo',
  'androidamap',
  'iosamap',
};

const List<_PermissionItem> _androidPermissionItems = [
  _PermissionItem(
    icon: Icons.location_on_outlined,
    title: '定位',
    description: '签到、服务地点校验',
    permission: Permission.locationWhenInUse,
  ),
  _PermissionItem(
    icon: Icons.camera_alt_outlined,
    title: '相机',
    description: '现场拍照、水印留证',
    permission: Permission.camera,
  ),
  _PermissionItem(
    icon: Icons.mic_none_rounded,
    title: '麦克风',
    description: '视频服务、语音沟通',
    permission: Permission.microphone,
  ),
  _PermissionItem(
    icon: Icons.phone_outlined,
    title: '电话',
    description: '联系客户与家属',
    permission: Permission.phone,
  ),
  _PermissionItem(
    icon: Icons.sms_outlined,
    title: '短信',
    description: '发送服务通知短信',
    permission: Permission.sms,
  ),
  _PermissionItem(
    icon: Icons.contacts_outlined,
    title: '通讯录',
    description: '选择联系人',
    permission: Permission.contacts,
  ),
];

const List<_PermissionItem> _iosPermissionItems = [
  _PermissionItem(
    icon: Icons.location_on_outlined,
    title: '定位',
    description: '签到、服务地点校验',
    permission: Permission.locationWhenInUse,
  ),
  _PermissionItem(
    icon: Icons.camera_alt_outlined,
    title: '相机',
    description: '现场拍照、水印留证',
    permission: Permission.camera,
  ),
  _PermissionItem(
    icon: Icons.mic_none_rounded,
    title: '麦克风',
    description: '视频服务、语音沟通',
    permission: Permission.microphone,
  ),
  _PermissionItem(
    icon: Icons.photo_library_outlined,
    title: '照片',
    description: '保存与选择现场照片',
    permission: Permission.photos,
  ),
];

List<_PermissionItem> get _permissionItems =>
    defaultTargetPlatform == TargetPlatform.iOS
    ? _iosPermissionItems
    : _androidPermissionItems;

// Android WebView gives <button> align-items: flex-start, which collapses the
// site's empty-span hamburger bars to zero width. Restore the intended layout.
// The window.open shim routes phone/SMS/map links through the host application.
const String _webViewCompatScript = '''
(() => {
  const styleId = 'cenming-webview-compat';
  let style = document.getElementById(styleId);
  if (!style) {
    style = document.createElement('style');
    style.id = styleId;
    document.head.appendChild(style);
  }
  style.textContent = '.hdr__burger { align-items: stretch !important; }';

  if (!window.__cenmingExternalLinkCompat) {
    const originalOpen = window.open.bind(window);
    window.open = (url, target, features) => {
      if (
        typeof url === 'string' &&
        /^(tel|sms|smsto|mailto|geo|androidamap|iosamap):/i.test(url)
      ) {
        window.location.href = url;
        return null;
      }
      return originalOpen(url, target, features);
    };
    window.__cenmingExternalLinkCompat = true;
  }

  const mediaDevices = navigator.mediaDevices;
  if (mediaDevices && !mediaDevices.__cenmingCompat) {
    const originalGetUserMedia = mediaDevices.getUserMedia.bind(mediaDevices);
    const tryStream = async (constraints) => {
      try {
        return await originalGetUserMedia(constraints);
      } catch (_) {
        return null;
      }
    };
    mediaDevices.getUserMedia = async (constraints) => {
      try {
        return await originalGetUserMedia(constraints);
      } catch (firstError) {
        const wantsVideo = Boolean(constraints?.video);
        const wantsAudio = Boolean(constraints?.audio);
        let desiredFacing = wantsAudio ? 'user' : 'environment';
        if (constraints?.video && typeof constraints.video === 'object') {
          const facing = constraints.video.facingMode;
          if (typeof facing === 'string') {
            desiredFacing = facing;
          } else if (facing?.ideal) {
            desiredFacing = facing.ideal;
          }
        }

        let videoStream = null;
        if (wantsVideo) {
          videoStream = await tryStream({
            video: {width: {ideal: 640}, facingMode: desiredFacing},
            audio: false,
          });
          if (!videoStream) {
            videoStream = await tryStream({video: true, audio: false});
          }
        }

        let audioStream = null;
        if (wantsAudio) {
          audioStream = await tryStream({
            audio: {
              echoCancellation: false,
              noiseSuppression: false,
              autoGainControl: false,
            },
            video: false,
          });
          if (!audioStream) {
            audioStream = await tryStream({audio: true, video: false});
          }
        }

        const tracks = [
          ...(videoStream?.getVideoTracks() ?? []),
          ...(audioStream?.getAudioTracks() ?? []),
        ];
        if (tracks.length > 0) {
          if (wantsAudio && !audioStream) {
            window.CenmingMediaStatus?.postMessage(
              '摄像头已启动，但麦克风不可用。请检查系统麦克风开关，或关闭占用麦克风的应用后重试。',
            );
          }
          if (wantsVideo && !videoStream) {
            window.CenmingMediaStatus?.postMessage(
              '麦克风已启动，但摄像头不可用。请检查系统相机开关后重试。',
            );
          }
          return new MediaStream(tracks);
        }
        window.CenmingMediaStatus?.postMessage(
          '摄像头和麦克风启动失败（' +
            (firstError?.name || '未知错误') +
            '）。请检查系统相机、麦克风开关后重试。',
        );
        throw firstError;
      }
    };
    mediaDevices.__cenmingCompat = true;
  }
})();
''';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const CenmingCareApp());
}

class CenmingCareApp extends StatelessWidget {
  const CenmingCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '岑茗养老',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kBrandColor),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = true;
  bool _hasLoadedPage = false;
  bool _hasError = false;
  bool _permissionPromptShown = false;
  bool _permissionSheetOpen = false;
  bool _requestingPermissions = false;
  bool _isPickingFile = false;
  bool _locationSettingsPrompted = false;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController.fromPlatformCreationParams(
      _buildControllerParams(),
      onPermissionRequest: (request) {
        unawaited(_handleWebPermissionRequest(request.platform));
      },
    );
    unawaited(_configureWebView());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(
        const Duration(milliseconds: 900),
        _maybePromptForPermissions,
      );
    });
  }

  PlatformWebViewControllerCreationParams _buildControllerParams() {
    const base = PlatformWebViewControllerCreationParams();
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      return WebKitWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
        base,
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    }
    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      return AndroidWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
        base,
      );
    }
    return base;
  }

  Future<void> _handleWebPermissionRequest(
    PlatformWebViewPermissionRequest request,
  ) async {
    final required = <Permission>[
      if (request.types.contains(WebViewPermissionResourceType.camera))
        Permission.camera,
      if (request.types.contains(WebViewPermissionResourceType.microphone))
        Permission.microphone,
    ];
    var allowed = true;
    if (required.isNotEmpty) {
      final currentStatuses = await Future.wait(
        required.map((permission) => permission.status),
      );
      allowed = currentStatuses.every((status) => status.isGranted);
      if (!allowed) {
        final requested = await required.request();
        allowed = requested.values.every((status) => status.isGranted);
      }
    }
    if (allowed) {
      await request.grant();
    } else {
      await request.deny();
      _showMessage('需要相机或麦克风权限才能拍照、录像或语音通话');
    }
  }

  Future<void> _configureWebView() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setBackgroundColor(Colors.white);
    await _controller.addJavaScriptChannel(
      'CenmingMediaStatus',
      onMessageReceived: (message) => _showMessage(message.message),
    );
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() => _progress = progress);
        },
        onPageStarted: (_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isLoading = true;
            _hasError = false;
          });
        },
        onPageFinished: (_) {
          if (!mounted) {
            return;
          }
          unawaited(_applyWebViewCompatScript());
          setState(() {
            _isLoading = false;
            _progress = 100;
            if (!_hasError) {
              _hasLoadedPage = true;
            }
          });
        },
        onWebResourceError: (error) {
          if (!mounted || error.isForMainFrame != true) {
            return;
          }
          debugPrint(
            'WebView main-frame error ${error.errorCode}: ${error.description}',
          );
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) {
            return NavigationDecision.prevent;
          }
          if (uri.scheme == 'http' || uri.scheme == 'https') {
            return NavigationDecision.navigate;
          }
          if (_externalSchemes.contains(uri.scheme)) {
            unawaited(_launchExternal(uri));
          }
          return NavigationDecision.prevent;
        },
      ),
    );

    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      await _configureAndroidWebView(platform);
    } else if (platform is WebKitWebViewController) {
      await _configureIosWebView();
    }
    _loadHomePage();
  }

  Future<void> _configureIosWebView() async {
    final platform = _controller.platform;
    if (platform is! WebKitWebViewController) {
      return;
    }
    await platform.setAllowsBackForwardNavigationGestures(true);
  }

  Future<void> _configureAndroidWebView(
    AndroidWebViewController controller,
  ) async {
    await controller.setGeolocationEnabled(true);
    await controller.setMediaPlaybackRequiresUserGesture(false);
    await controller.setAllowFileAccess(true);
    await controller.setAllowContentAccess(true);
    await controller.setGeolocationPermissionsPromptCallbacks(
      onShowPrompt: (_) async {
        final allowed = await _ensureLocationPermission();
        return GeolocationPermissionsResponse(allow: allowed, retain: true);
      },
    );
    await controller.setOnPlatformPermissionRequest((request) async {
      await _handleWebPermissionRequest(request);
    });
    await controller.setOnShowFileSelector(_pickImageForWebView);
  }

  void _loadHomePage() {
    _controller.loadRequest(Uri.parse(kHomeUrl));
  }

  void _retry() {
    setState(() {
      _isLoading = true;
      _hasLoadedPage = false;
      _hasError = false;
      _progress = 0;
    });
    _loadHomePage();
  }

  Future<void> _applyWebViewCompatScript() async {
    await _controller.runJavaScript(_webViewCompatScript);
  }

  Future<bool> _ensureLocationPermission() async {
    var status = await Permission.locationWhenInUse.status;
    if (!status.isGranted) {
      status = await Permission.locationWhenInUse.request();
    }
    if (!status.isGranted) {
      _showMessage('定位权限未开启，无法完成定位签到');
      return false;
    }
    final serviceStatus = await Permission.location.serviceStatus;
    if (!serviceStatus.isEnabled) {
      if (!_locationSettingsPrompted && mounted) {
        _locationSettingsPrompted = true;
        unawaited(_showLocationServiceDialog());
      }
    }
    return true;
  }

  Future<void> _showLocationServiceDialog() async {
    if (!mounted) {
      return;
    }
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('请开启定位服务'),
        content: const Text('手机定位服务当前未开启，开启后才能获取签到坐标。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('去开启'),
          ),
        ],
      ),
    );
    if (openSettings == true) {
      try {
        await _nativeChannel.invokeMethod<bool>('openLocationSettings');
      } on PlatformException {
        await openAppSettings();
      }
    }
  }

  Future<List<String>> _pickImageForWebView(FileSelectorParams params) async {
    if (_isPickingFile) {
      return <String>[];
    }
    if (params.mode != FileSelectorMode.open &&
        params.mode != FileSelectorMode.openMultiple) {
      _showMessage('当前页面暂不支持该文件操作');
      return <String>[];
    }
    final acceptsImages =
        params.acceptTypes.isEmpty ||
        params.acceptTypes.any(
          (type) => type == '*/*' || type.startsWith('image/'),
        );
    if (!acceptsImages) {
      _showMessage('当前页面仅支持选择图片');
      return <String>[];
    }

    _isPickingFile = true;
    try {
      if (!mounted) {
        return <String>[];
      }
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '上传现场照片',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  '可现场拍照，也可从相册选择',
                  style: TextStyle(color: Color(0xFF6A827E)),
                ),
                const SizedBox(height: 18),
                ListTile(
                  leading: const Icon(
                    Icons.photo_camera_outlined,
                    color: kBrandColor,
                  ),
                  title: const Text('拍照'),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library_outlined,
                    color: kBrandColor,
                  ),
                  title: const Text('从相册选择'),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
      if (source == null) {
        return <String>[];
      }
      if (source == ImageSource.camera) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          _showMessage('相机权限未开启，无法拍照');
          return <String>[];
        }
      }
      final file = await _imagePicker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 95,
        maxWidth: 2560,
        maxHeight: 2560,
      );
      if (file == null) {
        return <String>[];
      }
      return <String>[file.path];
    } on PlatformException catch (error) {
      _showMessage(error.message ?? '图片选择失败');
      return <String>[];
    } catch (_) {
      _showMessage('图片选择失败，请重试');
      return <String>[];
    } finally {
      _isPickingFile = false;
    }
  }

  Future<void> _launchExternal(Uri uri) async {
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _showMessage('未找到可处理该链接的应用');
      }
    } on PlatformException {
      _showMessage('未找到可处理该链接的应用');
    }
  }

  Future<void> _maybePromptForPermissions() async {
    if (!mounted || _permissionPromptShown) {
      return;
    }
    _permissionPromptShown = true;
    final missing = <_PermissionItem>[];
    for (final item in _permissionItems) {
      final status = await item.permission.status;
      if (!status.isGranted && !status.isLimited) {
        missing.add(item);
      }
    }
    if (!mounted || missing.isEmpty) {
      return;
    }
    await _showPermissionSheet(missing);
  }

  Future<void> _showPermissionSheet(List<_PermissionItem> items) async {
    if (!mounted || _permissionSheetOpen) {
      return;
    }
    _permissionSheetOpen = true;
    final shouldRequest = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PermissionSheet(items: items),
    );
    _permissionSheetOpen = false;
    if (shouldRequest == true) {
      await _requestPermissions(items);
    }
  }

  Future<void> _requestPermissions(List<_PermissionItem> items) async {
    if (_requestingPermissions) {
      return;
    }
    _requestingPermissions = true;
    try {
      final statuses = await items
          .map((item) => item.permission)
          .toList()
          .request();
      if (!mounted) {
        return;
      }
      final denied = <_PermissionItem>[
        for (final item in items)
          if (!(statuses[item.permission]?.isGranted ?? false) &&
              !(statuses[item.permission]?.isLimited ?? false))
            item,
      ];
      if (denied.isEmpty) {
        _showMessage('所需权限已全部开启');
        return;
      }
      await _showPermissionResultDialog(denied);
    } finally {
      _requestingPermissions = false;
    }
  }

  Future<void> _showPermissionResultDialog(List<_PermissionItem> denied) async {
    if (!mounted) {
      return;
    }
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('部分权限未开启'),
        content: Text(
          '${denied.map((item) => item.title).join('、')} 尚未开启。'
          '请到系统设置中手动允许，否则相关功能会无法使用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
    if (openSettings == true) {
      await openAppSettings();
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return;
    }
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: WebViewWidget(controller: _controller)),
              if (!_hasLoadedPage && !_hasError)
                const Positioned.fill(child: _LoadingView()),
              if (_hasError)
                Positioned.fill(child: _ErrorView(onRetry: _retry)),
              if (_isLoading && _hasLoadedPage && !_hasError)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    value: _progress > 0 && _progress < 100
                        ? _progress / 100
                        : null,
                    color: kBrandColor,
                    backgroundColor: const Color(0xFFE4F0EE),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionItem {
  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.permission,
  });

  final IconData icon;
  final String title;
  final String description;
  final Permission permission;
}

class _PermissionSheet extends StatelessWidget {
  const _PermissionSheet({required this.items});

  final List<_PermissionItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE7F4F1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_user_outlined,
                    color: kBrandColor,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '开启应用权限',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '签到、拍照、联系等功能需要以下权限',
                        style: TextStyle(
                          color: Color(0xFF6A827E),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Icon(item.icon, color: kBrandColor, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            item.description,
                            style: const TextStyle(
                              color: Color(0xFF6A827E),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: kBrandColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('全部允许'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('稍后'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/brand/favicon.png', width: 88, height: 88),
            const SizedBox(height: 24),
            const Text(
              '岑茗养老',
              style: TextStyle(
                color: Color(0xFF173F3A),
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '正在加载服务页面…',
              style: TextStyle(color: Color(0xFF6A827E), fontSize: 13),
            ),
            const SizedBox(height: 22),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: kBrandColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF5F3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  size: 36,
                  color: kBrandColor,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '页面暂时无法打开',
                style: TextStyle(
                  color: Color(0xFF173F3A),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '请检查网络连接后重试',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6A827E),
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新加载'),
                style: FilledButton.styleFrom(
                  backgroundColor: kBrandColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(148, 46),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                kHomeUrl,
                style: TextStyle(color: Color(0xFF9AAEAA), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
