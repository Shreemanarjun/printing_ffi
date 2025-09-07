# printing_ffi 🖨️

A Flutter plugin for direct printer communication using native FFI (Foreign Function Interface) bindings. This plugin enables listing printers (including offline ones), sending raw print data, and managing print jobs on macOS (via CUPS) and Windows (via winspool). It is designed for low-level printing tasks, offering improved performance and flexibility over solutions like the `printing` package. 🚀

## Features 🌟

- **List Printers** 📋: Retrieve all available printers, including offline ones, with their current status (e.g., `Idle`, `Printing`, `Offline`).
- **Raw Data Printing** 📦: Send raw print data (e.g., ZPL, ESC/POS) directly to printers, bypassing document rendering.
- **Print Job Management** ⚙️: List, pause, resume, and cancel print jobs for a selected printer.
- **Cross-Platform** 🌐: Supports macOS (CUPS) and Windows (winspool), with Linux support planned.
- **Offline Printer Support** 🔌: Lists offline printers on macOS using `cupsGetDests`, addressing a key limitation of other plugins.
- **Native Performance** ⚡: Uses FFI to interface directly with native printing APIs, reducing overhead and improving speed.
- **UI Feedback** 🔔: Includes an example app with a user-friendly interface, empty states, and snackbar notifications for errors and status updates.

## Installation 📦

Add the following to your `pubspec.yaml`:

```yaml
dependencies:
  printing_ffi:
    path: ../ # Use the path to the plugin directory if local, or specify version for pub.dev
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

## Usage 📖

The plugin provides a Dart API to interact with printers and print jobs. Below is an example using the provided `example/lib/main.dart`:

### Example Code

```dart
import 'package:flutter/material.dart';
import 'package:printing_ffi/printing_ffi.dart';
import 'dart:io';
import 'dart:typed_data';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Printing Plugin Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        cardTheme: CardTheme(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      home: const PrinterScreen(),
    );
  }
}

class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});

  @override
  _PrinterScreenState createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  String? selectedPrinter;
  List<PrintJob> jobs = [];
  List<Map<String, dynamic>> printers = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    setState(() => isLoading = true);
    try {
      final printerList = listPrinters();
      setState(() {
        printers = printerList;
        selectedPrinter = printers.isNotEmpty ? printers.first['name'] : null;
        isLoading = false;
        if (selectedPrinter != null) {
          _loadJobs();
        } else {
          jobs = [];
        }
      });
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('Error loading printers: $e', isError: true);
    }
  }

  Future<void> _loadJobs() async {
    if (selectedPrinter == null) return;
    setState(() => isLoading = true);
    try {
      final jobList = await listPrintJobs(selectedPrinter!);
      setState(() {
        jobs = jobList;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('Error loading print jobs: $e', isError: true);
    }
  }

  Future<void> _printTest() async {
    if (selectedPrinter == null) {
      _showSnackBar('No printer selected', isError: true);
      return;
    }
    final printer = printers.firstWhere((p) => p['name'] == selectedPrinter);
    if (printer['state'] == 5 || (Platform.isWindows && (printer['state'] & 0x80) != 0)) {
      _showSnackBar('Cannot print: Printer is offline', isError: true);
      return;
    }
    setState(() => isLoading = true);
    try {
      final rawData = Uint8List.fromList([0x1B, 0x40, 0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x0A]);
      final success = await rawDataToPrinter(selectedPrinter!, rawData);
      setState(() => isLoading = false);
      _showSnackBar(success ? 'Print job sent successfully' : 'Failed to send print job', isError: !success);
      await _loadJobs();
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('Error printing: $e', isError: true);
    }
  }

  Future<void> _pausePrintJob(int jobId) async {
    if (selectedPrinter == null) return;
    setState(() => isLoading = true);
    try {
      final success = await pausePrintJob(selectedPrinter!, jobId);
      setState(() => isLoading = false);
      _showSnackBar(success ? 'Job paused successfully' : 'Failed to pause job', isError: !success);
      await _loadJobs();
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('Error pausing job: $e', isError: true);
    }
  }

  Future<void> _resumePrintJob(int jobId) async {
    if (selectedPrinter == null) return;
    setState(() => isLoading = true);
    try {
      final success = await resumePrintJob(selectedPrinter!, jobId);
      setState(() => isLoading = false);
      _showSnackBar(success ? 'Job resumed successfully' : 'Failed to resume job', isError: !success);
      await _loadJobs();
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('Error resuming job: $e', isError: true);
    }
  }

  Future<void> _cancelPrintJob(int jobId) async {
    if (selectedPrinter == null) return;
    setState(() => isLoading = true);
    try {
      final success = await cancelPrintJob(selectedPrinter!, jobId);
      setState(() => isLoading = false);
      _showSnackBar(success ? 'Job canceled successfully' : 'Failed to cancel job', isError: !success);
      await _loadJobs();
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('Error canceling job: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Printing Plugin Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Select Printer: ',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: selectedPrinter,
                  hint: const Text('No printers found'),
                  items: printers.map((printer) {
                    return DropdownMenuItem<String>(
                      value: printer['name'],
                      child: Text(
                        '${printer['name']} ${printer['state'] == 5 || (Platform.isWindows && (printer['state'] & 0x80) != 0) ? '(Offline)' : ''}',
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedPrinter = value;
                      if (value != null) {
                        _loadJobs();
                      } else {
                        jobs = [];
                      }
                    });
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh Printers',
                  onPressed: _loadPrinters,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.print),
                  label: const Text('Print Test'),
                  onPressed: isLoading || selectedPrinter == null ? null : _printTest,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Jobs'),
                  onPressed: isLoading || selectedPrinter == null ? null : _loadJobs,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (printers.isEmpty)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.print_disabled, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No printers found',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      Text(
                        'Please connect a printer and refresh',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else if (jobs.isEmpty)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.description, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No print jobs found',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      Text(
                        'Try printing a test document',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: jobs.length,
                  itemBuilder: (context, index) {
                    final job = jobs[index];
                    return Card(
                      child: ListTile(
                        title: Text(
                          job.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('ID: ${job.id}, Status: ${job.statusDescription}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.pause, color: Colors.blue),
                              tooltip: 'Pause Job',
                              onPressed: isLoading ? null : () => _pausePrintJob(job.id),
                            ),
                            IconButton(
                              icon: const Icon(Icons.play_arrow, color: Colors.green),
                              tooltip: 'Resume Job',
                              onPressed: isLoading ? null : () => _resumePrintJob(job.id),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              tooltip: 'Cancel Job',
                              onPressed: isLoading ? null : () => _cancelPrintJob(job.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

Or add it manually:

```yaml
dependencies:
  printing_ffi: ^0.0.1 # Use the latest version
```

This configuration invokes the native build for the various target platforms
and bundles the binaries in Flutter applications using these FFI plugins.

This can be combined with dartPluginClass, such as when FFI is used for the
implementation of one platform in a federated plugin:

```yaml
  plugin:
    implements: some_other_plugin
    platforms:
      some_platform:
        dartPluginClass: SomeClass
        ffiPlugin: true
```

A plugin can have both FFI and method channels:

```yaml
  plugin:
    platforms:
      some_platform:
        pluginClass: SomeName
        ffiPlugin: true
```

The native build systems that are invoked by FFI (and method channel) plugins are:

* For Android: Gradle, which invokes the Android NDK for native builds.
  * See the documentation in android/build.gradle.
* For iOS and MacOS: Xcode, via CocoaPods.
  * See the documentation in ios/printing_ffi.podspec.
  * See the documentation in macos/printing_ffi.podspec.
* For Linux and Windows: CMake.
  * See the documentation in linux/CMakeLists.txt.
  * See the documentation in windows/CMakeLists.txt.

## Binding to native code

To use the native code, bindings in Dart are needed.
To avoid writing these by hand, they are generated from the header file
(`src/printing_ffi.h`) by `package:ffigen`.
Regenerate the bindings by running `dart run ffigen --config ffigen.yaml`.

## Invoking native code

Very short-running native functions can be directly invoked from any isolate.
For example, see `sum` in `lib/printing_ffi.dart`.

Longer-running functions should be invoked on a helper isolate to avoid
dropping frames in Flutter applications.
For example, see `sumAsync` in `lib/printing_ffi.dart`.

## Flutter help

For help getting started with Flutter, view our
[online documentation](https://docs.flutter.dev), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
