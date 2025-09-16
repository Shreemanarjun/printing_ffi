## 0.0.8

* ✨ **FEAT(example)**: Implemented the entire example app UI using the `shadcn_ui` package for a modern, clean, and responsive user experience.
* ✨ **FEAT(example)**: Enhanced raw data printing with a data type selector (ZPL, ESC/POS, Custom) and provided corresponding example data.
* **FIX**: Corrected conditional compilation for error handling, resolving an issue where `set_last_error` was not defined for all platforms, leading to compilation errors on non-Windows targets. 🐛
* **FIX**: Resolved an 'undefined' compiler error for the `_scale_to_fit` helper function by ensuring it is defined on all platforms. 🛠️

## 0.0.7

* **FEAT**: Added support for collating copies on Windows. 📚
* **FEAT**: Enhanced error handling, providing detailed native error messages and a real-time logging callback for easier debugging. 🕵️‍♂️
* **FEAT**: Enhanced PDF printing on Windows with `Fit to Paper` and `Custom` scaling options. 📄✨
* **FIX**: Resolved PDF rendering issues on Windows, including color distortion and page stretching on high-DPI displays, by using a 32-bit BGRA bitmap format for improved compatibility. 🐛🎨
* **FIX*a*: Improved stability by addressing a memory leak and enhancing resource cleanup during print failures on Windows.
* **REFACTOR**: Improved Windows print driver compatibility by streamlining device setting modifications, reducing the risk of conflicts. ♻️
* **EXAMPLE**: Added PDF file selection and custom scale validation to the example app. 🎨
* **DOCS**: Updated documentation for new features and error handling. 📝

## 0.0.6

* **FEAT**: Added support for opening the native Windows printer properties dialog via `openPrinterProperties`. 🎛️
* **FEAT**: Added support for setting Paper Size, Paper Source, and Orientation on Windows for both PDF and raw data printing. 📄⚙️
* **FEAT**: Added support for passing generic CUPS options to raw data print jobs on macOS and Linux. 🐧🍎
* **REFACTOR**: Refactored the Dart FFI layer to use generated bindings directly, removing manual lookups and improving maintainability. ✨
* **EXAMPLE**: Updated the example app with UI controls for new Windows printing options and a button to show printer properties. 🎨

## 0.0.5

* **FEAT**: Added support for `copies` and `pageRange` when printing PDFs on Windows and CUPS-based systems. 🔢
* **FEAT**: Refactored the `pageRange` parameter to use a type-safe `PageRange` class, improving API clarity and preventing invalid format errors. 🔒
* **DOCS**: Updated documentation for new printing parameters and the `PageRange` class. 📝
* **EXAMPLE**: Added UI controls for setting the number of copies and page range in the example app. 🎨

## 0.0.4

* **DOCS**: Updated `pubspec.yaml` with repository, homepage, issue tracker links,license and relevant topics for better discoverability on pub.dev.

## 0.0.3

* **FEAT**: Added full support for Linux via CUPS. 🚀
* **FEAT**: Added job status tracking streams for PDF and raw data printing. 📊
* **FEAT**: Added `getWindowsPrinterCapabilities` to fetch supported paper sizes and resolutions on Windows. 🖨️
* ✨ **FEAT**: Improved error handling and Windows printer capabilities:
    *   Enhanced isolate communication with robust error responses.
    *   Switched to Unicode (W-series) Windows APIs for full international character support in printer and document names.
    *   Improved memory management and error handling in `get_windows_printer_capabilities`.
    *   Added `NULL` checks for pointers returned by Windows API functions to prevent crashes.
    *   Improved logging for easier debugging.
* **DOCS**: Updated README with Linux setup instructions and new features. 📝

## 0.0.2

* **FIX**: Resolved a crash on Windows when printing by correctly quoting the printer name for the shell API.
* **FIX**: Updated the Windows build script to use the correct URL and latest version of the `pdfium` library, resolving download errors.
* **FEAT**: Added `PdfPrintScaling` option to the `printPdf` function on Windows to control scaling ('Fit to Page' vs 'Actual Size').
* **FIX**: Replaced unreliable `ShellExecute` PDF printing on Windows with a robust, self-contained solution using the `pdfium` library for rendering. This removes the dependency on external PDF applications.
* **FIX**: Correctly specified "raw" printing option for CUPS on macOS/Linux to ensure raw data is sent to the printer without modification.
* **FEAT**: Added extensive logging to the native C code, enabled in debug builds, to simplify troubleshooting.
* **FEAT**: Added `printPdf` function to print PDF files directly to a specified printer.

## 0.0.1

* **Initial Release**
* Added support for listing printers on macOS (via CUPS) and Windows (via winspool), including offline printers.
* Implemented raw data printing for sending formats like ZPL and ESC/POS directly to printers.
* Included print job management features: list, pause, resume, and cancel jobs.
* Utilizes FFI for direct native API communication, ensuring high performance.
