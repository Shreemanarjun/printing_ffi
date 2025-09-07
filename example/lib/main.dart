import 'package:flutter/material.dart';
import 'package:printing_ffi/printing_ffi.dart';
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
        cardTheme: CardThemeData(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
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
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  Printer? selectedPrinter;
  List<PrintJob> jobs = [];
  List<Printer> printers = [];
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
        selectedPrinter = printers.isNotEmpty ? printers.first : null;
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
      final jobList = await listPrintJobs(selectedPrinter!.name);
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
    if (!selectedPrinter!.isAvailable) {
      _showSnackBar('Cannot print: Printer is offline', isError: true);
      return;
    }
    setState(() => isLoading = true);
    try {
      final rawData = Uint8List.fromList([
        0x1B,
        0x40,
        0x48,
        0x65,
        0x6C,
        0x6C,
        0x6F,
        0x0A,
      ]); // "Hello\n" in ASCII
      final success = await rawDataToPrinter(selectedPrinter!.name, rawData);
      setState(() => isLoading = false);
      _showSnackBar(
        success ? 'Print job sent successfully' : 'Failed to send print job',
        isError: !success,
      );
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
      final success = await pausePrintJob(selectedPrinter!.name, jobId);
      setState(() => isLoading = false);
      _showSnackBar(
        success ? 'Job paused successfully' : 'Failed to pause job',
        isError: !success,
      );
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
      final success = await resumePrintJob(selectedPrinter!.name, jobId);
      setState(() => isLoading = false);
      _showSnackBar(
        success ? 'Job resumed successfully' : 'Failed to resume job',
        isError: !success,
      );
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
      final success = await cancelPrintJob(selectedPrinter!.name, jobId);
      setState(() => isLoading = false);
      _showSnackBar(
        success ? 'Job canceled successfully' : 'Failed to cancel job',
        isError: !success,
      );
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

  void _selectDefaultPrinter() {
    final defaultPrinter = getDefaultPrinter();
    if (defaultPrinter != null) {
      // Find the corresponding printer object in our state list to ensure
      // we're using the same instance for the DropdownButton.
      final printerInList = printers.cast<Printer?>().firstWhere(
            (p) => p!.name == defaultPrinter.name,
            orElse: () => null,
          );

      if (printerInList != null) {
        setState(() {
          selectedPrinter = printerInList;
          _loadJobs();
          _showSnackBar('Selected default printer: ${printerInList.name}');
        });
      } else {
        _showSnackBar('Default printer "${defaultPrinter.name}" not in list. Try refreshing.', isError: true);
      }
    } else {
      _showSnackBar('No default printer found.', isError: true);
    }
  }

  Widget _buildDetailRow(String label, String? value) {
    if (value == null || value.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                DropdownButton<Printer>(
                  value: selectedPrinter,
                  hint: const Text('No printers found'),
                  items: printers.map((printer) {
                    return DropdownMenuItem<Printer>(
                      value: printer,
                      child: Text(
                        '${printer.name} ${!printer.isAvailable ? '(Offline)' : ''}',
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
            if (selectedPrinter != null)
              Card(
                margin: const EdgeInsets.only(top: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Printer Details',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Divider(height: 16),
                      _buildDetailRow('Model', selectedPrinter!.model),
                      _buildDetailRow('Location', selectedPrinter!.location),
                      _buildDetailRow('Comment', selectedPrinter!.comment),
                      _buildDetailRow('URL', selectedPrinter!.url),
                      _buildDetailRow(
                        'Default',
                        selectedPrinter!.isDefault.toString(),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.print),
                  label: const Text('Print Test'),
                  onPressed: isLoading || selectedPrinter == null
                      ? null
                      : _printTest,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Jobs'),
                  onPressed: isLoading || selectedPrinter == null
                      ? null
                      : _loadJobs,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.star_border),
                  label: const Text('Select Default'),
                  onPressed: isLoading
                      ? null
                      : _selectDefaultPrinter,
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
                        subtitle: Text(
                          'ID: ${job.id}, Status: ${job.statusDescription}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.pause, color: Colors.blue),
                              tooltip: 'Pause Job',
                              onPressed: isLoading
                                  ? null
                                  : () => _pausePrintJob(job.id),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.play_arrow,
                                color: Colors.green,
                              ),
                              tooltip: 'Resume Job',
                              onPressed: isLoading
                                  ? null
                                  : () => _resumePrintJob(job.id),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              tooltip: 'Cancel Job',
                              onPressed: isLoading
                                  ? null
                                  : () => _cancelPrintJob(job.id),
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
