import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:printing_ffi/printing_ffi.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Enum for different types of raw data commands.
enum RawDataType {
  zpl('ZPL'),
  escPos('ESC/POS'),
  custom('Custom');

  const RawDataType(this.label);
  final String label;
}

/// A local helper class to represent the custom scaling option in the UI.
/// This is a marker class for the SegmentedButton.
class CustomScaling {
  const CustomScaling();
}

/// Helper function to get display names for duplex modes.
String _getDuplexModeDisplayName(DuplexMode mode) {
  switch (mode) {
    case DuplexMode.singleSided:
      return 'Single-sided';
    case DuplexMode.duplexLongEdge:
      return 'Duplex (Long Edge)';
    case DuplexMode.duplexShortEdge:
      return 'Duplex (Short Edge)';
  }
}

class PrinterSelector extends StatelessWidget {
  const PrinterSelector({
    super.key,
    required this.printers,
    required this.selectedPrinter,
    required this.onChanged,
  });

  final List<Printer> printers;
  final Printer? selectedPrinter;
  final ValueChanged<Printer?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('Printer:', style: ShadTheme.of(context).textTheme.large),
        const SizedBox(width: 10),
        Expanded(
          child: ShadSelect<Printer>(
            placeholder: const Text('Select a printer'),
            selectedOptionBuilder: (context, value) => Text(value.name),
            initialValue: selectedPrinter,
            onChanged: onChanged,
            options: printers.map(
              (p) => ShadOption(value: p, child: Text(p.name)),
            ),
          ),
        ),
      ],
    );
  }
}

class JobsList extends StatelessWidget {
  const JobsList({
    super.key,
    required this.isLoading,
    required this.jobs,
    required this.onManageJob,
  });

  final bool isLoading;
  final List<PrintJob> jobs;
  final void Function(int jobId, String action) onManageJob;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Print Queue', style: ShadTheme.of(context).textTheme.h4),
        const SizedBox(height: 10),
        if (isLoading) const Center(child: CircularProgressIndicator()),
        if (!isLoading && jobs.isEmpty) const Text('No active print jobs.'),
        if (!isLoading && jobs.isNotEmpty)
          SizedBox(
            height: 200,
            child: ListView.builder(
              itemCount: jobs.length,
              itemBuilder: (context, index) {
                final job = jobs[index];
                return ShadCard(
                  child: ListTile(
                    title: Text(job.title),
                    subtitle: Text(
                      'ID: ${job.id} - Status: ${job.statusDescription}',
                    ),
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        ShadIconButton.ghost(
                          icon: const Icon(Icons.pause, size: 16),
                          onPressed: () => onManageJob(job.id, 'pause'),
                        ),
                        ShadIconButton.ghost(
                          icon: const Icon(Icons.play_arrow, size: 16),
                          onPressed: () => onManageJob(job.id, 'resume'),
                        ),
                        ShadIconButton.ghost(
                          icon: const Icon(Icons.cancel, size: 16),
                          onPressed: () => onManageJob(job.id, 'cancel'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class AdvancedTab extends StatelessWidget {
  const AdvancedTab({
    super.key,
    required this.isLoading,
    required this.cupsOptions,
    required this.selectedCupsOptions,
    required this.onOptionChanged,
    required this.onPrint,
  });

  final bool isLoading;
  final List<CupsOptionModel>? cupsOptions;
  final Map<String, String> selectedCupsOptions;
  final void Function(String key, String value) onOptionChanged;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS && !Platform.isLinux) {
      return const Center(
        child: Text(
          'Advanced CUPS options are only available on macOS and Linux.',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        ShadCard(
          title: Text(
            'CUPS Options',
            style: ShadTheme.of(context).textTheme.h4,
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isLoading) const Center(child: CircularProgressIndicator()),
                if (!isLoading && (cupsOptions == null || cupsOptions!.isEmpty))
                  const Text('No CUPS options found for this printer.'),
                if (!isLoading &&
                    cupsOptions != null &&
                    cupsOptions!.isNotEmpty)
                  ..._buildCupsOptionWidgets(context),
                const SizedBox(height: 20),
                ShadButton(
                  leading: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                  onPressed: onPrint,
                  child: const Text('Print PDF with Selected Options'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCupsOptionWidgets(BuildContext context) {
    if (cupsOptions == null) return [];
    return cupsOptions!.map((option) {
      final currentValue = selectedCupsOptions[option.name];
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ShadSelect<String>(
          placeholder: Text(option.name),
          selectedOptionBuilder: (context, value) {
            final selectedChoice = option.supportedValues.firstWhere(
              (c) => c.choice == value,
              orElse: () => CupsOptionChoiceModel(choice: value, text: value),
            );
            return Text(selectedChoice.text);
          },
          initialValue: currentValue,
          onChanged: (newValue) {
            if (newValue != null) onOptionChanged(option.name, newValue);
          },
          options: option.supportedValues.map(
            (choice) => ShadOption(
              value: choice.choice,
              child: Text(choice.text, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      );
    }).toList();
  }
}

class PlatformSettings extends StatelessWidget {
  const PlatformSettings({
    super.key,
    required this.isLoading,
    required this.windowsCapabilities,
    required this.selectedPaperSize,
    required this.onPaperSizeChanged,
    required this.selectedPaperSource,
    required this.onPaperSourceChanged,
    required this.selectedAlignment,
    required this.onAlignmentChanged,
    required this.selectedPrintQuality,
    required this.onPrintQualityChanged,
    required this.selectedColorMode,
    required this.onColorModeChanged,
    required this.selectedOrientation,
    required this.onOrientationChanged,
    required this.selectedDuplexMode,
    required this.onDuplexModeChanged,
    required this.onOpenProperties,
    required this.onShowCapabilities,
  });

  final bool isLoading;
  final WindowsPrinterCapabilitiesModel? windowsCapabilities;
  final WindowsPaperSize? selectedPaperSize;
  final ValueChanged<WindowsPaperSize?> onPaperSizeChanged;
  final WindowsPaperSource? selectedPaperSource;
  final ValueChanged<WindowsPaperSource?> onPaperSourceChanged;
  final PdfPrintAlignment selectedAlignment;
  final ValueChanged<PdfPrintAlignment?> onAlignmentChanged;
  final PrintQuality selectedPrintQuality;
  final ValueChanged<PrintQuality?> onPrintQualityChanged;
  final ColorMode selectedColorMode;
  final ValueChanged<ColorMode?> onColorModeChanged;
  final WindowsOrientation selectedOrientation;
  final ValueChanged<WindowsOrientation?> onOrientationChanged;
  final DuplexMode selectedDuplexMode;
  final ValueChanged<DuplexMode?> onDuplexModeChanged;
  final VoidCallback onOpenProperties;
  final VoidCallback onShowCapabilities;

  @override
  Widget build(BuildContext context) {
    final List<Widget> windowsChildren = [];
    if (Platform.isWindows) {
      if (isLoading) {
        windowsChildren.add(const Center(child: CircularProgressIndicator()));
      } else if (windowsCapabilities != null) {
        windowsChildren.addAll([
          ShadSelect<WindowsPaperSize>(
            placeholder: const Text('Paper Size'),
            selectedOptionBuilder: (context, value) => Text(value.name),
            initialValue: selectedPaperSize,
            onChanged: onPaperSizeChanged,
            options: windowsCapabilities!.paperSizes.map(
              (p) => ShadOption(
                value: p,
                child: Text(p.name, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
          ShadSelect<WindowsPaperSource>(
            placeholder: const Text('Paper Source'),
            selectedOptionBuilder: (context, value) => Text(value.name),
            initialValue: selectedPaperSource,
            onChanged: onPaperSourceChanged,
            options: windowsCapabilities!.paperSources.map(
              (s) => ShadOption(
                value: s,
                child: Text(s.name, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
          ShadSelect<PdfPrintAlignment>(
            placeholder: const Text('Alignment'),
            selectedOptionBuilder: (context, value) =>
                Text(value.name[0].toUpperCase() + value.name.substring(1)),
            initialValue: selectedAlignment,
            onChanged: onAlignmentChanged,
            options: PdfPrintAlignment.values.map(
              (a) => ShadOption(
                value: a,
                child: Text(a.name[0].toUpperCase() + a.name.substring(1)),
              ),
            ),
          ),
        ]);
      }
    }

    final List<Widget> allChildren = [
      ...windowsChildren,
      ShadSelect<PrintQuality>(
        placeholder: const Text('Print Quality'),
        selectedOptionBuilder: (context, value) =>
            Text(value.name[0].toUpperCase() + value.name.substring(1)),
        initialValue: selectedPrintQuality,
        onChanged: onPrintQualityChanged,
        options: PrintQuality.values.map(
          (q) => ShadOption(
            value: q,
            child: Text(q.name[0].toUpperCase() + q.name.substring(1)),
          ),
        ),
      ),
      ShadSelect<ColorMode>(
        placeholder: const Text('Color Mode'),
        selectedOptionBuilder: (context, value) =>
            Text(value.name[0].toUpperCase() + value.name.substring(1)),
        initialValue: selectedColorMode,
        onChanged: onColorModeChanged,
        options: ColorMode.values.map(
          (c) => Builder(
            builder: (context) {
              final enabled =
                  (c == ColorMode.color &&
                      (windowsCapabilities?.isColorSupported ?? true)) ||
                  (c == ColorMode.monochrome &&
                      (windowsCapabilities?.isMonochromeSupported ?? true));
              if (!enabled) {
                return Text(c.name[0].toUpperCase() + c.name.substring(1));
              }
              return ShadOption(
                value: c,

                child: Text(c.name[0].toUpperCase() + c.name.substring(1)),
              );
            },
          ),
        ),
      ),
      ShadSelect<WindowsOrientation>(
        placeholder: const Text('Orientation'),
        selectedOptionBuilder: (context, value) =>
            Text(value.name[0].toUpperCase() + value.name.substring(1)),
        initialValue: selectedOrientation,
        onChanged: onOrientationChanged,
        options: WindowsOrientation.values.map(
          (o) => ShadOption(
            value: o,
            child: Text(o.name[0].toUpperCase() + o.name.substring(1)),
          ),
        ),
      ),
      ShadSelect<DuplexMode>(
        placeholder: const Text('Duplex Mode'),
        selectedOptionBuilder: (context, value) =>
            Text(_getDuplexModeDisplayName(value)),
        initialValue: selectedDuplexMode,
        onChanged: onDuplexModeChanged,
        options: DuplexMode.values.map(
          (d) =>
              ShadOption(value: d, child: Text(_getDuplexModeDisplayName(d))),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: ShadCard(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Platform Settings',
                style: ShadTheme.of(context).textTheme.large,
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  childAspectRatio: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: allChildren.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: allChildren[index],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: ShadButton.outline(
                  leading: const Icon(Icons.settings_outlined, size: 16),
                  onPressed: onOpenProperties,
                  child: const Text('Open Printer Properties'),
                ),
              ),
              const SizedBox(height: 12),
              if (Platform.isWindows)
                Center(
                  child: ShadButton.secondary(
                    leading: const Icon(Icons.inventory_2_outlined, size: 16),
                    onPressed: onShowCapabilities,
                    child: const Text('Show All Capabilities'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class StandardActionsCard extends StatelessWidget {
  const StandardActionsCard({
    super.key,
    required this.selectedScaling,
    required this.onScalingChanged,
    required this.customScaleController,
    required this.selectedPdfPath,
    required this.onClearPdfPath,
    required this.onPrintPdf,
    required this.copiesController,
    required this.pageRangeController,
    required this.collate,
    required this.onCollateChanged,
    required this.onPrintPdfAndTrack,
    required this.onShowWindowsCapabilities,
    required this.rawDataController,
    required this.onPrintRawData,
    required this.onPrintRawDataAndTrack,
    required this.selectedRawDataType,
    required this.onRawDataTypeChanged,
    required this.platformSettings,
  });

  final Object selectedScaling;
  final ValueChanged<Set<Object>> onScalingChanged;
  final TextEditingController customScaleController;
  final String? selectedPdfPath;
  final VoidCallback onClearPdfPath;
  final void Function({
    Map<String, String>? cupsOptions,
    required int copies,
    required String pageRangeString,
  })
  onPrintPdf;
  final TextEditingController copiesController;
  final TextEditingController pageRangeController;
  final bool collate;
  final ValueChanged<bool> onCollateChanged;
  final VoidCallback onPrintPdfAndTrack;
  final VoidCallback onShowWindowsCapabilities;
  final TextEditingController rawDataController;
  final VoidCallback onPrintRawData;
  final VoidCallback onPrintRawDataAndTrack;
  final RawDataType selectedRawDataType;
  final ValueChanged<RawDataType?> onRawDataTypeChanged;
  final Widget platformSettings;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      title: Text('Standard Actions', style: theme.textTheme.h4),
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const breakpoint = 800; // Breakpoint for desktop/tablet layout
            if (constraints.maxWidth < breakpoint) {
              // Mobile/Tablet layout (stacked)
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  platformSettings,
                  const SizedBox(height: 24),
                  _buildActionControls(context),
                ],
              );
            } else {
              // Desktop layout (side-by-side)
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: platformSettings),
                  const SizedBox(width: 16),
                  Expanded(flex: 3, child: _buildActionControls(context)),
                ],
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildActionControls(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (Platform.isWindows)
          SegmentedButton<Object>(
            segments: const <ButtonSegment<Object>>[
              ButtonSegment(
                value: PdfPrintScaling.fitToPrintableArea,
                label: Text('Fit'),
              ),
              ButtonSegment(
                value: PdfPrintScaling.actualSize,
                label: Text('Actual'),
              ),
              ButtonSegment(
                value: PdfPrintScaling.shrinkToFit,
                label: Text('Shrink'),
              ),
              ButtonSegment(
                value: PdfPrintScaling.fitToPaper,
                label: Text('Paper'),
              ),
              ButtonSegment(value: CustomScaling(), label: Text('Custom')),
            ],
            selected: {selectedScaling},
            onSelectionChanged: onScalingChanged,
          ),
        if (Platform.isWindows && selectedScaling is CustomScaling) ...[
          const SizedBox(height: 12),
          ShadInput(
            controller: customScaleController,
            placeholder: const Text('Scale'),
          ),
        ],
        const SizedBox(height: 12),
        if (selectedPdfPath != null)
          ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: const Text('Selected PDF:'),
            subtitle: Text(
              selectedPdfPath!.split(Platform.pathSeparator).last,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: ShadIconButton.ghost(
              icon: const Icon(Icons.clear, size: 16),
              onPressed: onClearPdfPath,
            ),
          ),
        ShadButton(
          leading: const Icon(Icons.picture_as_pdf, size: 16),
          onPressed: () => onPrintPdf(
            copies: int.tryParse(copiesController.text) ?? 1,
            pageRangeString: pageRangeController.text,
          ),
          child: Text(
            selectedPdfPath == null
                ? 'Select & Print PDF'
                : 'Print Selected PDF',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ShadInput(
                controller: copiesController,
                placeholder: const Text('Copies'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: ShadInput(
                controller: pageRangeController,
                placeholder: const Text('Page Range (e.g. 1-3, 5)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ShadSwitch(value: collate, onChanged: onCollateChanged),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Collate copies'),
                  Text(
                    'Enabled: (1,2,3), (1,2,3)\nDisabled: (1,1), (2,2), (3,3)',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ShadButton.outline(
          leading: const Icon(Icons.track_changes, size: 16),
          onPressed: onPrintPdfAndTrack,
          child: const Text('Print PDF and Track Status'),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('Raw Data Printing', style: theme.textTheme.large),
            const SizedBox(width: 16),
            SizedBox(
              width: 150,
              child: ShadSelect<RawDataType>(
                selectedOptionBuilder: (context, value) => Text(value.label),
                initialValue: selectedRawDataType,
                onChanged: onRawDataTypeChanged,
                options: RawDataType.values
                    .map((e) => ShadOption(value: e, child: Text(e.label)))
                    .toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ShadInput(
          controller: rawDataController,
          placeholder: const Text('Enter raw data... e.g., for ZPL'),
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ShadButton(
                leading: const Icon(Icons.send, size: 16),
                onPressed: onPrintRawData,
                child: const Text('Print Raw Data'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ShadButton.outline(
                leading: const Icon(Icons.track_changes, size: 16),
                onPressed: onPrintRawDataAndTrack,
                child: const Text('Print & Track'),
              ),
            ),
          ],
        ),
        if (Platform.isWindows) ...[
          const SizedBox(height: 12),
          ShadButton.secondary(
            leading: const Icon(Icons.inventory_2_outlined, size: 16),
            onPressed: onShowWindowsCapabilities,
            child: const Text('Show Printer Capabilities'),
          ),
        ],
      ],
    );
  }
}

class PrintStatusDialog extends StatefulWidget {
  const PrintStatusDialog({
    super.key,
    required this.jobStream,
    required this.printerName,
    required this.onToast,
  });

  final Stream<PrintJob> jobStream;
  final String printerName;
  final void Function(String message, {bool isError}) onToast;

  @override
  State<PrintStatusDialog> createState() => _PrintStatusDialogState();
}

class _PrintStatusDialogState extends State<PrintStatusDialog> {
  StreamSubscription<PrintJob>? _subscription;
  PrintJob? _previousJob;
  PrintJob? _currentJob;
  Object? _error;
  bool _isDone = false;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () {
      if (!mounted) return;
      _subscription = widget.jobStream.listen(
        (job) {
          if (mounted) {
            setState(() {
              _previousJob = _currentJob;
              _currentJob = job;
            });
          }
        },
        onError: (error) {
          if (mounted) setState(() => _error = error);
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _isDone = true;
              // If the stream closes and the last known state wasn't terminal,
              // we can assume it completed successfully.
              if (_currentJob != null &&
                  !_isTerminalStatus(_currentJob!.status)) {
                _previousJob = _currentJob;
                // Create a synthetic 'completed' or 'printed' job status.
                final finalRawStatus = Platform.isWindows
                    ? 128
                    : 9; // JOB_STATUS_PRINTED or IPP_JOB_COMPLETED
                _currentJob = PrintJob(
                  _currentJob!.id,
                  _currentJob!.title,
                  finalRawStatus,
                );
              }
            });
          }
        },
      );
    });
  }

  bool _isTerminalStatus(PrintJobStatus status) {
    return status == PrintJobStatus.completed ||
        status == PrintJobStatus.printed ||
        status == PrintJobStatus.canceled ||
        status == PrintJobStatus.aborted ||
        status == PrintJobStatus.error;
  }

  Future<void> _cancelJob() async {
    if (_currentJob == null || !mounted) return;
    setState(() => _isCancelling = true);
    try {
      final success = await PrintingFfi.instance.cancelPrintJob(
        widget.printerName,
        _currentJob!.id,
      );
      if (!mounted) return;
      // Don't pop here; let the status stream update to 'canceled'.
      if (success) {
        widget.onToast('Cancel command sent successfully.');
      } else {
        widget.onToast('Failed to send cancel command.', isError: true);
        // If it failed, re-enable the button.
        setState(() => _isCancelling = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCancelling = false);
      widget.onToast('Error cancelling job: $e', isError: true);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    final String titleText;
    if (_currentJob != null) {
      titleText = 'Tracking Job #${_currentJob!.id}';
    } else {
      titleText = 'Tracking Print Job...';
    }

    final isJobTerminal =
        _currentJob != null && _isTerminalStatus(_currentJob!.status);
    final isSuccessState =
        _currentJob != null &&
        (_currentJob!.status == PrintJobStatus.completed ||
            _currentJob!.status == PrintJobStatus.printed);
    final isErrorState =
        _currentJob != null &&
        (_currentJob!.status == PrintJobStatus.error ||
            _currentJob!.status == PrintJobStatus.aborted ||
            _currentJob!.status == PrintJobStatus.canceled);
    final hasError = _error != null || isErrorState;

    // Handle the case where the stream completes without ever emitting a job.
    // This usually means the job printed so quickly it was never seen in the queue.
    final isImplicitlyComplete =
        _isDone && _currentJob == null && _error == null;

    final isSuccess = isSuccessState || isImplicitlyComplete;

    final isFinished = isJobTerminal || _isDone || hasError;

    final canCancel = !_isCancelling && !isFinished;

    Widget iconWidget;
    if (isSuccess) {
      iconWidget = const Icon(
        Icons.check_circle,
        color: Colors.green,
        size: 48,
      );
    } else if (hasError) {
      iconWidget = Icon(
        Icons.error,
        color: theme.colorScheme.destructive,
        size: 48,
      );
    } else {
      iconWidget = const SizedBox(
        width: 48,
        height: 48,
        child: CircularProgressIndicator(),
      );
    }

    Widget statusText;
    if (_error != null) {
      statusText = Text(
        'Error: $_error',
        style: theme.textTheme.large.copyWith(
          color: theme.colorScheme.destructive,
        ),
        textAlign: TextAlign.center,
      );
    } else if (isImplicitlyComplete || isSuccessState) {
      statusText = Text(
        'Job Completed',
        style: theme.textTheme.large,
        textAlign: TextAlign.center,
      );
    } else if (_currentJob == null) {
      statusText = Text('Submitting job...', style: theme.textTheme.large);
    } else {
      statusText = Text(
        _currentJob!.statusDescription,
        style: theme.textTheme.large,
        textAlign: TextAlign.center,
      );
    }

    Widget previousStatusText;
    if (_previousJob != null && _previousJob!.status != _currentJob?.status) {
      previousStatusText = Text(
        'From: ${_previousJob!.statusDescription}',
        style: theme.textTheme.muted,
        textAlign: TextAlign.center,
      );
    } else {
      previousStatusText = const SizedBox.shrink();
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: SizedBox(
            key: ValueKey(
              isSuccess
                  ? 'success'
                  : hasError
                  ? 'error'
                  : 'loading',
            ),
            width: 48,
            height: 48,
            child: iconWidget,
          ),
        ),
        const SizedBox(height: 20),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Align(
            key: ValueKey(_currentJob?.status.toString() ?? 'initial'),
            alignment: Alignment.center,
            child: statusText,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Align(
            key: ValueKey(_previousJob?.status.toString() ?? 'no-previous'),
            alignment: Alignment.center,
            child: previousStatusText,
          ),
        ),
      ],
    );

    return ShadDialog.alert(
      title: Text(titleText),
      actions: <Widget>[
        if (isFinished)
          ShadButton(
            child: const Text('Close'),
            onPressed: () => Navigator.of(context).pop(),
          )
        else
          ShadButton.outline(
            onPressed: canCancel ? _cancelJob : null,
            child: _isCancelling
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Cancel'),
          ),
      ],
      child: SizedBox(width: 280, height: 150, child: Center(child: content)),
    );
  }
}
