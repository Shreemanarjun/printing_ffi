import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:printing_ffi/printing_ffi_bindings_generated.dart';
import 'models/models.dart';

export 'models/models.dart';

void _remapCupsOptions(Map<String, String> options) {
  if (Platform.isMacOS || Platform.isLinux) {
    if (options.containsKey('orientation')) {
      final orientationValue = options.remove('orientation');
      options['orientation-requested'] = orientationValue == 'landscape' ? '4' : '3';
    }
    if (options.containsKey('color-mode')) {
      final colorValue = options.remove('color-mode');
      options['print-color-mode'] = colorValue!;
    }
    if (options.containsKey('print-quality')) {
      final qualityValue = options.remove('print-quality');
      switch (qualityValue) {
        case 'draft':
        case 'low':
          options['print-quality'] = '3';
          break;
        case 'normal':
          options['print-quality'] = '4';
          break;
        case 'high':
          options['print-quality'] = '5';
          break;
      }
    }

    if (options.containsKey('duplex')) {
      final duplexValue = options.remove('duplex');
      switch (duplexValue) {
        case 'singleSided':
          options['sides'] = 'one-sided';
          break;
        case 'duplexLongEdge':
          options['sides'] = 'two-sided-long-edge';
          break;
        case 'duplexShortEdge':
          options['sides'] = 'two-sided-short-edge';
          break;
      }
    }
  }
}

class PrintingFfi {
  PrintingFfi._(); // Private constructor
  static final PrintingFfi instance = PrintingFfi._();

  static const String _libName = 'printing_ffi';

  final DynamicLibrary _dylib = () {
    if (Platform.isMacOS) {
      return DynamicLibrary.open('$_libName.framework/$_libName');
    }
    if (Platform.isLinux) return DynamicLibrary.open('lib$_libName.so');
    if (Platform.isWindows) return DynamicLibrary.open('$_libName.dll');
    throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
  }();

  late final PrintingFfiBindings _bindings = PrintingFfiBindings(_dylib);

  ReceivePort? _mainReceivePort;
  StreamSubscription? _mainPortSubscription;

  void dispose() {
    if (_helperIsolateSendPortFuture != null) {
      _helperIsolateSendPortFuture!
          .then((sendPort) {
            sendPort.send(const _DisposeRequest());
          })
          .catchError((_) {
            // Isolate might already be gone, which is fine.
          });
    }
    _mainPortSubscription?.cancel();
    _mainReceivePort?.close();
    _helperIsolateSendPortFuture = null;
    _mainPortSubscription = null;
    _mainReceivePort = null;
    _failAllPendingRequests(IsolateError('PrintingFfi instance disposed.'));
  }

  /// Initializes the bundled PDFium library for Windows.
  ///
  /// This method should be called from the main isolate, preferably in your `main()`
  /// function, before any other PDF-related operations if you are using this
  /// plugin for PDF printing on Windows **and are not using another plugin
  /// that already initializes PDFium (like `pdfrx`)**.
  ///
  /// ```dart
  /// void main() {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   if (Platform.isWindows) {
  ///     // Call this if printing_ffi is your only PDFium-based plugin.
  ///     PrintingFfi.instance.initPdfium();
  ///   }
  ///   runApp(const MyApp());
  /// }
  /// ```
  ///
  /// If you are using `pdfrx` or a similar plugin, you do not need to call this
  /// method, as that plugin will handle the initialization. This optional,
  /// explicit initialization prevents conflicts in apps with multiple PDFium-based plugins.
  void initPdfium() {
    if (!Platform.isWindows) return;
    _bindings.init_pdfium_library();
  }

  List<Printer> listPrinters() {
    final printerListPtr = _bindings.get_printers();

    if (printerListPtr == nullptr) {
      return [];
    }

    try {
      final printerList = printerListPtr.ref;
      final printers = <Printer>[];
      for (var i = 0; i < printerList.count; i++) {
        printers.add(_printerFromInfo(printerList.printers[i]));
      }
      return printers;
    } finally {
      _bindings.free_printer_list(printerListPtr);
    }
  }

  Printer? getDefaultPrinter() {
    final printerInfoPtr = _bindings.get_default_printer();

    if (printerInfoPtr == nullptr) {
      return null;
    }

    try {
      return _printerFromInfo(printerInfoPtr.ref);
    } finally {
      _bindings.free_printer_info(printerInfoPtr);
    }
  }

  Printer _printerFromInfo(PrinterInfo info) {
    final model = info.model.cast<Utf8>().toDartString();
    final location = info.location.cast<Utf8>().toDartString();
    final comment = info.comment.cast<Utf8>().toDartString();

    return Printer(
      name: info.name.cast<Utf8>().toDartString(),
      state: info.state,
      url: info.url.cast<Utf8>().toDartString(),
      model: model.isEmpty ? null : model,
      location: location.isEmpty ? null : location,
      comment: comment.isEmpty ? null : comment,
      isDefault: info.is_default,
      isAvailable: info.is_available,
    );
  }

  Future<PrinterPropertiesResult> openPrinterProperties(String printerName, {int hwnd = 0}) async {
    if (!Platform.isWindows) {
      // This function is Windows-specific.
      return PrinterPropertiesResult.error;
    }
    final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
    final int requestId = _nextOpenPrinterPropertiesRequestId++;
    final request = _OpenPrinterPropertiesRequest(requestId, printerName, hwnd);
    final completer = Completer<PrinterPropertiesResult>();
    _openPrinterPropertiesRequests[requestId] = completer;
    helperIsolateSendPort.send(request);
    return completer.future;
  }

  Future<bool> rawDataToPrinter(
    String printerName,
    Uint8List data, {
    String docName = 'Flutter Document',
    List<PrintOption> options = const [],
  }) async {
    final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
    final int requestId = _nextPrintRequestId++;
    final optionsMap = _buildOptions(options);

    final _PrintRequest request = _PrintRequest(
      requestId,
      printerName,
      data,
      docName,
      optionsMap,
    );
    final Completer<bool> completer = Completer<bool>();
    _printRequests[requestId] = completer;
    helperIsolateSendPort.send(request);
    return completer.future;
  }

  Future<bool> printPdf(
    String printerName,
    String pdfFilePath, {
    String docName = 'Flutter PDF Document',
    PdfPrintScaling scaling = PdfPrintScaling.fitToPrintableArea,
    int? copies,
    PageRange? pageRange,
    List<PrintOption> options = const [],
  }) async {
    final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
    final int requestId = _nextPrintPdfRequestId++;
    final optionsMap = _buildOptions(options);
    final pageRangeValue = pageRange?.toValue();
    final alignment = optionsMap.remove('alignment') ?? 'center';
    final finalOptions = {...optionsMap};
    if (scaling is PdfPrintScalingCustom) {
      finalOptions['custom-scale-factor'] = scaling.scale.toString();
    }

    final _PrintPdfRequest request = _PrintPdfRequest(
      requestId,
      printerName,
      pdfFilePath,
      docName,
      finalOptions,
      scaling.nativeValue,
      copies ?? 1,
      pageRangeValue,
      alignment,
    );
    final Completer<bool> completer = Completer<bool>();
    _printPdfRequests[requestId] = completer;
    helperIsolateSendPort.send(request);
    return completer.future;
  }

  Stream<PrintJob> rawDataToPrinterAndStreamStatus(
    String printerName,
    Uint8List data, {
    String docName = 'Flutter Raw Data',
    Duration pollInterval = const Duration(seconds: 2),
    List<PrintOption> options = const [],
  }) {
    return _streamJobStatus(
      printerName: printerName,
      pollInterval: pollInterval,
      submitJob: () => _sendRawDataJobRequest(
        printerName,
        data,
        docName: docName,
        options: _buildOptions(options),
      ),
    );
  }

  Stream<PrintJob> printPdfAndStreamStatus(
    String printerName,
    String pdfFilePath, {
    String docName = 'Flutter PDF Document',
    PdfPrintScaling scaling = PdfPrintScaling.fitToPrintableArea,
    int? copies,
    PageRange? pageRange,
    List<PrintOption> options = const [],
    Duration pollInterval = const Duration(seconds: 2),
  }) {
    return _streamJobStatus(
      printerName: printerName,
      pollInterval: pollInterval,
      submitJob: () {
        final optionsMap = _buildOptions(options);
        final alignment = optionsMap.remove('alignment') ?? 'center';
        final finalOptions = {...optionsMap};
        if (scaling is PdfPrintScalingCustom) {
          finalOptions['custom-scale-factor'] = scaling.scale.toString();
        }
        return _sendPdfJobRequest(
          printerName,
          pdfFilePath,
          docName: docName,
          scalingMode: scaling.nativeValue,
          copies: copies,
          pageRange: pageRange,
          options: finalOptions,
          alignment: alignment,
        );
      },
    );
  }

  Map<String, String> _buildOptions(List<PrintOption> options) {
    final Map<String, String> optionsMap = {};
    for (final option in options) {
      switch (option) {
        case WindowsPaperSizeOption(id: final id):
          optionsMap['paper-size-id'] = id.toString();
        case WindowsPaperSourceOption(id: final id):
          optionsMap['paper-source-id'] = id.toString();
        case OrientationOption(orientation: final orientation):
          optionsMap['orientation'] = orientation.name;
        case GenericCupsOption(name: final name, value: final value):
          optionsMap[name] = value;
        case ColorModeOption(mode: final mode):
          optionsMap['color-mode'] = mode.name;
        case PrintQualityOption(quality: final quality):
          optionsMap['print-quality'] = quality.name;
        case WindowsMediaTypeOption(id: final id):
          optionsMap['media-type-id'] = id.toString();
        case AlignmentOption(alignment: final alignment):
          optionsMap['alignment'] = alignment.name;
        case CollateOption(collate: final collate):
          optionsMap['collate'] = collate.toString();
        case DuplexOption(mode: final mode):
          optionsMap['duplex'] = mode.name;
      }
    }
    return optionsMap;
  }

  Stream<PrintJob> _streamJobStatus({
    required String printerName,
    required Duration pollInterval,
    required Future<int> Function() submitJob,
  }) {
    late StreamController<PrintJob> controller;
    Timer? poller;
    PrintJob? lastJobState;

    PrintJob? findJobById(List<PrintJob> jobs, int jobId) {
      for (final job in jobs) {
        if (job.id == jobId) return job;
      }
      return null;
    }

    Future<void> poll(int jobId) async {
      if (controller.isClosed) {
        poller?.cancel();
        return;
      }

      try {
        final jobs = await listPrintJobs(printerName);
        final currentJob = findJobById(jobs, jobId);

        if (currentJob != null) {
          // Job is still in the queue.
          // Only emit an update if the status has changed.
          if (currentJob.rawStatus != lastJobState?.rawStatus) {
            controller.add(currentJob);
          }
          lastJobState = currentJob;

          // If the job has reached a terminal state, stop polling.
          final status = currentJob.status;
          if (status == PrintJobStatus.completed || status == PrintJobStatus.canceled || status == PrintJobStatus.aborted || status == PrintJobStatus.error) {
            poller?.cancel();
            await controller.close();
          }
        } else {
          // Job is no longer in the queue. This usually means it has completed.
          // If we have a last known state and it wasn't already 'completed',
          // we can emit a final 'completed' status before closing the stream.
          if (lastJobState != null && lastJobState!.status != PrintJobStatus.completed) {
            // Create a synthetic 'completed' job status.
            final completedRawStatus = Platform.isWindows
                ? 0x00000080 // JOB_STATUS_PRINTED
                : 9; // IPP_JOB_COMPLETED
            final finalJob = PrintJob(lastJobState!.id, lastJobState!.title, completedRawStatus);

            // Only add if the status is actually different.
            if (finalJob.rawStatus != lastJobState!.rawStatus) {
              controller.add(finalJob);
            }
          }
          // The job is gone, so we stop polling and close the stream.
          poller?.cancel();
          await controller.close();
        }
      } catch (e, s) {
        if (!controller.isClosed) {
          controller.addError(e, s);
          poller?.cancel();
          await controller.close();
        }
      }
    }

    controller = StreamController<PrintJob>(
      onListen: () async {
        submitJob()
            .then((jobId) {
              // Got a job ID, start polling.
              // An initial poll is done right away to get the first status.
              poll(jobId);
              poller = Timer.periodic(pollInterval, (_) => poll(jobId));
            })
            .catchError((Object e, StackTrace s) {
              // The job submission failed.
              if (!controller.isClosed) {
                controller.addError(e, s);
                controller.close();
              }
            });
      },
      onCancel: () {
        poller?.cancel();
      },
    );

    return controller.stream;
  }

  Future<List<CupsOptionModel>> getSupportedCupsOptions(String printerName) async {
    if (!Platform.isMacOS && !Platform.isLinux) {
      return [];
    }

    final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
    final int requestId = _nextGetCupsOptionsRequestId++;
    final _GetCupsOptionsRequest request = _GetCupsOptionsRequest(requestId, printerName);
    final Completer<List<CupsOptionModel>> completer = Completer<List<CupsOptionModel>>();
    _getCupsOptionsRequests[requestId] = completer;
    helperIsolateSendPort.send(request);
    return completer.future;
  }

  Future<WindowsPrinterCapabilitiesModel?> getWindowsPrinterCapabilities(String printerName) async {
    if (!Platform.isWindows) {
      return null;
    }
    final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
    final int requestId = _nextGetWindowsCapsRequestId++;
    final request = _GetWindowsCapsRequest(requestId, printerName);
    final completer = Completer<WindowsPrinterCapabilitiesModel?>();
    _getWindowsCapsRequests[requestId] = completer;
    helperIsolateSendPort.send(request);
    return completer.future;
  }

  Future<List<PrintJob>> listPrintJobs(String printerName) async {
    final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
    final int requestId = _nextPrintJobsRequestId++;
    final _PrintJobsRequest request = _PrintJobsRequest(requestId, printerName);
    final Completer<List<PrintJob>> completer = Completer<List<PrintJob>>();
    _printJobsRequests[requestId] = completer;
    helperIsolateSendPort.send(request);
    return completer.future;
  }

  Stream<List<PrintJob>> listPrintJobsStream(
    String printerName, {
    Duration pollInterval = const Duration(seconds: 2),
  }) {
    late StreamController<List<PrintJob>> controller;
    Timer? timer;

    void startPolling() {
      if (timer?.isActive ?? false) return;
      timer = Timer.periodic(pollInterval, (_) async {
        if (controller.isClosed) {
          timer?.cancel();
          return;
        }
        try {
          final jobs = await listPrintJobs(printerName);
          if (!controller.isClosed) {
            controller.add(jobs);
          }
        } catch (e, s) {
          if (!controller.isClosed) {
            controller.addError(e, s);
          }
        }
      });
    }

    void stopPolling() {
      timer?.cancel();
      timer = null;
    }

    controller = StreamController<List<PrintJob>>(
      onListen: () {
        listPrintJobs(printerName)
            .then((jobs) {
              if (!controller.isClosed) {
                controller.add(jobs);
              }
              startPolling();
            })
            .catchError((e, s) {
              if (!controller.isClosed) {
                controller.addError(e, s);
              }
            });
      },
      onPause: stopPolling,
      onResume: startPolling,
      onCancel: stopPolling,
    );

    return controller.stream;
  }

  Future<bool> pausePrintJob(String printerName, int jobId) async {
    final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
    final int requestId = _nextPrintJobActionRequestId++;
    final _PrintJobActionRequest request = _PrintJobActionRequest(
      requestId,
      printerName,
      jobId,
      'pause',
    );
    final Completer<bool> completer = Completer<bool>();
    _printJobActionRequests[requestId] = completer;
    helperIsolateSendPort.send(request);
    return completer.future;
  }

  Future<bool> resumePrintJob(String printerName, int jobId) async {
    final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
    final int requestId = _nextPrintJobActionRequestId++;
    final _PrintJobActionRequest request = _PrintJobActionRequest(
      requestId,
      printerName,
      jobId,
      'resume',
    );
    final Completer<bool> completer = Completer<bool>();
    _printJobActionRequests[requestId] = completer;
    helperIsolateSendPort.send(request);
    return completer.future;
  }

  Future<bool> cancelPrintJob(String printerName, int jobId) async {
    final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
    final int requestId = _nextPrintJobActionRequestId++;
    final _PrintJobActionRequest request = _PrintJobActionRequest(
      requestId,
      printerName,
      jobId,
      'cancel',
    );
    final Completer<bool> completer = Completer<bool>();
    _printJobActionRequests[requestId] = completer;
    helperIsolateSendPort.send(request);
    return completer.future;
  }

  Future<int> _sendRawDataJobRequest(
    String printerName,
    Uint8List data, {
    String docName = 'Flutter Document',
    Map<String, String> options = const {},
  }) async {
    final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
    final int requestId = _nextSubmitRawDataJobRequestId++;
    final request = _SubmitRawDataJobRequest(
      requestId,
      printerName,
      data,
      docName,
      options,
    );
    final completer = Completer<int>();
    _submitRawDataJobRequests[requestId] = completer;
    helperIsolateSendPort.send(request);
    return completer.future;
  }

  Future<int> _sendPdfJobRequest(
    String printerName,
    String pdfFilePath, {
    String docName = 'Flutter PDF Document',
    required int scalingMode,
    int? copies,
    PageRange? pageRange,
    Map<String, String> options = const {},
    String alignment = 'center',
  }) async {
    final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
    final int requestId = _nextSubmitPdfJobRequestId++;
    final pageRangeValue = pageRange?.toValue();
    final request = _SubmitPdfJobRequest(
      requestId,
      printerName,
      pdfFilePath,
      docName,
      options,
      scalingMode,
      copies ?? 1,
      pageRangeValue,
      alignment,
    );
    final completer = Completer<int>();
    _submitPdfJobRequests[requestId] = completer;
    helperIsolateSendPort.send(request);
    return completer.future;
  }

  int _nextPrintRequestId = 0;
  int _nextPrintJobsRequestId = 0;
  int _nextPrintJobActionRequestId = 0;
  int _nextPrintPdfRequestId = 0;
  int _nextGetCupsOptionsRequestId = 0;
  int _nextGetWindowsCapsRequestId = 0;
  int _nextOpenPrinterPropertiesRequestId = 0;
  int _nextSubmitRawDataJobRequestId = 0;
  int _nextSubmitPdfJobRequestId = 0;

  final Map<int, Completer<bool>> _printRequests = <int, Completer<bool>>{};
  final Map<int, Completer<List<PrintJob>>> _printJobsRequests = <int, Completer<List<PrintJob>>>{};
  final Map<int, Completer<bool>> _printJobActionRequests = <int, Completer<bool>>{};
  final Map<int, Completer<bool>> _printPdfRequests = <int, Completer<bool>>{};
  final Map<int, Completer<List<CupsOptionModel>>> _getCupsOptionsRequests = <int, Completer<List<CupsOptionModel>>>{};
  final Map<int, Completer<WindowsPrinterCapabilitiesModel?>> _getWindowsCapsRequests = <int, Completer<WindowsPrinterCapabilitiesModel?>>{};
  final Map<int, Completer<PrinterPropertiesResult>> _openPrinterPropertiesRequests = <int, Completer<PrinterPropertiesResult>>{};
  final Map<int, Completer<int>> _submitRawDataJobRequests = <int, Completer<int>>{};
  final Map<int, Completer<int>> _submitPdfJobRequests = <int, Completer<int>>{};

  Future<SendPort>? _helperIsolateSendPortFuture;

  void _failAllPendingRequests(Object error, [StackTrace? stackTrace]) {
    final allCompleters = [
      ..._printRequests.values,
      ..._printJobsRequests.values,
      ..._printJobActionRequests.values,
      ..._printPdfRequests.values,
      ..._getCupsOptionsRequests.values,
      ..._getWindowsCapsRequests.values,
      ..._openPrinterPropertiesRequests.values,
      ..._submitRawDataJobRequests.values,
      ..._submitPdfJobRequests.values,
    ];

    for (final completer in allCompleters) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }

    _printRequests.clear();
    _printJobsRequests.clear();
    _printJobActionRequests.clear();
    _printPdfRequests.clear();
    _getCupsOptionsRequests.clear();
    _getWindowsCapsRequests.clear();
    _openPrinterPropertiesRequests.clear();
    _submitRawDataJobRequests.clear();
    _submitPdfJobRequests.clear();
  }

  Future<SendPort> get _helperIsolateSendPort async {
    if (_helperIsolateSendPortFuture != null) {
      return _helperIsolateSendPortFuture!;
    }

    final Completer<SendPort> completer = Completer<SendPort>();
    _mainReceivePort = ReceivePort();

    _mainPortSubscription = _mainReceivePort!.listen((dynamic data) {
      if (data is SendPort) {
        if (!completer.isCompleted) {
          completer.complete(data);
        }
        return;
      }

      if (data is List && data.length == 2 && data[0] is String) {
        final error = IsolateError('Uncaught exception in helper isolate: ${data[0]}');
        final stack = StackTrace.fromString(data[1].toString());
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
        _failAllPendingRequests(error, stack);
        _mainPortSubscription?.cancel();
        _mainReceivePort?.close();
        _mainPortSubscription = null;
        _mainReceivePort = null;
        return;
      }

      if (data == null) {
        final error = IsolateError('Helper isolate exited unexpectedly.');
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
        _failAllPendingRequests(error);
        _mainPortSubscription?.cancel();
        _mainReceivePort?.close();
        _mainPortSubscription = null;
        _mainReceivePort = null;
        return;
      }

      if (data is _PrintResponse) {
        final Completer<bool> completer = _printRequests[data.id]!;
        _printRequests.remove(data.id);
        completer.complete(data.result);
        return;
      }
      if (data is _PrintJobsResponse) {
        final Completer<List<PrintJob>> completer = _printJobsRequests[data.id]!;
        _printJobsRequests.remove(data.id);
        completer.complete(data.jobs);
        return;
      }
      if (data is _PrintJobActionResponse) {
        final Completer<bool> completer = _printJobActionRequests[data.id]!;
        _printJobActionRequests.remove(data.id);
        completer.complete(data.result);
        return;
      }
      if (data is _PrintPdfResponse) {
        final Completer<bool> completer = _printPdfRequests[data.id]!;
        _printPdfRequests.remove(data.id);
        completer.complete(data.result);
        return;
      }
      if (data is _GetCupsOptionsResponse) {
        final Completer<List<CupsOptionModel>> completer = _getCupsOptionsRequests[data.id]!;
        _getCupsOptionsRequests.remove(data.id);
        completer.complete(data.options);
        return;
      }
      if (data is _GetWindowsCapsResponse) {
        final Completer<WindowsPrinterCapabilitiesModel?> completer = _getWindowsCapsRequests[data.id]!;
        _getWindowsCapsRequests.remove(data.id);
        completer.complete(data.capabilities);
        return;
      }
      if (data is _OpenPrinterPropertiesResponse) {
        final Completer<PrinterPropertiesResult> completer = _openPrinterPropertiesRequests[data.id]!;
        _openPrinterPropertiesRequests.remove(data.id);
        completer.complete(data.result);
        return;
      }
      if (data is _SubmitJobResponse) {
        if (_submitRawDataJobRequests.containsKey(data.id)) {
          _submitRawDataJobRequests.remove(data.id)!.complete(data.jobId);
        } else if (_submitPdfJobRequests.containsKey(data.id)) {
          _submitPdfJobRequests.remove(data.id)!.complete(data.jobId);
        }
        return;
      }
      if (data is _ErrorResponse) {
        Completer? requestCompleter;
        final allRequestMaps = [
          _printRequests,
          _printJobsRequests,
          _printJobActionRequests,
          _printPdfRequests,
          _getCupsOptionsRequests,
          _getWindowsCapsRequests,
          _openPrinterPropertiesRequests,
          _submitRawDataJobRequests,
          _submitPdfJobRequests,
        ];
        for (final map in allRequestMaps) {
          if (map.containsKey(data.id)) {
            requestCompleter = map.remove(data.id);
            break;
          }
        }
        requestCompleter?.completeError(data.error, data.stackTrace);
        return;
      }
      throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
    });

    try {
      await Isolate.spawn(
        _helperIsolateEntryPoint,
        _mainReceivePort!.sendPort,
      );
    } catch (error, stack) {
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
    }

    _helperIsolateSendPortFuture = completer.future;
    return _helperIsolateSendPortFuture!;
  }
}

// Helper classes for isolate communication

class _PrintRequest {
  final int id;
  final String printerName;
  final Uint8List data;
  final String docName;
  final Map<String, String>? options;

  const _PrintRequest(this.id, this.printerName, this.data, this.docName, this.options);
}

class _PrintJobsRequest {
  final int id;
  final String printerName;

  const _PrintJobsRequest(this.id, this.printerName);
}

class _PrintJobActionRequest {
  final int id;
  final String printerName;
  final int jobId;
  final String action;

  const _PrintJobActionRequest(this.id, this.printerName, this.jobId, this.action);
}

class _PrintPdfRequest {
  final int id;
  final String printerName;
  final String pdfFilePath;
  final String docName;
  final Map<String, String>? options;
  final int scalingMode;
  final int copies;
  final String? pageRange;
  final String alignment;

  const _PrintPdfRequest(this.id, this.printerName, this.pdfFilePath, this.docName, this.options, this.scalingMode, this.copies, this.pageRange, this.alignment);
}

class _GetCupsOptionsRequest {
  final int id;
  final String printerName;

  const _GetCupsOptionsRequest(this.id, this.printerName);
}

class _GetWindowsCapsRequest {
  final int id;
  final String printerName;

  const _GetWindowsCapsRequest(this.id, this.printerName);
}

class _OpenPrinterPropertiesRequest {
  final int id;
  final String printerName;
  final int hwnd;

  const _OpenPrinterPropertiesRequest(this.id, this.printerName, this.hwnd);
}

class _SubmitRawDataJobRequest {
  final int id;
  final String printerName;
  final Uint8List data;
  final String docName;
  final Map<String, String>? options;

  const _SubmitRawDataJobRequest(this.id, this.printerName, this.data, this.docName, this.options);
}

class _SubmitPdfJobRequest {
  final int id;
  final String printerName;
  final String pdfFilePath;
  final String docName;
  final Map<String, String>? options;
  final int scalingMode;
  final int copies;
  final String? pageRange;
  final String alignment;

  const _SubmitPdfJobRequest(this.id, this.printerName, this.pdfFilePath, this.docName, this.options, this.scalingMode, this.copies, this.pageRange, this.alignment);
}

class _PrintResponse {
  final int id;
  final bool result;

  const _PrintResponse(this.id, this.result);
}

class _PrintJobsResponse {
  final int id;
  final List<PrintJob> jobs;

  const _PrintJobsResponse(this.id, this.jobs);
}

class _PrintJobActionResponse {
  final int id;
  final bool result;

  const _PrintJobActionResponse(this.id, this.result);
}

class _PrintPdfResponse {
  final int id;
  final bool result;

  const _PrintPdfResponse(this.id, this.result);
}

class _GetCupsOptionsResponse {
  final int id;
  final List<CupsOptionModel> options;

  const _GetCupsOptionsResponse(this.id, this.options);
}

class _GetWindowsCapsResponse {
  final int id;
  final WindowsPrinterCapabilitiesModel? capabilities;

  const _GetWindowsCapsResponse(this.id, this.capabilities);
}

class _OpenPrinterPropertiesResponse {
  final int id;
  final PrinterPropertiesResult result;

  const _OpenPrinterPropertiesResponse(this.id, this.result);
}

class _SubmitJobResponse {
  final int id;
  final int jobId;

  const _SubmitJobResponse(this.id, this.jobId);
}

class _ErrorResponse {
  final int id;
  final Object error;
  final StackTrace? stackTrace;

  const _ErrorResponse(this.id, this.error, this.stackTrace);
}

class _DisposeRequest {
  const _DisposeRequest();
}

/// The entry point for the helper isolate.
void _helperIsolateEntryPoint(SendPort sendPort) {
  runZonedGuarded(
    () {
      if (Platform.isWindows) {
        // Initialize COM for the current thread. This is crucial for some Windows APIs,
        // especially those related to printing and shell services, which may be
        // used by printer drivers. Without this, calls can hang, fail, or perform
        // very slowly when run from a background isolate.
        // COINIT_APARTMENTTHREADED is a common requirement for UI-related components
        // that printer drivers might interact with.
        try {
          final ole32 = DynamicLibrary.open('ole32.dll');
          final coInitializeEx = ole32.lookup<NativeFunction<Int32 Function(Pointer, Uint32)>>('CoInitializeEx');
          final coInitializeExFunc = coInitializeEx.asFunction<int Function(Pointer, int)>();
          // Revert to STA (Single-Threaded Apartment) as some printer drivers
          // have strict requirements for it. To prevent the thread from hanging,
          // we will manually pump the Windows message queue from the native C code
          // during long-running operations.
          const coinitApartmentthreaded = 0x2;
          coInitializeExFunc(nullptr, coinitApartmentthreaded);
          // We don't check the HRESULT. It's okay if it's already initialized (S_FALSE).
          // We just need to ensure it's been called once for this thread.
        } catch (e) {
          // If CoInitializeEx is not available or fails, we'll proceed without it,
          // but this might be the cause of the reported performance issues.
        }
      }
      final dylib = () {
        if (Platform.isMacOS) {
          return DynamicLibrary.open('${PrintingFfi._libName}.framework/${PrintingFfi._libName}');
        }
        if (Platform.isLinux) return DynamicLibrary.open('lib${PrintingFfi._libName}.so');
        if (Platform.isWindows) return DynamicLibrary.open('${PrintingFfi._libName}.dll');
        throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
      }();

      final bindings = PrintingFfiBindings(dylib);
      final getLastError = dylib.lookup<NativeFunction<Pointer<Utf8> Function()>>('get_last_error').asFunction<Pointer<Utf8> Function()>();

      final helperReceivePort = ReceivePort();
      helperReceivePort.listen((dynamic data) {
        if (data is _DisposeRequest) {
          if (Platform.isWindows) {
            // Clean up the PDFium library before the isolate exits.
            bindings.shutdown_pdfium_library();
          }
          helperReceivePort.close();
          return;
        }
        if (data is _PrintRequest) {
          try {
            final namePtr = data.printerName.toNativeUtf8();
            final docNamePtr = data.docName.toNativeUtf8();
            final dataPtr = malloc<Uint8>(data.data.length);
            dataPtr.asTypedList(data.data.length).setAll(0, data.data);
            try {
              final options = {...?data.options};
              _remapCupsOptions(options);
              final int numOptions = options.length;
              Pointer<Pointer<Utf8>> keysPtr = nullptr;
              Pointer<Pointer<Utf8>> valuesPtr = nullptr;

              try {
                if (numOptions > 0) {
                  keysPtr = malloc<Pointer<Utf8>>(numOptions);
                  valuesPtr = malloc<Pointer<Utf8>>(numOptions);
                  int i = 0;
                  for (var entry in options.entries) {
                    keysPtr[i] = entry.key.toNativeUtf8();
                    valuesPtr[i] = entry.value.toNativeUtf8();
                    i++;
                  }
                }

                final bool result = bindings.raw_data_to_printer(
                  namePtr.cast(),
                  dataPtr,
                  data.data.length,
                  docNamePtr.cast(),
                  numOptions,
                  keysPtr.cast(),
                  valuesPtr.cast(),
                );
                if (result) {
                  sendPort.send(_PrintResponse(data.id, true));
                } else {
                  final errorMsg = getLastError().toDartString();
                  sendPort.send(_ErrorResponse(data.id, PrintingFfiException(errorMsg), StackTrace.current));
                }
              } finally {
                if (numOptions > 0) {
                  for (var i = 0; i < numOptions; i++) {
                    malloc.free(keysPtr[i]);
                    malloc.free(valuesPtr[i]);
                  }
                  malloc.free(keysPtr);
                  malloc.free(valuesPtr);
                }
              }
            } finally {
              malloc.free(namePtr);
              malloc.free(docNamePtr);
              malloc.free(dataPtr);
            }
          } catch (e, s) {
            sendPort.send(_ErrorResponse(data.id, e, s));
          }
        } else if (data is _PrintJobsRequest) {
          try {
            final namePtr = data.printerName.toNativeUtf8();
            try {
              final jobListPtr = bindings.get_print_jobs(namePtr.cast());
              final jobs = <PrintJob>[];
              if (jobListPtr != nullptr) {
                try {
                  final jobList = jobListPtr.ref;
                  for (var i = 0; i < jobList.count; i++) {
                    final jobInfo = jobList.jobs[i];
                    jobs.add(
                      PrintJob(
                        jobInfo.id,
                        jobInfo.title.cast<Utf8>().toDartString(),
                        jobInfo.status,
                      ),
                    );
                  }
                } finally {
                  bindings.free_job_list(jobListPtr);
                }
              }
              sendPort.send(_PrintJobsResponse(data.id, jobs));
            } finally {
              malloc.free(namePtr);
            }
          } catch (e, s) {
            sendPort.send(_ErrorResponse(data.id, e, s));
          }
        } else if (data is _PrintJobActionRequest) {
          try {
            final namePtr = data.printerName.toNativeUtf8();
            try {
              bool result = false;
              if (data.action == 'pause') {
                result = bindings.pause_print_job(namePtr.cast(), data.jobId);
              } else if (data.action == 'resume') {
                result = bindings.resume_print_job(namePtr.cast(), data.jobId);
              } else if (data.action == 'cancel') {
                result = bindings.cancel_print_job(namePtr.cast(), data.jobId);
              }
              sendPort.send(_PrintJobActionResponse(data.id, result));
            } finally {
              malloc.free(namePtr);
            }
          } catch (e, s) {
            sendPort.send(_ErrorResponse(data.id, e, s));
          }
        } else if (data is _GetCupsOptionsRequest) {
          try {
            final namePtr = data.printerName.toNativeUtf8();
            try {
              final optionListPtr = bindings.get_supported_cups_options(namePtr.cast());
              final options = <CupsOptionModel>[];
              if (optionListPtr != nullptr) {
                try {
                  final optionList = optionListPtr.ref;
                  for (var i = 0; i < optionList.count; i++) {
                    final optionInfo = optionList.options[i];
                    final supportedValues = <CupsOptionChoiceModel>[];
                    final choiceList = optionInfo.supported_values;
                    for (var j = 0; j < choiceList.count; j++) {
                      final choiceInfo = choiceList.choices[j];
                      supportedValues.add(
                        CupsOptionChoiceModel(
                          choice: choiceInfo.choice.cast<Utf8>().toDartString(),
                          text: choiceInfo.text.cast<Utf8>().toDartString(),
                        ),
                      );
                    }
                    options.add(
                      CupsOptionModel(
                        name: optionInfo.name.cast<Utf8>().toDartString(),
                        defaultValue: optionInfo.default_value.cast<Utf8>().toDartString(),
                        supportedValues: supportedValues,
                      ),
                    );
                  }
                } finally {
                  bindings.free_cups_option_list(optionListPtr);
                }
              }
              sendPort.send(_GetCupsOptionsResponse(data.id, options));
            } finally {
              malloc.free(namePtr);
            }
          } catch (e, s) {
            sendPort.send(_ErrorResponse(data.id, e, s));
          }
        } else if (data is _GetWindowsCapsRequest) {
          try {
            final namePtr = data.printerName.toNativeUtf8();
            try {
              final capsPtr = bindings.get_windows_printer_capabilities(namePtr.cast());
              if (capsPtr == nullptr) {
                sendPort.send(_GetWindowsCapsResponse(data.id, null));
              } else {
                try {
                  final caps = capsPtr.ref;
                  final paperSizes = <WindowsPaperSize>[];
                  for (var i = 0; i < caps.paper_sizes.count; i++) {
                    final size = caps.paper_sizes.papers[i];
                    paperSizes.add(
                      WindowsPaperSize(
                        id: size.id,
                        name: size.name.cast<Utf8>().toDartString(),
                        widthMillimeters: size.width_mm,
                        heightMillimeters: size.height_mm,
                      ),
                    );
                  }

                  final paperSources = <WindowsPaperSource>[];
                  for (var i = 0; i < caps.paper_sources.count; i++) {
                    final source = caps.paper_sources.sources[i];
                    paperSources.add(
                      WindowsPaperSource(
                        id: source.id,
                        name: source.name.cast<Utf8>().toDartString(),
                      ),
                    );
                  }

                  final mediaTypes = <WindowsMediaType>[];
                  for (var i = 0; i < caps.media_types.count; i++) {
                    final type = caps.media_types.types[i];
                    mediaTypes.add(
                      WindowsMediaType(
                        id: type.id,
                        name: type.name.cast<Utf8>().toDartString(),
                      ),
                    );
                  }

                  final resolutions = <WindowsResolution>[];
                  for (var i = 0; i < caps.resolutions.count; i++) {
                    final res = caps.resolutions.resolutions[i];
                    resolutions.add(WindowsResolution(xdpi: res.x_dpi, ydpi: res.y_dpi));
                  }

                  final model = WindowsPrinterCapabilitiesModel(
                    paperSizes: paperSizes,
                    paperSources: paperSources,
                    mediaTypes: mediaTypes,
                    resolutions: resolutions,
                    isColorSupported: caps.is_color_supported,
                    isMonochromeSupported: caps.is_monochrome_supported,
                    supportsLandscape: caps.supports_landscape,
                  );
                  sendPort.send(_GetWindowsCapsResponse(data.id, model));
                } finally {
                  bindings.free_windows_printer_capabilities(capsPtr);
                }
              }
            } finally {
              malloc.free(namePtr);
            }
          } catch (e, s) {
            sendPort.send(_ErrorResponse(data.id, e, s));
          }
        } else if (data is _OpenPrinterPropertiesRequest) {
          try {
            final namePtr = data.printerName.toNativeUtf8();
            try {
              final result = bindings.open_printer_properties(namePtr.cast(), data.hwnd);
              final responseResult = switch (result) {
                1 => PrinterPropertiesResult.ok,
                2 => PrinterPropertiesResult.cancel,
                _ => PrinterPropertiesResult.error,
              };
              sendPort.send(_OpenPrinterPropertiesResponse(data.id, responseResult));
            } finally {
              malloc.free(namePtr);
            }
          } catch (e, s) {
            sendPort.send(_ErrorResponse(data.id, e, s));
          }
        } else if (data is _PrintPdfRequest) {
          try {
            final namePtr = data.printerName.toNativeUtf8();
            final pathPtr = data.pdfFilePath.toNativeUtf8();
            final docNamePtr = data.docName.toNativeUtf8();
            final pageRangeValue = data.pageRange;
            final alignmentPtr = data.alignment.toNativeUtf8();
            final pageRangePtr = pageRangeValue?.toNativeUtf8() ?? nullptr;
            try {
              final options = {...?data.options};
              if (Platform.isMacOS || Platform.isLinux) {
                if (data.copies > 1) options['copies'] = data.copies.toString();
                if (pageRangeValue != null && pageRangeValue.isNotEmpty) options['page-ranges'] = pageRangeValue;
              }
              _remapCupsOptions(options);

              final int numOptions = options.length;
              Pointer<Pointer<Utf8>> keysPtr = nullptr;
              Pointer<Pointer<Utf8>> valuesPtr = nullptr;

              if (numOptions > 0) {
                keysPtr = malloc<Pointer<Utf8>>(numOptions);
                valuesPtr = malloc<Pointer<Utf8>>(numOptions);
                int i = 0;
                for (var entry in options.entries) {
                  keysPtr[i] = entry.key.toNativeUtf8();
                  valuesPtr[i] = entry.value.toNativeUtf8();
                  i++;
                }
              }

              final bool result = bindings.print_pdf(
                namePtr.cast(),
                pathPtr.cast(),
                docNamePtr.cast(),
                data.scalingMode,
                data.copies,
                pageRangePtr.cast(),
                numOptions,
                keysPtr.cast(),
                valuesPtr.cast(),
                alignmentPtr.cast(),
              );
              if (result) {
                sendPort.send(_PrintPdfResponse(data.id, true));
              } else {
                final errorMsg = getLastError().toDartString();
                sendPort.send(_ErrorResponse(data.id, PrintingFfiException(errorMsg), StackTrace.current));
              }

              if (numOptions > 0) {
                for (var i = 0; i < numOptions; i++) {
                  malloc.free(keysPtr[i]);
                  malloc.free(valuesPtr[i]);
                }
                malloc.free(keysPtr);
                malloc.free(valuesPtr);
              }
            } finally {
              malloc.free(namePtr);
              malloc.free(pathPtr);
              malloc.free(docNamePtr);
              if (pageRangePtr != nullptr) malloc.free(pageRangePtr);
              malloc.free(alignmentPtr);
            }
          } catch (e, s) {
            sendPort.send(_ErrorResponse(data.id, e, s));
          }
        } else if (data is _SubmitRawDataJobRequest) {
          try {
            final namePtr = data.printerName.toNativeUtf8();
            final docNamePtr = data.docName.toNativeUtf8();
            final dataPtr = malloc<Uint8>(data.data.length);
            dataPtr.asTypedList(data.data.length).setAll(0, data.data);
            try {
              final options = {...?data.options};
              _remapCupsOptions(options);
              final int numOptions = options.length;
              Pointer<Pointer<Utf8>> keysPtr = nullptr;
              Pointer<Pointer<Utf8>> valuesPtr = nullptr;

              try {
                if (numOptions > 0) {
                  keysPtr = malloc<Pointer<Utf8>>(numOptions);
                  valuesPtr = malloc<Pointer<Utf8>>(numOptions);
                  int i = 0;
                  for (var entry in options.entries) {
                    keysPtr[i] = entry.key.toNativeUtf8();
                    valuesPtr[i] = entry.value.toNativeUtf8();
                    i++;
                  }
                }

                final int jobId = bindings.submit_raw_data_job(
                  namePtr.cast(),
                  dataPtr,
                  data.data.length,
                  docNamePtr.cast(),
                  numOptions,
                  keysPtr.cast(),
                  valuesPtr.cast(),
                );
                if (jobId > 0) {
                  sendPort.send(_SubmitJobResponse(data.id, jobId));
                } else {
                  final errorMsg = getLastError().toDartString();
                  sendPort.send(_ErrorResponse(data.id, PrintingFfiException(errorMsg), StackTrace.current));
                }
              } finally {
                if (numOptions > 0) {
                  for (var i = 0; i < numOptions; i++) {
                    malloc.free(keysPtr[i]);
                    malloc.free(valuesPtr[i]);
                  }
                  malloc.free(keysPtr);
                  malloc.free(valuesPtr);
                }
              }
            } finally {
              malloc.free(namePtr);
              malloc.free(docNamePtr);
              malloc.free(dataPtr);
            }
          } catch (e, s) {
            sendPort.send(_ErrorResponse(data.id, e, s));
          }
        } else if (data is _SubmitPdfJobRequest) {
          try {
            final namePtr = data.printerName.toNativeUtf8();
            final pathPtr = data.pdfFilePath.toNativeUtf8();
            final docNamePtr = data.docName.toNativeUtf8();
            final pageRangeValue = data.pageRange;
            final alignmentPtr = data.alignment.toNativeUtf8();
            final pageRangePtr = pageRangeValue?.toNativeUtf8() ?? nullptr;
            try {
              final options = {...?data.options};
              if (Platform.isMacOS || Platform.isLinux) {
                if (data.copies > 1) options['copies'] = data.copies.toString();
                if (pageRangeValue != null && pageRangeValue.isNotEmpty) options['page-ranges'] = pageRangeValue;
              }
              _remapCupsOptions(options);

              final int numOptions = options.length;
              Pointer<Pointer<Utf8>> keysPtr = nullptr;
              Pointer<Pointer<Utf8>> valuesPtr = nullptr;

              if (numOptions > 0) {
                keysPtr = malloc<Pointer<Utf8>>(numOptions);
                valuesPtr = malloc<Pointer<Utf8>>(numOptions);
                int i = 0;
                for (var entry in options.entries) {
                  keysPtr[i] = entry.key.toNativeUtf8();
                  valuesPtr[i] = entry.value.toNativeUtf8();
                  i++;
                }
              }

              final int jobId = bindings.submit_pdf_job(
                namePtr.cast(),
                pathPtr.cast(),
                docNamePtr.cast(),
                data.scalingMode,
                data.copies,
                pageRangePtr.cast(),
                numOptions,
                keysPtr.cast(),
                valuesPtr.cast(),
                alignmentPtr.cast(),
              );
              if (jobId > 0) {
                sendPort.send(_SubmitJobResponse(data.id, jobId));
              } else {
                final errorMsg = getLastError().toDartString();
                sendPort.send(_ErrorResponse(data.id, PrintingFfiException(errorMsg), StackTrace.current));
              }

              if (numOptions > 0) {
                for (var i = 0; i < numOptions; i++) {
                  malloc.free(keysPtr[i]);
                  malloc.free(valuesPtr[i]);
                }
                malloc.free(keysPtr);
                malloc.free(valuesPtr);
              }
            } finally {
              malloc.free(namePtr);
              malloc.free(pathPtr);
              malloc.free(docNamePtr);
              if (pageRangePtr != nullptr) malloc.free(pageRangePtr);
              malloc.free(alignmentPtr);
            }
          } catch (e, s) {
            sendPort.send(_ErrorResponse(data.id, e, s));
          }
        }
      });

      sendPort.send(helperReceivePort.sendPort);
    },
    (error, stack) {
      sendPort.send([error.toString(), stack.toString()]);
    },
  );
}
