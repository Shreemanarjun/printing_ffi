<p align="center">
  <img src="https://zmozkivkhopoeutpnnum.supabase.co/storage/v1/object/public/images/printing_ffi_plugin_logo.png" alt="printing_ffi Logo" width="200"/>
</p>

# printing_ffi 🖨️

[![Sponsor on GitHub](https://img.shields.io/static/v1?label=Sponsor&message=%E2%9D%A4&logo=GitHub&color=%23fe8e86)](https://github.com/sponsors/Shreemanarjun)
[![Buy Me a Coffee](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/shreemanarjun)

A Flutter plugin for direct printer communication using native FFI (Foreign Function Interface) bindings. This plugin enables listing printers (including offline ones), sending raw print data, and managing print jobs on macOS (via CUPS) and Windows (via winspool). It is designed for low-level printing tasks, offering improved performance and flexibility over solutions like the printing package. 🚀

## Features 🌟

- **List Printers** 📋: Retrieve all available printers, including offline ones, with their current status (e.g., `Idle`, `Printing`, `Offline`).
- **Raw Data Printing** 📦: Send raw print data (e.g., ZPL, ESC/POS) directly to printers, bypassing document rendering.
- **Print Job Management** ⚙️: List, pause, resume, and cancel print jobs for a selected printer.
- **Track Print Job Status** 📊: Submit a print job and receive a stream of status updates, from submission to completion.
- **PDF Printing** 📄: Print PDF files directly to a specified printer. On Windows, this uses a bundled version of the `pdfium` library for robust, self-contained rendering.
- **Collate Support** 📚: Control how multiple copies are arranged when printing. Choose between collated (complete copies together) or non-collated (all copies of each page together) printing.
- **Duplex Printing** 📖: Support for double-sided printing with three modes: single-sided, duplex long edge (book-style), and duplex short edge (notepad-style).
- **Get Printer Capabilities (Windows)** 🖨️: Fetch supported paper sizes, paper sources (trays/bins), and resolutions for a given printer on Windows.
- **Advanced Print Settings (Windows)** 🔧: Control paper size, source, orientation, duplex mode, and collate mode for individual print jobs.
- **Cross-Platform** 🌐: Supports macOS, Windows, and Linux via native APIs.
- **Offline Printer Support** 🔌: Lists offline printers on macOS using `cupsGetDests`, addressing a key limitation of other plugins.
- **Native Performance** ⚡: Uses FFI to interface directly with native printing APIs, reducing overhead and improving speed.
- **UI Feedback** 🔔: Includes an example app with a user-friendly interface, empty states, and snackbar notifications for errors and status updates.

## Platform Support 🌐

| Platform   |      Status      | Notes                                |
| :--------- | :--------------: | :----------------------------------- |
| 🍎 macOS   |   ✅ Supported   | Requires CUPS installation.          |
| 🪟 Windows |   ✅ Supported   | Uses native `winspool` API.          |
| 🐧 Linux   |   ✅ Supported   | Requires CUPS development libraries. |
| 🤖 Android | ❌ Not Supported | -                                    |
| 📱 iOS     | ❌ Not Supported | -                                    |

## `printing_ffi` vs. `package:printing`

| Feature              |           `printing_ffi`            |        `package:printing`         |
| :------------------- | :---------------------------------: | :-------------------------------: |
| **Communication**    |       ⚡ Native FFI (Direct)        |       🐌 Platform Channels        |
| **Data Type**        |          📦 Raw Data & PDF          |         📄 PDF Documents          |
| **Offline Printers** |        ✅ Supported (macOS)         |         ❌ Not Supported          |
| **Job Management**   | ✅ Full Control (List, Pause, etc.) |            ❌ Limited             |
| **Dependencies**     |    🍃 Lightweight (No PDF libs)     | 📚 Heavy (Includes PDF rendering) |
| **UI Examples**      |    ✨ Enhanced (Snackbars, etc.)    |             ➖ Basic              |

## Installation 📦

Add the following to your `pubspec.yaml`:

```yaml
dependencies:
  printing_ffi: ^0.0.1 # Use the latest version from pub.dev
```

Run:

```bash
flutter pub get
```

### macOS Setup 🍎

1.  **Install CUPS dependencies**:

    ```bash
    brew install cups
    ```

2.  **Ensure CUPS is running**:

    ```bash
    sudo launchctl start org.cups.cupsd
    ```

3.  **Update `macos/Podfile`** to include the `printing_ffi` plugin. Use the following `Podfile`:

    ```ruby
    platform :osx, '10.15'

    # Disable CocoaPods analytics for faster builds
    ENV['COCOAPODS_DISABLE_STATS'] = 'true'

    project 'Runner', {
      'Debug' => :debug,
      'Profile' => :release,
      'Release' => :release,
    }

    def flutter_root
      generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'ephemeral', 'Flutter-Generated.xcconfig'), __FILE__)
      unless File.exist?(generated_xcode_build_settings_path)
        raise "#{generated_xcode_build_settings_path} must exist. If you're running pod install manually, make sure \"flutter pub get\" is executed first"
      end

      File.foreach(generated_xcode_build_settings_path) do |line|
        matches = line.match(/FLUTTER_ROOT\=(.*)/)
        return matches[1].strip if matches
      end
      raise "FLUTTER_ROOT not found in #{generated_xcode_build_settings_path}. Try deleting Flutter-Generated.xcconfig, then run \"flutter pub get\""
    end

    require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)

    flutter_macos_podfile_setup

    target 'Runner' do
      use_frameworks!
      pod 'printing_ffi', :path => '../' # Path to the printing_ffi plugin
      flutter_install_all_macos_pods File.dirname(File.realpath(__FILE__))
    end

    post_install do |installer|
      installer.pods_project.targets.each do |target|
        flutter_additional_macos_build_settings(target)
      end
    end
    ```

4.  **Run `pod install`** in the `macos` directory:

    ```bash
    cd macos
    pod install
    ```

5.  **Verify `printing_ffi.framework`**: Ensure it’s built and included in `macos/Flutter/ephemeral/.app`.

### Windows Setup 🪟

The plugin uses the native `winspool` API for printing. For PDF printing, it bundles the PDFium library.

#### PDF Printing and Compatibility

If you are using `printing_ffi` for PDF printing on Windows, you may need to initialize the PDFium library.

*   **If you are also using another PDF plugin (like `pdfrx`)**: You do **not** need to do anything. The other plugin will handle PDFium's initialization, and `printing_ffi` will use the existing instance.

*   **If `printing_ffi` is your ONLY PDFium-based plugin**: You **must** call `initPdfium()` once when your app starts. This ensures the library is initialized correctly on the main thread.

Add the following to your `main()` function:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:printing_ffi/printing_ffi.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    PrintingFfi.instance.initPdfium();
  }

  runApp(const MyApp());
}
```

### Linux Setup 🐧

1.  **Install CUPS development libraries**:
    - On Debian/Ubuntu:
      ```bash
      sudo apt-get install libcups2-dev
      ```
    - On Fedora/CentOS/RHEL:
      ```bash
      sudo dnf install cups-devel
      ```
2.  **Ensure CUPS is running**:
    ```bash
    sudo systemctl start cups
    ```

#### Overriding the Pdfium Version

The plugin automatically downloads a specific version of the `pdfium` library for PDF printing on Windows. If you need to use a different version, you can override the default by setting variables in your application's `windows/CMakeLists.txt` file _before_ the `add_subdirectory(flutter)` line:

```cmake
# In your_project/windows/CMakeLists.txt
set(PDFIUM_VERSION "5790" CACHE STRING "" FORCE)
set(PDFIUM_ARCH "x64" CACHE STRING "" FORCE)

add_subdirectory(flutter)
```

## Limitations 🚧

- Requires manual setup for macOS (CUPS installation, Podfile configuration).
- Requires manual setup for macOS and Linux to install printing system dependencies.
- The Windows implementation automatically downloads and bundles the `pdfium` library for PDF rendering.

## Troubleshooting 🛠️

### Offline Printers Not Showing

- **macOS**:
  - Verify printers in `System Settings > Printers & Scanners`.
  - Reset printing system: Control-click the printer list, select `Reset Printing System`, and re-add printers.
  - Check CUPS: Access `http://localhost:631` and ensure `org.cups.cupsd` is running (`sudo launchctl start org.cups.cupsd`).
  - Run `lpstat -p` in the terminal to list all printers, including offline ones.
- **Connections**: Ensure USB cables are secure or network printers are on the same Wi-Fi and not in sleep mode.
- **Drivers**: Update via `System Settings > Software Update` or the manufacturer’s website (e.g., HP Smart app).

### Build Issues

- Ensure `libcups` is installed (`brew install cups`).
- Verify your `Podfile` includes `pod 'printing_ffi', :path => '../'`.
- To suppress the Xcode “Run Script” warning: In `macos/Runner.xcodeproj`, uncheck “Based on dependency analysis” in `Build Phases > Run Script`.
- Check CUPS logs for errors: `/var/log/cups/error_log`.

### No Printers Found on macOS

If `listPrinters()` returns an empty list on macOS even when printers are configured in System Settings, the issue is likely related to the **App Sandbox**. Sandboxed apps have restricted access to system resources by default.

To fix this, you must grant your application permissions for **Printing** and **Outgoing Network Connections**. This allows it to interact with the printing system and communicate with the CUPS daemon.

1.  Open your project's `macos` folder in Xcode: `open macos/Runner.xcworkspace`.
2.  In the project navigator, select the `Runner` target.
3.  Navigate to the **Signing & Capabilities** tab.
4.  If not already present, click **+ Capability** and add **App Sandbox**.
5.  Under the App Sandbox settings, find the **Hardware** section and check the box for **Printing**.
6.  In the same section, find **Network** and check the box for **Outgoing Connections (Client)**.

This adds the necessary entitlements to your app. Your `DebugProfile.entitlements` (or `Release.entitlements`) file should now contain these keys:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.print</key>
    <true/>
</dict>
</plist>
```

## Contributing 🤝

Contributions are welcome! Please submit issues or pull requests to the repository.

- **GitHub Repository**: https://github.com/Shreemanarjun/printing_ffi
