import 'pdf_print_settings.dart';

/// Defines the orientation for printing on Windows.
enum WindowsOrientation {
  /// Portrait orientation (short edge is top).
  portrait(1),

  /// Landscape orientation (long edge is top).
  landscape(2);

  const WindowsOrientation(this.value);
  final int value;
}

/// Defines the color mode for printing.
enum ColorMode { monochrome, color }

/// Defines the quality for printing.
///
/// These correspond to standard driver settings. `normal` is equivalent to
/// the driver's default medium quality.
enum PrintQuality { draft, low, normal, high }

/// Defines the duplex printing mode.
enum DuplexMode {
  /// Print on one side only (single-sided).
  singleSided,

  /// Print on both sides, flip on long edge (book-style).
  /// This is the standard duplex mode for documents like books.
  duplexLongEdge,

  /// Print on both sides, flip on short edge (notepad-style).
  /// This is used for documents that are bound along the short edge.
  duplexShortEdge,
}

/// Defines the alignment for PDF printing on Windows.
enum PdfPrintAlignment {
  center,
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

/// Represents a generic printing option to be passed to print functions.
sealed class PrintOption {
  const PrintOption();
}

/// A Windows-specific option to set the paper size by its ID.
/// The ID can be obtained from [WindowsPrinterCapabilities].
class WindowsPaperSizeOption extends PrintOption {
  final int id;
  const WindowsPaperSizeOption(this.id);
}

/// A Windows-specific option to set the paper source (tray/bin) by its ID.
/// The ID can be obtained from [WindowsPrinterCapabilities].
class WindowsPaperSourceOption extends PrintOption {
  final int id;
  const WindowsPaperSourceOption(this.id);
}

/// An option to set the page orientation.
class OrientationOption extends PrintOption {
  final WindowsOrientation orientation;
  const OrientationOption(this.orientation);
}

/// An option to set the color mode (e.g., monochrome or color).
class ColorModeOption extends PrintOption {
  final ColorMode mode;
  const ColorModeOption(this.mode);
}

/// An option to set the print quality.
class PrintQualityOption extends PrintOption {
  final PrintQuality quality;
  const PrintQualityOption(this.quality);
}

/// A Windows-specific option to set the media type (e.g., "Plain Paper", "Glossy Photo") by its ID.
/// The ID can be obtained from [WindowsPrinterCapabilities].
class WindowsMediaTypeOption extends PrintOption {
  final int id;
  const WindowsMediaTypeOption(this.id);
}

/// A generic CUPS option, represented as a key-value pair.
/// The available options can be discovered using [getSupportedCupsOptions].
class GenericCupsOption extends PrintOption {
  final String name;
  final String value;
  const GenericCupsOption(this.name, this.value);
}

/// A Windows-specific option to set the alignment of the printed content.
class AlignmentOption extends PrintOption {
  final PdfPrintAlignment alignment;
  const AlignmentOption(this.alignment);
}

/// An option to set the collate mode for multiple copies.
///
/// For duplex printing (front/back), this controls how multiple copies are arranged:
///
/// **When true (collated)**: Pages are grouped by copy
/// - Copy 1: Page 1, Page 2, Page 3, Page 4, Page 5, Page 6
/// - Copy 2: Page 1, Page 2, Page 3, Page 4, Page 5, Page 6
///
/// **When false (non-collated)**: Pages are grouped by page number
/// - All copies of Page 1, then all copies of Page 2, etc.
/// - Page 1, Page 1, Page 2, Page 2, Page 3, Page 3, Page 4, Page 4, Page 5, Page 5, Page 6, Page 6
///
/// This is particularly useful for duplex printing where you want complete copies
/// to be printed together rather than all copies of each page.
class CollateOption extends PrintOption {
  final bool collate;
  const CollateOption(this.collate);
}

/// An option to set the duplex printing mode.
///
/// This controls whether and how pages are printed on both sides of the paper:
///
/// - [DuplexMode.singleSided]: Print on one side only
/// - [DuplexMode.duplexLongEdge]: Print on both sides, flip on long edge (book-style)
/// - [DuplexMode.duplexShortEdge]: Print on both sides, flip on short edge (notepad-style)
///
/// Note: The actual duplex printing depends on the printer's capabilities.
/// If the printer doesn't support duplex printing, single-sided printing will be used.
class DuplexOption extends PrintOption {
  final DuplexMode mode;
  const DuplexOption(this.mode);
}

/// An option to set the rotation for PDF printing on Windows.
///
/// This overrides the rotation specified in the PDF document itself.
class PdfRotationOption extends PrintOption {
  final PdfRotation rotation;
  const PdfRotationOption(this.rotation);
}
