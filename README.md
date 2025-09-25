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
  printing_ffi: ^0.0.10 # Use the latest version from pub.dev
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

5.  **Verify `printing_ffi.framework`**: Ensure it's built and included in `macos/Flutter/ephemeral/.app`.

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

## Usage 📚

Here are comprehensive examples showing how to use the `printing_ffi` plugin for various printing tasks:

### Basic Setup

```dart
import 'package:printing_ffi/printing_ffi.dart';
import 'dart:typed_data';
import 'dart:io';

// Get the PrintingFfi instance
final printingFfi = PrintingFfi.instance;
```

### 1. List Available Printers

```dart
// Get all printers (including offline ones)
List<Printer> printers = printingFfi.listPrinters();

for (Printer printer in printers) {
  print('Printer: ${printer.name}');
  print('  State: ${printer.state}');
  print('  Available: ${printer.isAvailable}');
  print('  Default: ${printer.isDefault}');
  print('  Model: ${printer.model}');
  print('  Location: ${printer.location}');
  print('---');
}

// Get the default printer
Printer? defaultPrinter = printingFfi.getDefaultPrinter();
if (defaultPrinter != null) {
  print('Default printer: ${defaultPrinter.name}');
}
```

### 2. Raw Data Printing (ZPL, ESC/POS, etc.)

```dart
// Example: Print ZPL label to a label printer
Future<void> printZplLabel() async {
  const String zplData = '''
^XA
^LH0,0
^FO50,50^ADN,36,20^FDHello World^FS
^FO50,100^ADN,36,20^FDPrinting FFI^FS
^XZ
''';

  final Uint8List data = Uint8List.fromList(zplData.codeUnits);

  try {
    bool success = await printingFfi.rawDataToPrinter(
      'Zebra_Printer_Name', // Replace with your printer name
      data,
      docName: 'ZPL Label',
      options: [
        OrientationOption(PrintOrientation.portrait),
      ],
    );

    if (success) {
      print('ZPL label printed successfully');
    } else {
      print('Failed to print ZPL label');
    }
  } catch (e) {
    print('Error printing ZPL: $e');
  }
}

// Example: Print ESC/POS receipt
Future<void> printReceipt() async {
  final List<int> escPosCommands = [
    // ESC/POS commands for receipt
    0x1B, 0x40, // Initialize printer
    0x1B, 0x61, 0x01, // Center alignment
    ...('RECEIPT\n').codeUnits,
    0x1B, 0x61, 0x00, // Left alignment
    ...('Item 1: \$10.00\n').codeUnits,
    ...('Item 2: \$15.00\n').codeUnits,
    ...('Total: \$25.00\n').codeUnits,
    0x1D, 0x56, 0x00, // Cut paper
  ];

  final Uint8List data = Uint8List.fromList(escPosCommands);

  bool success = await printingFfi.rawDataToPrinter(
    'Receipt_Printer_Name',
    data,
    docName: 'Receipt',
  );

  print('Receipt printed: $success');
}
```

### 3. PDF Printing

```dart
// Basic PDF printing
Future<void> printPdf() async {
  try {
    bool success = await printingFfi.printPdf(
      'HP_LaserJet_Printer', // Replace with your printer name
      '/path/to/your/document.pdf',
      docName: 'My Document',
      scaling: PdfPrintScaling.fitToPrintableArea,
      copies: 1,
    );

    if (success) {
      print('PDF printed successfully');
    } else {
      print('Failed to print PDF');
    }
  } catch (e) {
    print('Error printing PDF: $e');
  }
}

// Advanced PDF printing with options
Future<void> printPdfWithOptions() async {
  bool success = await printingFfi.printPdf(
    'Office_Printer',
    '/path/to/document.pdf',
    docName: 'Report',
    scaling: PdfPrintScaling.fitToPrintableArea,
    copies: 3,
    pageRange: PageRange.range(1, 5), // Print pages 1-5
    options: [
      OrientationOption(PrintOrientation.landscape),
      DuplexOption(DuplexMode.duplexLongEdge),
      CollateOption(true),
      ColorModeOption(PrintColorMode.color),
      PrintQualityOption(PrintQuality.high),
    ],
  );

  print('Advanced PDF printing: $success');
}

// Custom scaling
Future<void> printPdfCustomScale() async {
  bool success = await printingFfi.printPdf(
    'Printer_Name',
    '/path/to/document.pdf',
    scaling: PdfPrintScaling.custom(0.8), // 80% scale
    options: [
      AlignmentOption(PrintAlignment.center),
    ],
  );

  print('Custom scaled PDF: $success');
}
```

### 4. Print Job Management

```dart
// List print jobs for a specific printer
Future<void> managePrintJobs() async {
  try {
    List<PrintJob> jobs = await printingFfi.listPrintJobs('Office_Printer');

    for (PrintJob job in jobs) {
      print('Job ID: ${job.id}');
      print('Title: ${job.title}');
      print('Status: ${job.status}');
      print('Raw Status: ${job.rawStatus}');
      print('---');
    }

    // Pause a specific job
    if (jobs.isNotEmpty) {
      bool paused = await printingFfi.pausePrintJob('Office_Printer', jobs.first.id);
      print('Job paused: $paused');

      // Resume the job
      bool resumed = await printingFfi.resumePrintJob('Office_Printer', jobs.first.id);
      print('Job resumed: $resumed');

      // Cancel the job if needed
      // bool cancelled = await printingFfi.cancelPrintJob('Office_Printer', jobs.first.id);
    }
  } catch (e) {
    print('Error managing print jobs: $e');
  }
}

// Stream print jobs for real-time monitoring
void monitorPrintJobs() {
  printingFfi.listPrintJobsStream(
    'Office_Printer',
    pollInterval: Duration(seconds: 3),
  ).listen(
    (List<PrintJob> jobs) {
      print('Current jobs: ${jobs.length}');
      for (var job in jobs) {
        print('  ${job.title}: ${job.status}');
      }
    },
    onError: (error) => print('Error monitoring jobs: $error'),
  );
}
```

### 5. Track Print Job Status with Streams

```dart
// Print and track job status in real-time
void printAndTrackStatus() {
  // For raw data printing with status tracking
  printingFfi.rawDataToPrinterAndStreamStatus(
    'Label_Printer',
    Uint8List.fromList('Sample label data'.codeUnits),
    docName: 'Tracked Label',
    pollInterval: Duration(seconds: 1),
  ).listen(
    (PrintJob job) {
      print('Job ${job.id} status: ${job.status}');

      switch (job.status) {
        case PrintJobStatus.pending:
          print('Job is waiting to print...');
          break;
        case PrintJobStatus.printing:
          print('Job is currently printing...');
          break;
        case PrintJobStatus.completed:
        case PrintJobStatus.printed:
          print('Job completed successfully!');
          break;
        case PrintJobStatus.error:
          print('Job encountered an error!');
          break;
        case PrintJobStatus.canceled:
          print('Job was canceled.');
          break;
        default:
          print('Job status: ${job.status}');
      }
    },
    onError: (error) => print('Print tracking error: $error'),
    onDone: () => print('Print job tracking completed'),
  );

  // For PDF printing with status tracking
  printingFfi.printPdfAndStreamStatus(
    'Office_Printer',
    '/path/to/document.pdf',
    docName: 'Tracked PDF',
    copies: 2,
    pollInterval: Duration(seconds: 2),
  ).listen(
    (PrintJob job) => print('PDF Job ${job.id}: ${job.status}'),
    onError: (error) => print('PDF tracking error: $error'),
  );
}
```

### 6. Printer Capabilities (Windows)

```dart
// Get Windows printer capabilities
Future<void> getWindowsPrinterInfo() async {
  if (!Platform.isWindows) {
    print('This feature is Windows-only');
    return;
  }

  try {
    WindowsPrinterCapabilitiesModel? capabilities =
        await printingFfi.getWindowsPrinterCapabilities('HP_Printer');

    if (capabilities != null) {
      print('Printer Capabilities:');
      print('Color supported: ${capabilities.isColorSupported}');
      print('Monochrome supported: ${capabilities.isMonochromeSupported}');
      print('Landscape supported: ${capabilities.supportsLandscape}');

      print('\nPaper Sizes:');
      for (var size in capabilities.paperSizes) {
        print('  ${size.name}: ${size.widthMillimeters}x${size.heightMillimeters}mm');
      }

      print('\nPaper Sources:');
      for (var source in capabilities.paperSources) {
        print('  ${source.name} (ID: ${source.id})');
      }

      print('\nResolutions:');
      for (var res in capabilities.resolutions) {
        print('  ${res.xdpi}x${res.ydpi} DPI');
      }
    }
  } catch (e) {
    print('Error getting printer capabilities: $e');
  }
}

// Print with Windows-specific options
Future<void> printWithWindowsOptions() async {
  if (!Platform.isWindows) return;

  // First get capabilities to see available options
  var capabilities = await printingFfi.getWindowsPrinterCapabilities('HP_Printer');
  if (capabilities == null) return;

  // Use specific paper size and source
  var letterSize = capabilities.paperSizes.firstWhere(
    (size) => size.name.contains('Letter'),
    orElse: () => capabilities.paperSizes.first,
  );

  var tray1 = capabilities.paperSources.firstWhere(
    (source) => source.name.contains('Tray 1'),
    orElse: () => capabilities.paperSources.first,
  );

  bool success = await printingFfi.printPdf(
    'HP_Printer',
    '/path/to/document.pdf',
    options: [
      WindowsPaperSizeOption(letterSize.id),
      WindowsPaperSourceOption(tray1.id),
      OrientationOption(PrintOrientation.portrait),
      DuplexOption(DuplexMode.duplexLongEdge),
    ],
  );

  print('Windows-specific printing: $success');
}
```

### 7. CUPS Options (macOS/Linux)

```dart
// Get supported CUPS options for a printer
Future<void> getCupsOptions() async {
  if (Platform.isWindows) {
    print('CUPS options are not available on Windows');
    return;
  }

  try {
    List<CupsOptionModel> options =
        await printingFfi.getSupportedCupsOptions('Office_Printer');

    for (var option in options) {
      print('Option: ${option.name}');
      print('Default: ${option.defaultValue}');
      print('Supported values:');
      for (var choice in option.supportedValues) {
        print('  ${choice.choice}: ${choice.text}');
      }
      print('---');
    }
  } catch (e) {
    print('Error getting CUPS options: $e');
  }
}

// Print with custom CUPS options
Future<void> printWithCupsOptions() async {
  bool success = await printingFfi.printPdf(
    'Office_Printer',
    '/path/to/document.pdf',
    options: [
      GenericCupsOption('media', 'na_letter_8.5x11in'),
      GenericCupsOption('resolution', '600dpi'),
      GenericCupsOption('ColorModel', 'RGB'),
      GenericCupsOption('sides', 'two-sided-long-edge'),
    ],
  );

  print('CUPS options printing: $success');
}
```

### 8. Printer Properties Dialog (Windows)

```dart
// Open Windows printer properties dialog
Future<void> openPrinterProperties() async {
  if (!Platform.isWindows) {
    print('Printer properties dialog is Windows-only');
    return;
  }

  try {
    PrinterPropertiesResult result =
        await printingFfi.openPrinterProperties('HP_Printer');

    switch (result) {
      case PrinterPropertiesResult.ok:
        print('User clicked OK - settings may have been changed');
        break;
      case PrinterPropertiesResult.cancel:
        print('User canceled the dialog');
        break;
      case PrinterPropertiesResult.error:
        print('Error opening printer properties');
        break;
    }
  } catch (e) {
    print('Error: $e');
  }
}
```

### 9. Error Handling and Best Practices

```dart
class PrintingService {
  final PrintingFfi _printingFfi = PrintingFfi.instance;

  Future<bool> safePrint({
    required String printerName,
    required String pdfPath,
    int copies = 1,
  }) async {
    try {
      // Check if printer exists and is available
      final printers = _printingFfi.listPrinters();
      final printer = printers.firstWhere(
        (p) => p.name == printerName,
        orElse: () => throw PrintingFfiException('Printer not found: $printerName'),
      );

      if (!printer.isAvailable) {
        throw PrintingFfiException('Printer is not available: $printerName');
      }

      // Check if file exists
      if (!await File(pdfPath).exists()) {
        throw PrintingFfiException('PDF file not found: $pdfPath');
      }

      // Perform the print
      return await _printingFfi.printPdf(
        printerName,
        pdfPath,
        copies: copies,
        options: [
          OrientationOption(PrintOrientation.portrait),
          PrintQualityOption(PrintQuality.normal),
        ],
      );

    } on PrintingFfiException catch (e) {
      print('Printing error: ${e.message}');
      return false;
    } catch (e) {
      print('Unexpected error: $e');
      return false;
    }
  }

  void dispose() {
    _printingFfi.dispose();
  }
}
```

### 10. Complete Example Widget

```dart
class PrintingWidget extends StatefulWidget {
  @override
  _PrintingWidgetState createState() => _PrintingWidgetState();
}

class _PrintingWidgetState extends State<PrintingWidget> {
  final PrintingFfi _printingFfi = PrintingFfi.instance;
  List<Printer> _printers = [];
  String? _selectedPrinter;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    setState(() => _isLoading = true);
    try {
      _printers = _printingFfi.listPrinters();
      if (_printers.isNotEmpty) {
        _selectedPrinter = _printers.first.name;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading printers: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _printSampleLabel() async {
    if (_selectedPrinter == null) return;

    setState(() => _isLoading = true);
    try {
      const String zpl = '^XA^FO50,50^ADN,36,20^FDSample Label^FS^XZ';
      final data = Uint8List.fromList(zpl.codeUnits);

      bool success = await _printingFfi.rawDataToPrinter(
        _selectedPrinter!,
        data,
        docName: 'Sample Label',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Label printed!' : 'Print failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Printing FFI Demo')),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                DropdownButton<String>(
                  value: _selectedPrinter,
                  hint: Text('Select Printer'),
                  items: _printers.map((printer) {
                    return DropdownMenuItem(
                      value: printer.name,
                      child: Text('${printer.name} ${printer.isAvailable ? "✓" : "✗"}'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedPrinter = value);
                  },
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _selectedPrinter != null ? _printSampleLabel : null,
                  child: Text('Print Sample Label'),
                ),
                ElevatedButton(
                  onPressed: _loadPrinters,
                  child: Text('Refresh Printers'),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _printingFfi.dispose();
    super.dispose();
  }
}
```

This usage section covers all the major features of the plugin with practical examples that developers can adapt for their specific needs.

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
- **Drivers**: Update via `System Settings > Software Update` or the manufacturer's website (e.g., HP Smart app).

### Build Issues

- Ensure `libcups` is installed (`brew install cups`).
- Verify your `Podfile` includes `pod 'printing_ffi', :path => '../'`.
- To suppress the Xcode "Run Script" warning: In `macos/Runner.xcodeproj`, uncheck "Based on dependency analysis" in `Build Phases > Run Script`.
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