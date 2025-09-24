import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:printing_ffi/printing_ffi.dart';
import 'package:printing_ffi/printing_ffi_bindings_generated.dart';

// Create a mock class for PrintingFfiBindings using mocktail.
class MockPrintingFfiBindings extends Mock implements PrintingFfiBindings {}

void main() {
  late MockPrintingFfiBindings mockBindings;
  late PrintingFfi printing;

  setUp(() {
    // Create the mock object.
    mockBindings = MockPrintingFfiBindings();
    // Create an instance of PrintingFfi with the mock bindings.
    printing = PrintingFfi.forTest(mockBindings);
  });

  group('PrintingFfi Mocked Tests', () {
    test('listPrinters returns an empty list when native call returns null', () {
      // Arrange: Configure the mock to return a null pointer.
      when(() => mockBindings.get_printers()).thenReturn(nullptr);

      // Act: Call the method under test.
      final printers = printing.listPrinters();

      // Assert: Verify the result and that the native function was called.
      expect(printers, isEmpty);
      verify(() => mockBindings.get_printers()).called(1);
    });

    test('listPrinters correctly parses and returns a list of printers', () {
      // Arrange: Set up a complex native-like data structure in memory using ffi.
      // This is an advanced test that requires careful memory management.
      final printerArray = calloc<PrinterInfo>(1);
      printerArray[0].name = 'Test Printer 1'.toNativeUtf8().cast();
      printerArray[0].model = 'Model-X'.toNativeUtf8().cast();
      printerArray[0].url = ''.toNativeUtf8().cast();
      printerArray[0].location = ''.toNativeUtf8().cast();
      printerArray[0].comment = ''.toNativeUtf8().cast();
      printerArray[0].is_default = true;

      final printerList = calloc<PrinterList>();
      printerList.ref.count = 1;
      printerList.ref.printers = printerArray;

      final printerListPtr = printerList;

      when(() => mockBindings.get_printers()).thenReturn(printerListPtr);

      // Act
      final printers = printing.listPrinters();

      // Assert
      expect(printers, hasLength(1));
      expect(printers.first.name, 'Test Printer 1');
      expect(printers.first.model, 'Model-X');
      expect(printers.first.isDefault, isTrue);

      // Verify that the free function is called to prevent memory leaks.
      verify(() => mockBindings.free_printer_list(printerListPtr)).called(1);

      // Clean up allocated memory.
      calloc.free(printerArray[0].name);
      calloc.free(printerArray[0].model);
      calloc.free(printerArray[0].url);
      calloc.free(printerArray[0].location);
      calloc.free(printerArray[0].comment);
      calloc.free(printerArray);
      calloc.free(printerList);
    });

    test('getDefaultPrinter returns null when native call returns a null pointer', () {
      // Arrange
      when(() => mockBindings.get_default_printer()).thenReturn(nullptr);

      // Act
      final printer = printing.getDefaultPrinter();

      // Assert
      expect(printer, isNull);
      verify(() => mockBindings.get_default_printer()).called(1);
    });

    test('_buildOptions correctly converts PrintOption list to a map', () {
      // Arrange
      final options = [
        const OrientationOption(WindowsOrientation.landscape),
        const ColorModeOption(ColorMode.color),
      ];

      // Act
      final result = printing.buildOptions(options);

      // Assert
      expect(result, {'orientation': 'landscape', 'color-mode': 'color'});
    });
  });
}
