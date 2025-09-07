# printing_ffi 🖨️

A Flutter plugin for direct printer communication using native FFI (Foreign Function Interface) bindings. This plugin enables listing printers (including offline ones), sending raw print data, and managing print jobs on macOS (via CUPS) and Windows (via winspool). It is designed for low-level printing tasks, offering improved performance and flexibility over solutions like the printing package. 🚀

## Features 🌟

- **List Printers** 📋: Retrieve all available printers, including offline ones, with their current status (e.g., `Idle`, `Printing`, `Offline`).
- **Raw Data Printing** 📦: Send raw print data (e.g., ZPL, ESC/POS) directly to printers, bypassing document rendering.
- **Print Job Management** ⚙️: List, pause, resume, and cancel print jobs for a selected printer.
- **Cross-Platform** 🌐: Supports macOS (CUPS) and Windows (winspool), with Linux support planned.
- **Offline Printer Support** 🔌: Lists offline printers on macOS using `cupsGetDests`, addressing a key limitation of other plugins.
- **Native Performance** ⚡: Uses FFI to interface directly with native printing APIs, reducing overhead and improving speed.
- **UI Feedback** 🔔: Includes an example app with a user-friendly interface, empty states, and snackbar notifications for errors and status updates.

## Platform Support 🌐

| Platform | Status | Notes |
| :--- | :---: | :--- |
| 🍎 macOS | ✅ Supported | Requires CUPS installation. |
| 🪟 Windows | ✅ Supported | Uses native `winspool` API. |
| 🐧 Linux | ⏳ Planned | Support is planned for a future release. |
| 🤖 Android | ❌ Not Supported | - |
| 📱 iOS | ❌ Not Supported | - |

## `printing_ffi` vs. `package:printing`

| Feature | `printing_ffi` | `package:printing` |
| :--- | :---: | :---: |
| **Communication** | ⚡ Native FFI (Direct) | 🐌 Platform Channels |
| **Data Type** | 📦 Raw Data (ZPL, ESC/POS) | 📄 PDF Documents |
| **Offline Printers** | ✅ Supported (macOS) | ❌ Not Supported |
| **Job Management** | ✅ Full Control (List, Pause, etc.) | ❌ Limited |
| **Dependencies** | 🍃 Lightweight (No PDF libs) | 📚 Heavy (Includes PDF rendering) |
| **UI Examples** | ✨ Enhanced (Snackbars, etc.) | ➖ Basic |

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

No additional setup is required, as the plugin uses the native `winspool` API included with Windows. 🎉

## Limitations 🚧

-   Linux support is planned but not yet implemented.
-   Requires manual setup for macOS (CUPS installation, Podfile configuration).
-   Limited to raw data printing; for PDF or document printing, use the `printing` package.

## Troubleshooting 🛠️

### Offline Printers Not Showing

-   **macOS**:
    -   Verify printers in `System Settings > Printers & Scanners`.
    -   Reset printing system: Control-click the printer list, select `Reset Printing System`, and re-add printers.
    -   Check CUPS: Access `http://localhost:631` and ensure `org.cups.cupsd` is running (`sudo launchctl start org.cups.cupsd`).
    -   Run `lpstat -p` in the terminal to list all printers, including offline ones.
-   **Connections**: Ensure USB cables are secure or network printers are on the same Wi-Fi and not in sleep mode.
-   **Drivers**: Update via `System Settings > Software Update` or the manufacturer’s website (e.g., HP Smart app).

### Build Issues

-   Ensure `libcups` is installed (`brew install cups`).
-   Verify your `Podfile` includes `pod 'printing_ffi', :path => '../'`.
-   To suppress the Xcode “Run Script” warning: In `macos/Runner.xcodeproj`, uncheck “Based on dependency analysis” in `Build Phases > Run Script`.
-   Check CUPS logs for errors: `/var/log/cups/error_log`.

## Contributing 🤝

Contributions are welcome! Please submit issues or pull requests to the repository.

-   **GitHub Repository**: https://github.com/Shreemanarjun/printing_ffi
