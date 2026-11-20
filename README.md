# 岑茗养老 Android 客户端

固定加载 [https://c.my-gun.top/](https://c.my-gun.top/) 的 Flutter WebView 客户端。

## 工程信息

- 应用名称：岑茗养老
- 包名：`top.myguntop.cenming_care`
- 版本：`1.0.3+4`
- 最低系统：Android 7.0（API 24）
- Flutter：FVM 管理，版本 `3.35.4`
- WebView：`webview_flutter 4.13.1`

主要逻辑在 `lib/main.dart`，入口地址为 `kHomeUrl`。

## 构建

本机使用 Android Studio 自带的 JDK 17 构建：

```powershell
$env:JAVA_HOME = 'D:\hjh\Android\Android Studio\jbr'
$env:ANDROID_HOME = 'C:\Users\27175\AppData\Local\Android\sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME

fvm flutter pub get
fvm flutter analyze
fvm flutter build apk --release
```

构建产物：

```text
build\app\outputs\flutter-apk\app-release.apk
```

发布副本：

```text
dist\cenming-care-v1.0.3-release.apk
```

## 签名

正式包使用 `android/release-key.jks` 签名，证书信息在 `android/key.properties`。

- 这两个文件已加入 `.gitignore`，不要上传或外发。
- 后续升级必须继续使用同一份 keystore，请单独备份。
- 如需更换签名，修改 `android/key.properties` 后重新构建。

## 功能

- 固定入口加载岑茗养老官网
- 支持网页 JavaScript
- 支持页面内跳转与系统返回键回退
- 首次加载页、顶部加载进度、断网重试页
- 修复 Android WebView 中菜单按钮三条横线宽度为 0 的问题
- 首次启动申请定位、相机、麦克风、电话、短信、通讯录权限
- 网页定位、摄像头预览与拍照上传已接通
- 视频连线使用分轨采集兜底，避免 WebView 同时申请音视频时启动失败
- 电话、短信和地图链接可拉起对应系统应用
- 自适应 Android 启动图标
