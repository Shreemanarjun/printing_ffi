import 'dart:ffi';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:printing_ffi/printing_ffi.dart';
import 'package:printing_ffi/printing_ffi_bindings_generated.dart';

// Create a mock class for PrintingFfiBindings using mocktail.
class MockPrintingFfiBindings extends Mock implements PrintingFfiBindings {}

class MockSendPort extends Mock implements SendPort {}

void main() {
  late MockPrintingFfiBindings mockBindings;
  late PrintingFfi printingFfi;
  late MockSendPort mockSendPort;

  setUp(() {
    // Create the mock object.
    mockBindings = MockPrintingFfiBindings();
    mockSendPort = MockSendPort();

    // Create an instance of PrintingFfi with the mock bindings.
    // This instance bypasses isolate creation and uses the mock bindings directly
    // for synchronous methods.
    printingFfi = PrintingFfi.forTest(
      mockBindings,
      // Inject a future that completes with our mock SendPort for async tests.
      helperIsolateSendPortFuture: Future.value(mockSendPort),
    );

    // Register fallback values for functions that return void.
    registerFallbackValue(nullptr);
  });

  group('PrintingFfi Mocked Tests', () {
    test('listPrinters returns an empty list when native call returns null', () {
      // Arrange: Configure the mock to return a null pointer.
      when(() => mockBindings.get_printers()).thenReturn(nullptr);

      // Act: Call the method under test.
      final printers = printingFfi.listPrinters();

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
      final printers = printingFfi.listPrinters();

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
      final printer = printingFfi.getDefaultPrinter();

      // Assert
      expect(printer, isNull);
      verify(() => mockBindings.get_default_printer()).called(1);
    });

    test('getDefaultPrinter returns a valid printer when native call succeeds', () {
      // Arrange
      final printerInfo = calloc<PrinterInfo>();
      printerInfo.ref.name = 'Default Printer'.toNativeUtf8().cast();
      printerInfo.ref.model = 'Default-Model'.toNativeUtf8().cast();
      printerInfo.ref.url = ''.toNativeUtf8().cast();
      printerInfo.ref.location = ''.toNativeUtf8().cast();
      printerInfo.ref.comment = ''.toNativeUtf8().cast();
      printerInfo.ref.is_default = true;

      when(() => mockBindings.get_default_printer()).thenReturn(printerInfo);
      when(() => mockBindings.free_printer_info(any())).thenAnswer((_) {});

      // Act
      final printer = printingFfi.getDefaultPrinter();

      // Assert
      expect(printer, isNotNull);
      expect(printer!.name, 'Default Printer');
      expect(printer.model, 'Default-Model');
      expect(printer.isDefault, isTrue);

      verify(() => mockBindings.get_default_printer()).called(1);
      verify(() => mockBindings.free_printer_info(printerInfo)).called(1);

      // Clean up
      calloc.free(printerInfo.ref.name);
      calloc.free(printerInfo.ref.model);
      calloc.free(printerInfo.ref.url);
      calloc.free(printerInfo.ref.location);
      calloc.free(printerInfo.ref.comment);
      calloc.free(printerInfo);
    });

    test('_buildOptions correctly converts PrintOption list to a map', () {
      // Arrange
      final options = [
        const OrientationOption(WindowsOrientation.landscape),
        const ColorModeOption(ColorMode.color),
      ];

      // Act
      final result = printingFfi.buildOptions(options);

      // Assert
      expect(result, {'orientation': 'landscape', 'color-mode': 'color'});
    });

    test('initPdfium calls the native binding on Windows', () {
      // This test is platform-specific and relies on debug-mode behavior.
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      when(() => mockBindings.init_pdfium_library()).thenAnswer((_) {});
      printingFfi.initPdfium();
      verify(() => mockBindings.init_pdfium_library()).called(1);
      debugDefaultTargetPlatformOverride = null; // Reset to default
    });

    group('getWindowsPrinterCapabilities', () {
      test('returns null on non-Windows platforms', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final capabilities = await printingFfi.getWindowsPrinterCapabilities('Test Printer');
        expect(capabilities, isNull);
        verifyNever(() => mockSendPort.send(any()));
        debugDefaultTargetPlatformOverride = null;
      });

      test('returns capabilities on success', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        when(() => mockSendPort.send(any())).thenAnswer((_) {});
        final mockCaps = WindowsPrinterCapabilitiesModel(
          paperSizes: [WindowsPaperSize(id: 1, name: 'A4', widthMillimeters: 210, heightMillimeters: 297)],
          paperSources: [],
          mediaTypes: [],
          resolutions: [],
          isColorSupported: true,
          isMonochromeSupported: true,
          supportsLandscape: true,
        );

        final future = printingFfi.getWindowsPrinterCapabilities('Test Printer');

        await Future.microtask(() {});
        final captured = verify(() => mockSendPort.send(captureAny(that: isA<GetWindowsCapsRequest>()))).captured;
        final request = captured.last as GetWindowsCapsRequest;
        printingFfi.handleIsolateMessageForTest(GetWindowsCapsResponse(request.id, mockCaps));

        final result = await future;
        expect(result, isNotNull);
        expect(result!.paperSizes.first.name, 'A4');
        debugDefaultTargetPlatformOverride = null;
      });
    });

    group('getSupportedCupsOptions', () {
      test('returns empty list on non-CUPS platforms', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        final options = await printingFfi.getSupportedCupsOptions('Test Printer');
        expect(options, isEmpty);
        verifyNever(() => mockSendPort.send(any()));
        debugDefaultTargetPlatformOverride = null;
      });

      test('returns options on success', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        when(() => mockSendPort.send(any())).thenAnswer((_) {});
        final mockOptions = [
          CupsOptionModel(name: 'print-quality', defaultValue: '4', supportedValues: []),
        ];

        final future = printingFfi.getSupportedCupsOptions('Test Printer');

        await Future.microtask(() {});
        final captured = verify(() => mockSendPort.send(captureAny(that: isA<GetCupsOptionsRequest>()))).captured;
        final request = captured.last as GetCupsOptionsRequest;
        printingFfi.handleIsolateMessageForTest(GetCupsOptionsResponse(request.id, mockOptions));

        final result = await future;
        expect(result, isNotEmpty);
        expect(result.first.name, 'print-quality');
        debugDefaultTargetPlatformOverride = null;
      });
    });

    group('openPrinterProperties', () {
      test('returns error on non-Windows platforms', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final result = await printingFfi.openPrinterProperties('Test Printer');
        expect(result, PrinterPropertiesResult.error);
        verifyNever(() => mockSendPort.send(any()));
        debugDefaultTargetPlatformOverride = null;
      });

      for (final testCase in [
        {'response': PrinterPropertiesResult.ok, 'label': 'OK'},
        {'response': PrinterPropertiesResult.cancel, 'label': 'Cancel'},
        {'response': PrinterPropertiesResult.error, 'label': 'Error'},
      ]) {
        test('completes with ${testCase['label']} on response', () async {
          debugDefaultTargetPlatformOverride = TargetPlatform.windows;
          when(() => mockSendPort.send(any())).thenAnswer((_) {});

          final future = printingFfi.openPrinterProperties('Test Printer');

          await Future.microtask(() {});
          final captured = verify(() => mockSendPort.send(captureAny(that: isA<OpenPrinterPropertiesRequest>()))).captured;
          final request = captured.last as OpenPrinterPropertiesRequest;
          printingFfi.handleIsolateMessageForTest(
            OpenPrinterPropertiesResponse(request.id, testCase['response']! as PrinterPropertiesResult),
          );

          final result = await future;
          expect(result, testCase['response']);
          debugDefaultTargetPlatformOverride = null;
        });
      }
    });

    test('listPrintJobs returns an empty list when no jobs are present', () async {
      // Arrange
      when(() => mockSendPort.send(any())).thenAnswer((_) {});

      // Act
      final future = printingFfi.listPrintJobs('Test Printer');

      // Simulate the isolate sending back an empty response.
      await Future.microtask(() {});
      final captured = verify(() => mockSendPort.send(captureAny())).captured;
      final request = captured.last as PrintJobsRequest;
      printingFfi.handleIsolateMessageForTest(PrintJobsResponse(request.id, []));
      final jobs = await future;

      // Assert
      expect(jobs, isEmpty);
    });

    test('listPrintJobs returns a list of print jobs', () async {
      // Arrange
      when(() => mockSendPort.send(any())).thenAnswer((_) {});
      final mockJob = PrintJob(123, 'Test Document', 4); // Status: PROCESSING

      // Act
      final future = printingFfi.listPrintJobs('Test Printer');

      // Simulate the isolate sending back a response with one job.
      await Future.microtask(() {});
      final captured = verify(() => mockSendPort.send(captureAny())).captured;
      final request = captured.last as PrintJobsRequest;
      printingFfi.handleIsolateMessageForTest(PrintJobsResponse(request.id, [mockJob]));
      final jobs = await future;

      // Assert
      expect(jobs, hasLength(1));
      expect(jobs.first.id, 123);
      expect(jobs.first.title, 'Test Document');
    });

    test('listPrintJobs throws an exception on error response', () async {
      // Arrange
      when(() => mockSendPort.send(any())).thenAnswer((_) {});
      final exception = PrintingFfiException('Failed to list jobs');

      // Act
      final future = printingFfi.listPrintJobs('Test Printer');

      // Simulate the isolate sending back an error response.
      await Future.microtask(() {});
      final captured = verify(() => mockSendPort.send(captureAny())).captured;
      final request = captured.last as PrintJobsRequest;
      printingFfi.handleIsolateMessageForTest(ErrorResponse(request.id, exception, StackTrace.current));

      // Assert
      expect(future, throwsA(isA<PrintingFfiException>()));
    });

    test('printPdf sends correct request and completes on success response', () async {
      // Arrange
      when(() => mockSendPort.send(any())).thenAnswer((_) {});

      // Act
      final future = printingFfi.printPdf(
        'Test Printer',
        '/path/to/doc.pdf',
        docName: 'My Test PDF',
        scaling: PdfPrintScaling.actualSize,
        copies: 2,
        pageRange: PageRange.parse('1-2'),
        options: [const ColorModeOption(ColorMode.monochrome)],
      );

      // Simulate the isolate sending back a success response.
      await Future.microtask(() {});
      final captured = verify(() => mockSendPort.send(captureAny())).captured;
      final request = captured.last as PrintPdfRequest;
      printingFfi.handleIsolateMessageForTest(PrintPdfResponse(request.id, true));
      final result = await future;

      // Assert
      expect(result, isTrue);
      expect(request.printerName, 'Test Printer');
      expect(request.pdfFilePath, '/path/to/doc.pdf');
      expect(request.docName, 'My Test PDF');
      expect(request.scalingMode, PdfPrintScaling.actualSize.nativeValue);
      expect(request.copies, 2);
      expect(request.pageRange, '1-2');
      expect(request.options, containsPair('color-mode', 'monochrome'));
    });

    test('printPdf throws an exception on error response', () async {
      // Arrange
      when(() => mockSendPort.send(any())).thenAnswer((_) {});
      final exception = PrintingFfiException('Native print error');

      // Act
      final future = printingFfi.printPdf(
        'Test Printer',
        '/path/to/doc.pdf',
      );

      // Simulate the isolate sending back an error response.
      await Future.microtask(() {});
      final captured = verify(() => mockSendPort.send(captureAny())).captured;
      final request = captured.last as PrintPdfRequest;
      printingFfi.handleIsolateMessageForTest(ErrorResponse(request.id, exception, StackTrace.current));
      // Assert
      expect(future, throwsA(isA<PrintingFfiException>()));
    });

    test('rawDataToPrinter sends correct request and completes on success', () async {
      // Arrange
      when(() => mockSendPort.send(any())).thenAnswer((_) {});
      final testData = Uint8List.fromList([1, 2, 3]);

      // Act
      final future = printingFfi.rawDataToPrinter(
        'Test Raw Printer',
        testData,
        docName: 'My Raw Doc',
        options: [const GenericCupsOption('raw', 'true')],
      );

      // Simulate isolate response
      await Future.microtask(() {});
      final captured = verify(() => mockSendPort.send(captureAny())).captured;
      final request = captured.last as PrintRequest;
      printingFfi.handleIsolateMessageForTest(PrintResponse(request.id, true));
      final result = await future;

      // Assert
      expect(result, isTrue);
      expect(request.printerName, 'Test Raw Printer');
      expect(request.data, testData);
      expect(request.docName, 'My Raw Doc');
      expect(request.options, containsPair('raw', 'true'));
    });

    test('rawDataToPrinter throws an exception on error response', () async {
      // Arrange
      when(() => mockSendPort.send(any())).thenAnswer((_) {});
      final testData = Uint8List.fromList([1, 2, 3]);
      final exception = PrintingFfiException('Raw print failed');

      // Act
      final future = printingFfi.rawDataToPrinter('Test Raw Printer', testData);

      // Simulate isolate response
      await Future.microtask(() {});
      final captured = verify(() => mockSendPort.send(captureAny())).captured;
      final request = captured.last as PrintRequest;
      printingFfi.handleIsolateMessageForTest(ErrorResponse(request.id, exception, StackTrace.current));
      // Assert
      expect(future, throwsA(isA<PrintingFfiException>()));
    });

    for (final action in ['cancel', 'pause', 'resume']) {
      test('$action PrintJob sends correct request and completes on success', () async {
        // Arrange
        when(() => mockSendPort.send(any())).thenAnswer((_) {});
        const printerName = 'Test Printer';
        const jobId = 456;

        // Act
        Future<bool> future;
        switch (action) {
          case 'cancel':
            future = printingFfi.cancelPrintJob(printerName, jobId);
            break;
          case 'pause':
            future = printingFfi.pausePrintJob(printerName, jobId);
            break;
          case 'resume':
            future = printingFfi.resumePrintJob(printerName, jobId);
            break;
          default:
            throw 'unreachable';
        }

        // Simulate isolate response
        await Future.microtask(() {});
        final captured = verify(() => mockSendPort.send(captureAny())).captured;
        final request = captured.last as PrintJobActionRequest;
        printingFfi.handleIsolateMessageForTest(PrintJobActionResponse(request.id, true));
        final result = await future;

        // Assert
        expect(result, isTrue);
        expect(request.action, action);
        expect(request.jobId, jobId);
      });
    }

    group('Streaming Job Status', () {
      test('rawDataToPrinterAndStreamStatus submits job and streams status', () async {
        // Arrange
        final testData = Uint8List.fromList([1, 2, 3]);
        const jobId = 999;
        final processingJob = PrintJob(jobId, 'My Tracked ZPL Label', 5); // CUPS: IPP_JOB_PROCESSING
        final completedJob = PrintJob(jobId, 'My Tracked ZPL Label', 9); // CUPS: IPP_JOB_COMPLETED
        bool firstPollDone = false;

        // Use thenAnswer to simulate the isolate's response based on the request type.
        // This allows us to drive the stream's logic dynamically.
        when(() => mockSendPort.send(any())).thenAnswer((invocation) {
          final request = invocation.positionalArguments.first;
          if (request is SubmitRawDataJobRequest) {
            printingFfi.handleIsolateMessageForTest(SubmitJobResponse(request.id, jobId));
          } else if (request is PrintJobsRequest) {
            // First poll gets processing, second gets completed.
            if (!firstPollDone) {
              printingFfi.handleIsolateMessageForTest(PrintJobsResponse(request.id, [processingJob]));
              firstPollDone = true;
            } else {
              printingFfi.handleIsolateMessageForTest(PrintJobsResponse(request.id, [completedJob]));
            }
          }
        });

        // Act
        final stream = printingFfi.rawDataToPrinterAndStreamStatus(
          'Test Printer',
          testData,
          docName: 'My Tracked ZPL Label',
          pollInterval: const Duration(milliseconds: 1), // Use short interval for test
        );

        // Assert
        // Awaiting the stream will now work because the `thenAnswer` setup above
        // will provide the necessary data to unblock the futures inside the stream logic.
        await expectLater(
          stream,
          emitsInOrder([
            isA<PrintJob>().having((j) => j.status, 'status', PrintJobStatus.processing),
            isA<PrintJob>().having((j) => j.status, 'status', PrintJobStatus.completed),
            emitsDone,
          ]),
        );
      });

      test('rawDataToPrinterAndStreamStatus emits error if submission fails', () async {
        // Arrange
        final testData = Uint8List.fromList([1, 2, 3]);
        final exception = PrintingFfiException('Submission failed');

        // Simulate a failure during job submission.
        when(() => mockSendPort.send(any())).thenAnswer((invocation) {
          final request = invocation.positionalArguments.first;
          if (request is SubmitRawDataJobRequest) {
            printingFfi.handleIsolateMessageForTest(ErrorResponse(request.id, exception, StackTrace.current));
          }
        });

        // Act
        final stream = printingFfi.rawDataToPrinterAndStreamStatus(
          'Test Printer',
          testData,
        );

        // Assert
        // The stream should emit the error and then be done.
        await expectLater(stream, emitsError(isA<PrintingFfiException>()));
      });

      test('printPdfAndStreamStatus submits job and streams status', () async {
        // Arrange
        const pdfPath = '/path/to/test.pdf';
        const jobId = 1000;
        final processingJob = PrintJob(jobId, 'My Tracked PDF', 5); // CUPS: IPP_JOB_PROCESSING
        final completedJob = PrintJob(jobId, 'My Tracked PDF', 9); // CUPS: IPP_JOB_COMPLETED
        bool firstPollDone = false;

        // Use thenAnswer to simulate the isolate's response based on the request type.
        when(() => mockSendPort.send(any())).thenAnswer((invocation) {
          final request = invocation.positionalArguments.first;
          if (request is SubmitPdfJobRequest) {
            printingFfi.handleIsolateMessageForTest(SubmitJobResponse(request.id, jobId));
          } else if (request is PrintJobsRequest) {
            // First poll gets processing, second gets completed.
            if (!firstPollDone) {
              printingFfi.handleIsolateMessageForTest(PrintJobsResponse(request.id, [processingJob]));
              firstPollDone = true;
            } else {
              printingFfi.handleIsolateMessageForTest(PrintJobsResponse(request.id, [completedJob]));
            }
          }
        });

        // Act
        final stream = printingFfi.printPdfAndStreamStatus(
          'Test Printer',
          pdfPath,
          docName: 'My Tracked PDF',
          pollInterval: const Duration(milliseconds: 1), // Use short interval for test
        );

        // Assert
        await expectLater(
          stream,
          emitsInOrder([
            isA<PrintJob>().having((j) => j.status, 'status', PrintJobStatus.processing),
            isA<PrintJob>().having((j) => j.status, 'status', PrintJobStatus.completed),
            emitsDone,
          ]),
        );
      });

      test('listPrintJobsStream polls for and streams job lists', () async {
        // Arrange
        final job1 = PrintJob(1, 'Job 1', 5); // Processing
        final job2 = PrintJob(2, 'Job 2', 3); // Pending
        final job3 = PrintJob(3, 'Job 3', 9); // Completed

        final firstResponse = [job1, job2];
        final secondResponse = [job2, job3]; // job1 finished, job3 appeared
        final thirdResponse = [job3]; // job2 finished

        int pollCount = 0;
        when(() => mockSendPort.send(any(that: isA<PrintJobsRequest>()))).thenAnswer((invocation) {
          final request = invocation.positionalArguments.first as PrintJobsRequest;
          pollCount++;
          if (pollCount == 1) {
            printingFfi.handleIsolateMessageForTest(PrintJobsResponse(request.id, firstResponse));
          } else if (pollCount == 2) {
            printingFfi.handleIsolateMessageForTest(PrintJobsResponse(request.id, secondResponse));
          } else {
            printingFfi.handleIsolateMessageForTest(PrintJobsResponse(request.id, thirdResponse));
          }
        });

        // Act
        final stream = printingFfi.listPrintJobsStream(
          'Test Printer',
          pollInterval: const Duration(milliseconds: 1),
        );

        // Assert
        // We take 3 events to see the queue change over time.
        await expectLater(
          stream.take(3),
          emitsInOrder([
            firstResponse,
            secondResponse,
            thirdResponse,
          ]),
        );
      });
    });

    test('dispose fails pending requests and cleans up resources', () async {
      // Arrange
      // No need to mock send because we won't let it complete.
      when(() => mockSendPort.send(any())).thenAnswer((_) async {});

      // Act
      // Start a request but don't await it or provide a response.
      // Ensure the synchronous part of listPrintJobs completes and adds the completer.
      final future = printingFfi.listPrintJobs('Test Printer');
      await Future.microtask(() {});

      // Dispose the instance while the request is in flight.
      printingFfi.dispose();

      // Assert
      // The future should fail, and the dispose request should be sent.
      await expectLater(future, throwsA(isA<IsolateError>()));
      verify(() => mockSendPort.send(any(that: isA<DisposeRequest>()))).called(1); // Verify the DisposeRequest was sent
    });
  });
}
