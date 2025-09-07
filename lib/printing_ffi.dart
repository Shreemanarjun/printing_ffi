import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'printing_ffi_bindings_generated.dart';

class PrintJob {
  final int id;
  final String title;
  final int status;

  PrintJob(this.id, this.title, this.status);

  String get statusDescription {
    return switch (status) {
      0x00000100 ||
      5 => 'Printing', // Windows JOB_STATUS_PRINTING | CUPS IPP_JOB_PROCESSING
      0x00000004 ||
      4 => 'Paused', // Windows JOB_STATUS_PAUSED | CUPS IPP_JOB_HELD
      _ => 'Unknown ($status)',
    };
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
List<Map<String, dynamic>> listPrinters() {
  final countPtr = malloc<Int>();
  final printerListPtr = malloc<Pointer<Char>>();
  final printerStatesPtr = malloc<Uint32>(100); // Assume max 100 printers
  try {
    if (_bindings.list_printers(printerListPtr, countPtr, printerStatesPtr)) {
      final count = countPtr.value;
      final printers = <Map<String, dynamic>>[];
      for (var i = 0; i < count; i++) {
        final namePtr = printerListPtr.value + (i * 256);
        printers.add({
          'name': namePtr.cast<Utf8>().toDartString(),
          'state': printerStatesPtr[i],
        });
      }
      return printers;
    }
    return [];
  } finally {
    malloc.free(countPtr);
    malloc.free(printerListPtr);
    malloc.free(printerStatesPtr);
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
          final countPtr = malloc<Int>();
          final jobIdsPtr = malloc<Uint32>(100);
          final jobTitlesPtr = malloc<Pointer<Char>>();
          final jobStatusesPtr = malloc<Uint32>(100);
          final namePtr = data.printerName.toNativeUtf8();
          try {
            final jobs = <PrintJob>[];
            if (_bindings.list_print_jobs(
              namePtr.cast(),
              jobIdsPtr,
              jobTitlesPtr,
              jobStatusesPtr,
              countPtr,
            )) {
              final count = countPtr.value;
              for (var i = 0; i < count; i++) {
                final titlePtr = jobTitlesPtr.value + (i * 256);
                jobs.add(
                  PrintJob(
                    jobIdsPtr[i],
                    titlePtr.cast<Utf8>().toDartString(),
                    jobStatusesPtr[i],
                  ),
                );
              }
            }
            sendPort.send(_PrintJobsResponse(data.id, jobs));
          } finally {
            malloc.free(countPtr);
            malloc.free(jobIdsPtr);
            malloc.free(jobTitlesPtr);
            malloc.free(jobStatusesPtr);
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
