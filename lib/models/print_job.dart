import 'dart:io';

/// Represents the status of a print job.
///
/// ## Print Job Lifecycle
///
/// A print job typically progresses through several states from submission to completion.
/// The exact flow can vary between operating systems.
///
/// ### Windows State Graph
/// A common lifecycle for a successful print job on Windows is:
///
/// `pending` -> `spooling` -> `processing` -> `printed` -> `completed`
///
/// - **pending**: The job is in the queue, waiting for its turn.
/// - **spooling**: The job's data is being written to a temporary file.
/// - **processing**: The spooled data is being sent to the printer.
/// - **printed**: The computer has finished sending all data to the printer.
/// - **completed**: The printer has finished the job, and it is removed from the queue.
///
/// Other states can interrupt this flow:
/// - **Error States**: `error`, `userIntervention`, `paperOut`, `offline`, `blocked`.
/// - **User Actions**: `paused`, `restarting`, `deleting` -> `canceled`.
///
/// ### CUPS (macOS & Linux) State Graph
/// A common lifecycle on CUPS-based systems is simpler:
///
/// `pending` -> `processing` -> `completed`
///
/// Other states can interrupt this flow: `held`, `stopped`, `canceled`, `aborted`.
enum PrintJobStatus {
  // Common states
  /// The job has been created but is not yet processing. It may be waiting for
  /// other jobs to complete.
  /// - **CUPS**: `IPP_JOB_PENDING` (3)
  /// - **Windows**: No status flags set (0)
  /// - **Example**: A user sends a document to a busy office printer. The job enters the `pending` state while it waits for two other documents to finish printing.
  pending('Pending'),

  /// The job is currently being sent to the printer or is being printed.
  /// - **CUPS**: `IPP_JOB_PROCESSING` (5)
  /// - **Windows**: `JOB_STATUS_PRINTING` (16)
  /// - **Example**: After spooling, the job's data is actively being sent to the printer. The printer has started to pull paper and print the first page. The job is now `processing`. This continues until the print process is finished.
  processing('Processing'),

  /// The job has finished sending data to the printer. On some systems, this
  /// may be a transitional state before `completed`.
  /// - **Windows**: `JOB_STATUS_PRINTED` (128)
  /// - **Example**: (Windows) The print spooler has successfully sent all pages of the document to the printer's internal buffer. The job is marked as `printed`. The computer's role is done, but the printer might still be physically printing the last few pages before the job is finally `completed`.
  printed('Printed'), // Windows

  /// The job has finished all processing and is considered fully complete.
  /// - **CUPS**: `IPP_JOB_COMPLETED` (9)
  /// - **Windows**: `JOB_STATUS_COMPLETE` (4096)
  /// - **Example**: The printing process is finished, and all pages have been physically ejected from the printer. The job is removed from the active queue and marked as `completed`.
  completed('Completed'),

  /// The job was explicitly canceled by a user or an administrator.
  /// - **CUPS**: `IPP_JOB_CANCELED` (7)
  /// - **Windows**: `JOB_STATUS_DELETED` (256)
  /// - **Example**: A user accidentally prints a 100-page document. They open the print queue and cancel the job before it finishes. The job's final status is `canceled`.
  canceled('Canceled'),

  /// The job was aborted by the system due to an error or other condition.
  /// - **CUPS**: `IPP_JOB_ABORTED` (8)
  /// - **Example**: (CUPS) The printer loses power mid-print. When it comes back online, the CUPS server aborts the incomplete job.
  aborted('Aborted'),

  /// An error occurred that prevents the job from printing.
  /// - **Windows**: `JOB_STATUS_ERROR` (2)
  /// - **Example**: (Windows) The print driver is corrupted or incompatible with the data being sent, causing the job to enter an `error` state.
  error('Error'),

  /// The job status could not be determined.
  /// - **Example**: The plugin receives a status code from the operating system that doesn't map to any known state.
  unknown('Unknown'),

  // Platform-specific or nuanced states
  /// The job is held and will not print until released.
  /// - **CUPS**: `IPP_JOB_HELD` (4)
  /// - **Example**: (CUPS) In a secure printing environment, a job is sent to the printer but is `held` until the user authenticates at the printer with a badge.
  held('Held'), // CUPS

  /// The printer has been stopped, and the job is paused.
  /// - **CUPS**: `IPP_JOB_STOPPED` (6)
  /// - **Example**: (CUPS) An administrator stops the printer queue to perform maintenance. All jobs in the queue, including the currently processing one, enter the `stopped` state.
  stopped('Stopped'), // CUPS

  /// The job has been paused by a user or administrator.
  /// - **Windows**: `JOB_STATUS_PAUSED` (1)
  /// - **Example**: (Windows) A user pauses their own print job to change the paper tray, then resumes it. While paused, the job status is `paused`.
  paused('Paused'), // Windows

  /// The job is being written to a spool file on the disk.
  /// - **Windows**: `JOB_STATUS_SPOOLING` (8)
  /// - **Example**: (Windows) A large PDF is being printed. The system first writes the print-ready data to a temporary file on the hard drive. During this process, the job is `spooling`. Once finished, it will transition to `processing`.
  spooling('Spooling'), // Windows

  /// The job is in the process of being deleted.
  /// - **Windows**: `JOB_STATUS_DELETING` (4)
  /// - **Example**: (Windows) After a job is canceled, it briefly enters the `deleting` state while the system cleans up its associated spool file.
  deleting('Deleting'), // Windows

  /// The job has been restarted and is being printed again.
  /// - **Windows**: `JOB_STATUS_RESTART` (2048)
  /// - **Example**: (Windows) A job was blocked due to a printer error. After the error is resolved, the job is automatically `restarting`.
  restarting('Restarting'), // Windows

  /// The printer is offline.
  /// - **Windows**: `JOB_STATUS_OFFLINE` (32)
  /// - **Example**: (Windows) A user tries to print to a network printer that is turned off. The job enters the queue with an `offline` status.
  offline('Offline'), // Windows

  /// The printer is out of paper.
  /// - **Windows**: `JOB_STATUS_PAPEROUT` (64)
  /// - **Example**: (Windows) A multi-page document stops printing midway through. The job status changes to `paperOut` and a notification appears on the user's screen.
  paperOut('Paper Out'), // Windows

  /// The printer requires user intervention (e.g., to load paper, fix a jam).
  /// - **Windows**: `JOB_STATUS_USER_INTERVENTION` (1024)
  /// - **Example**: (Windows) A paper jam occurs. The job status becomes `userIntervention` until someone clears the jam.
  userIntervention('User Intervention'), // Windows

  /// The job is blocked, for example, because a preceding job has an error.
  /// - **Windows**: `JOB_STATUS_BLOCKED_DEVQ` (512)
  /// - **Example**: (Windows) Job A has an error (e.g., `paperOut`). Job B, which was sent after Job A, is now `blocked` and will not print until Job A is resolved or canceled.
  blocked('Blocked'), // Windows

  /// The job has completed but is retained in the queue for re-printing.
  /// - **Windows**: `JOB_STATUS_RETAINED` (8192)
  /// - **Example**: (Windows) A printer is configured to keep completed jobs. After printing, the job's status changes to `retained`, allowing a user to easily reprint it from the queue history.
  retained('Retained'); // Windows

  const PrintJobStatus(this.description);

  /// A user-friendly description of the status.
  final String description;

  /// Creates a [PrintJobStatus] from a raw platform-specific integer value.
  static PrintJobStatus fromRaw(int status) {
    if (Platform.isMacOS || Platform.isLinux) {
      // CUPS IPP Job States
      return switch (status) {
        3 => PrintJobStatus.pending, // IPP_JOB_PENDING
        4 => PrintJobStatus.held, // IPP_JOB_HELD
        5 => PrintJobStatus.processing, // IPP_JOB_PROCESSING
        6 => PrintJobStatus.stopped, // IPP_JOB_STOPPED
        7 => PrintJobStatus.canceled, // IPP_JOB_CANCELED
        8 => PrintJobStatus.aborted, // IPP_JOB_ABORTED
        9 => PrintJobStatus.completed, // IPP_JOB_COMPLETED
        _ => PrintJobStatus.unknown,
      };
    }

    if (Platform.isWindows) {
      // Windows Job Status bit flags. The order of checks determines priority.
      // A job can have multiple status flags, so we check from most to least critical.
      // The values correspond to the JOB_STATUS_* constants in the Windows Spooler API.

      // 1. Critical error states that halt the job.
      if ((status & 2) != 0) return PrintJobStatus.error; // JOB_STATUS_ERROR (2)
      if ((status & 1024) != 0) return PrintJobStatus.userIntervention; // JOB_STATUS_USER_INTERVENTION (1024)
      if ((status & 64) != 0) return PrintJobStatus.paperOut; // JOB_STATUS_PAPEROUT (64)
      if ((status & 32) != 0) return PrintJobStatus.offline; // JOB_STATUS_OFFLINE (32)
      if ((status & 512) != 0) return PrintJobStatus.blocked; // JOB_STATUS_BLOCKED_DEVQ (512)

      // 2. Terminal states (job is finished). These have priority over active states.
      if ((status & 8192) != 0) return PrintJobStatus.retained; // JOB_STATUS_RETAINED (8192)
      // JOB_STATUS_COMPLETE is a more definitive state than PRINTED, so check it first.
      if ((status & 4096) != 0) return PrintJobStatus.completed; // JOB_STATUS_COMPLETE (4096)
      if ((status & 128) != 0) return PrintJobStatus.printed; // JOB_STATUS_PRINTED (128)
      if ((status & 256) != 0) return PrintJobStatus.canceled; // JOB_STATUS_DELETED (256)

      // 3. Active/transient states (job is in progress, paused, or being managed).
      if ((status & 4) != 0) return PrintJobStatus.deleting; // JOB_STATUS_DELETING (4)
      if ((status & 2048) != 0) return PrintJobStatus.restarting; // JOB_STATUS_RESTART (2048)
      if ((status & 1) != 0) return PrintJobStatus.paused; // JOB_STATUS_PAUSED (1)
      if ((status & 16) != 0) return PrintJobStatus.processing; // JOB_STATUS_PRINTING (16)
      if ((status & 8) != 0) return PrintJobStatus.spooling; // JOB_STATUS_SPOOLING (8)

      // 4. Default pending state if no other flags are set.
      if (status == 0) return PrintJobStatus.pending; // No flags, likely queued.

      return PrintJobStatus.unknown;
    }

    return PrintJobStatus.unknown;
  }
}

class PrintJob {
  final int id;
  final String title;

  /// The raw platform-specific status value.
  final int rawStatus;

  /// The parsed, cross-platform status.
  final PrintJobStatus status;

  PrintJob(this.id, this.title, this.rawStatus) : status = PrintJobStatus.fromRaw(rawStatus);

  /// A user-friendly description of the status.
  String get statusDescription => status.description;
}
