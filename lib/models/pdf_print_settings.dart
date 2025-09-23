/// Defines the scaling behavior for PDF printing on Windows.
sealed class PdfPrintScaling {
  /// The integer value passed to the native code.
  final int nativeValue;
  const PdfPrintScaling(this.nativeValue);

  /// **Fit to Printable Area**
  ///
  /// Scales the page (up or down) to fit perfectly within the printer's
  /// **printable area**, maintaining the aspect ratio. The printable area is
  /// the physical paper size minus any unprintable hardware margins.
  ///
  /// This is the safest scaling option to ensure no content is ever clipped.
  static const PdfPrintScaling fitToPrintableArea = PdfPrintScalingValue(0);

  @Deprecated('Use fitToPrintableArea instead. This will be removed in a future version.')
  static const PdfPrintScaling fitPage = fitToPrintableArea;

  /// **Actual Size**
  ///
  /// Prints the page without any scaling (100% scale). The content is centered
  /// on the paper. If the page is larger than the printable area, the content
  /// will be cropped.
  static const PdfPrintScaling actualSize = PdfPrintScalingValue(1);

  /// **Shrink to Fit**
  ///
  /// A conditional scaling mode:
  /// - If the page at its actual size is **larger** than the printable area, it
  ///   is scaled down to fit (behaving like `fitToPrintableArea`).
  /// - If the page at its actual size is **smaller** than or equal to the
  ///   printable area, it is printed without scaling (behaving like `actualSize`).
  ///
  /// This is useful for ensuring large documents are not cropped while preserving
  /// the original size of smaller documents.
  static const PdfPrintScaling shrinkToFit = PdfPrintScalingValue(2);

  /// **Fit to Paper**
  ///
  /// Scales the page (up or down) to fit the **entire physical paper size**,
  /// maintaining the aspect ratio.
  ///
  /// **Warning:** Content near the edges of the PDF page may be clipped by the
  /// printer's unprintable hardware margins. This mode is different from
  /// `fitToPrintableArea`, which respects these margins.
  static const PdfPrintScaling fitToPaper = PdfPrintScalingValue(3);

  /// **Custom Scale**
  ///
  /// Applies a custom scaling factor to the page.
  ///
  /// - [scale]: The scaling factor (e.g., 1.0 for 100%, 0.5 for 50%). Must be a positive number.
  const factory PdfPrintScaling.custom(double scale) = PdfPrintScalingCustom;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfPrintScaling || runtimeType != other.runtimeType) return false;
    if (other is PdfPrintScalingCustom && this is PdfPrintScalingCustom) {
      return (this as PdfPrintScalingCustom).scale == other.scale;
    }
    return nativeValue == other.nativeValue;
  }

  @override
  int get hashCode => nativeValue.hashCode;
}

class PdfPrintScalingValue extends PdfPrintScaling {
  const PdfPrintScalingValue(super.nativeValue);
}

class PdfPrintScalingCustom extends PdfPrintScaling {
  const PdfPrintScalingCustom(this.scale) : super(4);

  final double scale;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PdfPrintScalingCustom && runtimeType == other.runtimeType && scale == other.scale;

  @override
  int get hashCode => Object.hash(nativeValue, scale);
}

/// Represents a page range for printing.
///
/// This class provides a type-safe way to define which pages of a document to print.
/// It can represent a single page, a continuous range of pages, or a complex
/// combination of pages and ranges.
///
/// Example usage:
/// ```dart
/// // Print only page 5
/// final singlePage = PageRange.single(5);
///
/// // Print pages 2 through 7
/// final continuousRange = PageRange.range(2, 7);
///
/// // Print pages 1, 3-5, and 8
/// final complexRange = PageRange.multiple([
///   PageRange.single(1),
///   PageRange.range(3, 5),
///   PageRange.single(8),
/// ]);
///
/// // Parse from a string
/// final fromString = PageRange.parse("1-3,5,7-9");
/// ```
class PageRange {
  final String _value;

  // Private constructor to ensure values are always validated.
  PageRange._(this._value);

  /// Creates a page range representing a single page.
  ///
  /// Throws an [ArgumentError] if [page] is not positive.
  factory PageRange.single(int page) {
    if (page <= 0) {
      throw ArgumentError('Page number must be positive, but was $page.');
    }
    return PageRange._('$page');
  }

  /// Creates a page range from a [start] to an [end] page, inclusive.
  ///
  /// Throws an [ArgumentError] if pages are not positive or if [end] is less than [start].
  factory PageRange.range(int start, int end) {
    if (start <= 0) {
      throw ArgumentError('Start page must be positive, but was $start.');
    }
    if (end < start) {
      throw ArgumentError('End page ($end) cannot be less than start page ($start).');
    }
    return PageRange._('$start-$end');
  }

  /// Creates a complex page range by combining multiple [PageRange] objects.
  factory PageRange.multiple(List<PageRange> ranges) {
    if (ranges.isEmpty) {
      throw ArgumentError('The list of ranges cannot be empty.');
    }
    return PageRange._(ranges.map((r) => r.toValue()).join(','));
  }

  /// Parses a page range string (e.g., "1-3,5,7-9") into a [PageRange] object.
  ///
  /// Throws an [ArgumentError] if the format is invalid.
  factory PageRange.parse(String rangeString) {
    final trimmed = rangeString.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Page range string cannot be empty.');
    }
    // A simple regex to validate the overall structure. It's not exhaustive but catches most common errors.
    final RegExp validPageRange = RegExp(r'^\s*\d+(-\d+)?(\s*,\s*\d+(-\d+)?)*\s*$');
    if (!validPageRange.hasMatch(trimmed)) {
      throw ArgumentError('Invalid page range format: "$rangeString". Use a format like "1-3,5,7-9".');
    }
    // Further validation could be added here (e.g., check if end > start in all sub-ranges).
    return PageRange._(trimmed);
  }

  /// Returns the underlying string value of the page range.
  String toValue() => _value;

  @override
  String toString() => 'PageRange("$_value")';
}
