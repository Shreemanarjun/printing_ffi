## 0.0.11
* **DOCS**: Updated `README.md` with detailed instructions for usage of available API's.


## 0.0.10

* ✨ **FEAT**: Added support for printing multiple copies of PDF documents on Windows. The printer driver now handles copy collation, improving performance and reliability. 🔢
* ✨ **FEAT**: Exposed `initPdfium()` for explicit PDFium library initialization on Windows. This improves compatibility with other PDF plugins (like `pdfrx`) and ensures thread-safe, idempotent initialization.
* ✨ **FEAT**: Added a `PdfRotation` option for PDF printing on Windows, allowing users to override the document's default rotation (e.g., `auto`, `none`, `rotate90`).
* ✨ **FEAT**: Added a comprehensive suite of mock tests using `mocktail` to validate class behavior, including synchronous and asynchronous methods, without requiring a native environment.
* **REFACTOR**: Simplified the Windows PDF printing implementation by removing the manual copy loop. The native `dmCopies` setting in the `DEVMODE` structure is now used, delegating the work to the printer driver for better efficiency. ♻️
* **REFACTOR**: Refactored the `PrintingFfi` class to support dependency injection, significantly improving testability. This includes a new `PrintingFfi.forTest` constructor for injecting mock bindings. 🧪
* ✨ **FEAT(example)**: The example app now includes fields to specify the number of copies and select page rotation for PDF printing.
* ✨ **FEAT(example)**: Enhanced the print job status tracking dialog with more detailed feedback, clearer status transitions, and a synthetic "completed" status for finished jobs.
* **FIX**: Corrected the dynamic library (`.dylib`) loading logic on macOS to work reliably in both test and application environments. 🐛
* **FIX**: Implemented `shutdown_pdfium_library()` to ensure proper cleanup of PDFium resources on Windows, preventing potential resource leaks. 🛠️
* **FIX**: Ensured the `PrintingFfi` private constructor correctly initializes native bindings, preventing potential runtime errors. 🛠️
* **BUILD**: Removed unnecessary `android` and `ios` platform declarations from `pubspec.yaml`.
* **BUILD**: Added `mocktail` as a `dev_dependency` to support the new testing infrastructure.
* **DOCS**: Updated `README.md` with detailed instructions for the new explicit PDFium initialization.

## 0.0.9

* ✨ **FEAT**: Added full support for duplex (double-sided) printing on Windows, macOS, and Linux. Users can now select single-sided, duplex long-edge (book-style), or duplex short-edge (notepad-style) printing. 📖
* ✨ **FEAT(example)**: Refined the example app with `shadcn_ui` components, including a dedicated platform settings card and responsive layouts for a better user experience. 🎨
* **REFACTOR**: Translated generic print options (like `orientation`, `color-mode`, `duplex`) into platform-specific CUPS options (`orientation-requested`, `print-color-mode`, `sides`) within the Dart isolate, simplifying the native C code and improving cross-platform consistency. ♻️
* **DOCS**: Updated `README.md` to include documentation for the new duplex printing feature. 📝

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
