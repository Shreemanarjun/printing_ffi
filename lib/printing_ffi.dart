import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'printing_ffi_bindings_generated.dart';

class Printer {
  /// The platform specific printer identification (e.g., device URI).
  final String url;

  /// The display name of the printer.
  final String name;

  /// The printer model.
  final String? model;

  /// The physical location of the printer.
  final String? location;

  /// A user comment about the printer.
  final String? comment;

  /// Whether this is the default printer on the system.
  final bool isDefault;

  /// Whether the printer is available for printing (e.g., not offline or stopped).
  final bool isAvailable;

  /// The raw platform-specific state value.
  final int state;

  Printer({
    required this.url,
    required this.name,
    this.model,
    this.location,
    this.comment,
    required this.isDefault,
    required this.isAvailable,
    required this.state,
  });
}

class PrintJob {
  final int id;
  final String title;
  final int status;

  PrintJob(this.id, this.title, this.status);

  String get statusDescription {
    // CUPS (macOS/Linux) IPP Job States
    if (Platform.isMacOS || Platform.isLinux) {
      return switch (status) {
        3 => 'Pending', // IPP_JOB_PENDING
        4 => 'Held', // IPP_JOB_HELD
        5 => 'Processing', // IPP_JOB_PROCESSING
        6 => 'Stopped', // IPP_JOB_STOPPED
        7 => 'Canceled', // IPP_JOB_CANCELED
        8 => 'Aborted', // IPP_JOB_ABORTED
        9 => 'Completed', // IPP_JOB_COMPLETED
        _ => 'Unknown ($status)',
      };
    }

    // Windows Job Status
    if (Platform.isWindows) {
      if ((status & 0x00000001) != 0) return 'Paused'; // JOB_STATUS_PAUSED
      if ((status & 0x00000010) != 0) return 'Printing'; // JOB_STATUS_PRINTING
      if ((status & 0x00000100) != 0) return 'Printed'; // JOB_STATUS_PRINTED
      // Many other statuses exist, this is a subset.
    }

    return 'Unknown ($status)';
  }
}

// Request classes for printing operations
class _PrintRequest {
  final int id;
  final String printerName;
  final Uint8List data;
  final String docName;

  const _PrintRequest(this.id, this.printerName, this.data, this.docName);
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
  final String action; // 'pause', 'resume', 'cancel'

  const _PrintJobActionRequest(
    this.id,
    this.printerName,
    this.jobId,
    this.action,
  );
}

// Response classes
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

const String _libName = 'printing_ffi'; // Updated library name

final DynamicLibrary _dylib = () {
  if (Platform.isMacOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isLinux) return DynamicLibrary.open('lib$_libName.so');
  if (Platform.isWindows) return DynamicLibrary.open('$_libName.dll');
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

final PrintingFfiBindings _bindings = PrintingFfiBindings(
  _dylib,
); // Updated to PrintingFfiBindings

// Example functions from template
int sum(int a, int b) => _bindings.sum(a, b);

// Printing functions
List<Printer> listPrinters() {
  // Call the native function to get a pointer to the PrinterList struct.
  final printerListPtr = _bindings.get_printers();

  // If the pointer is null, it means an error occurred or no printers were found.
  if (printerListPtr == nullptr) {
    return [];
  }

  try {
    // Dereference the pointer to access the struct's data.
    final printerList = printerListPtr.ref;
    final printers = <Printer>[];
    for (var i = 0; i < printerList.count; i++) {
      final printerInfo = printerList.printers[i];

      final model = printerInfo.model.cast<Utf8>().toDartString();
      final location = printerInfo.location.cast<Utf8>().toDartString();
      final comment = printerInfo.comment.cast<Utf8>().toDartString();

      printers.add(
        Printer(
          name: printerInfo.name.cast<Utf8>().toDartString(),
          state: printerInfo.state,
          url: printerInfo.url.cast<Utf8>().toDartString(),
          model: model.isEmpty ? null : model,
          location: location.isEmpty ? null : location,
          comment: comment.isEmpty ? null : comment,
          isDefault: printerInfo.is_default,
          isAvailable: printerInfo.is_available,
        ),
      );
    }
    return printers;
  } finally {
    // IMPORTANT: Free the memory allocated by the native code.
    _bindings.free_printer_list(printerListPtr);
  }
}

Future<bool> rawDataToPrinter(
  String printerName,
  Uint8List data, {
  String docName = 'Flutter Document',
}) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextPrintRequestId++;
  final _PrintRequest request = _PrintRequest(
    requestId,
    printerName,
    data,
    docName,
  );
  final Completer<bool> completer = Completer<bool>();
  _printRequests[requestId] = completer;
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

// Isolate communication setup

int _nextPrintRequestId = 0;
int _nextPrintJobsRequestId = 0;
int _nextPrintJobActionRequestId = 0;

final Map<int, Completer<bool>> _printRequests = <int, Completer<bool>>{};
final Map<int, Completer<List<PrintJob>>> _printJobsRequests =
    <int, Completer<List<PrintJob>>>{};
final Map<int, Completer<bool>> _printJobActionRequests =
    <int, Completer<bool>>{};

Future<SendPort> _helperIsolateSendPort = () async {
  final Completer<SendPort> completer = Completer<SendPort>();
  final ReceivePort receivePort = ReceivePort()
    ..listen((dynamic data) {
      if (data is SendPort) {
        completer.complete(data);
        return;
      }

      if (data is _PrintResponse) {
        final Completer<bool> completer = _printRequests[data.id]!;
        _printRequests.remove(data.id);
        completer.complete(data.result);
        return;
      }
      if (data is _PrintJobsResponse) {
        final Completer<List<PrintJob>> completer =
            _printJobsRequests[data.id]!;
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
      throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
    });

  await Isolate.spawn((SendPort sendPort) async {
    final ReceivePort helperReceivePort = ReceivePort()
      ..listen((dynamic data) {
        if (data is _PrintRequest) {
          final namePtr = data.printerName.toNativeUtf8();
          final docNamePtr = data.docName.toNativeUtf8();
          final dataPtr = malloc<Uint8>(data.data.length);
          for (var i = 0; i < data.data.length; i++) {
            dataPtr[i] = data.data[i];
          }
          try {
            final bool result = _bindings.raw_data_to_printer(
              namePtr.cast(),
              dataPtr,
              data.data.length,
              docNamePtr.cast(),
            );
            sendPort.send(_PrintResponse(data.id, result));
          } finally {
            malloc.free(namePtr);
            malloc.free(docNamePtr);
            malloc.free(dataPtr);
          }
        } else if (data is _PrintJobsRequest) {
          final namePtr = data.printerName.toNativeUtf8();
          try {
            final jobListPtr = _bindings.get_print_jobs(namePtr.cast());
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
                // IMPORTANT: Free the memory for the job list.
                _bindings.free_job_list(jobListPtr);
              }
            }
            sendPort.send(_PrintJobsResponse(data.id, jobs));
          } finally {
            malloc.free(namePtr);
          }
        } else if (data is _PrintJobActionRequest) {
          final namePtr = data.printerName.toNativeUtf8();
          try {
            bool result = false;
            if (data.action == 'pause') {
              result = _bindings.pause_print_job(namePtr.cast(), data.jobId);
            } else if (data.action == 'resume') {
              result = _bindings.resume_print_job(namePtr.cast(), data.jobId);
            } else if (data.action == 'cancel') {
              result = _bindings.cancel_print_job(namePtr.cast(), data.jobId);
            }
            sendPort.send(_PrintJobActionResponse(data.id, result));
          } finally {
            malloc.free(namePtr);
          }
        } else {
          throw UnsupportedError(
            'Unsupported message type: ${data.runtimeType}',
          );
        }
      });

    sendPort.send(helperReceivePort.sendPort);
  }, receivePort.sendPort);

  return completer.future;
}();
