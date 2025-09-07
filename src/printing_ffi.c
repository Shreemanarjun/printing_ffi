#include "printing_ffi.h"
#include <string.h>

#ifdef _WIN32
#include <winspool.h>
#else
#include <cups/cups.h>
#include <stdio.h>
#include <stdlib.h>
#endif

FFI_PLUGIN_EXPORT int sum(int a, int b) {
    return a + b;
}

FFI_PLUGIN_EXPORT int sum_long_running(int a, int b) {
#ifdef _WIN32
    Sleep(5000);
#else
    usleep(5000 * 1000);
#endif
    return a + b;
}

FFI_PLUGIN_EXPORT bool list_printers(char** printer_list, int* count, uint32_t* printer_states) {
#ifdef _WIN32
    DWORD needed, returned;
    EnumPrintersA(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, NULL, 2, NULL, 0, &needed, &returned);
    BYTE* buffer = (BYTE*)malloc(needed);
    if (!buffer) return false;

    if (EnumPrintersA(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, NULL, 2, buffer, needed, &needed, &returned)) {
        *count = returned;
        *printer_list = (char*)malloc(returned * 256);
        PRINTER_INFO_2A* printers = (PRINTER_INFO_2A*)buffer;
        for (DWORD i = 0; i < returned; i++) {
            strcpy(*printer_list + (i * 256), printers[i].pPrinterName);
            printer_states[i] = printers[i].Status; // Windows printer status (e.g., PRINTER_STATUS_OFFLINE = 0x80)
        }
        free(buffer);
        return true;
    }
    free(buffer);
    return false;
#else
    cups_dest_t* dests = NULL;
    int num_dests = cupsGetDests(&dests); // Use default CUPS connection
    if (num_dests <= 0) {
        return false;
    }

    *count = num_dests;
    *printer_list = (char*)malloc(num_dests * 256);
    for (int i = 0; i < num_dests; i++) {
        strcpy(*printer_list + (i * 256), dests[i].name);
        const char* state = cupsGetOption("printer-state", dests[i].num_options, dests[i].options);
        printer_states[i] = state ? atoi(state) : 3; // Default to IPP_PRINTER_IDLE (3) if not found
    }
    cupsFreeDests(num_dests, dests);
    return true;
#endif
}

FFI_PLUGIN_EXPORT bool raw_data_to_printer(const char* printer_name, const uint8_t* data, int length, const char* doc_name) {
#ifdef _WIN32
    HANDLE hPrinter;
    DOC_INFO_1A docInfo;
    DWORD written;

    if (!OpenPrinterA((LPSTR)printer_name, &hPrinter, NULL)) return false;

    docInfo.pDocName = (LPSTR)doc_name;
    docInfo.pOutputFile = NULL;
    docInfo.pDatatype = "RAW";

    if (StartDocPrinterA(hPrinter, 1, (LPBYTE)&docInfo) == 0) {
        ClosePrinter(hPrinter);
        return false;
    }

    if (!StartPagePrinter(hPrinter)) {
        EndDocPrinter(hPrinter);
        ClosePrinter(hPrinter);
        return false;
    }

    bool result = WritePrinter(hPrinter, (LPVOID)data, length, &written);
    EndPagePrinter(hPrinter);
    EndDocPrinter(hPrinter);
    ClosePrinter(hPrinter);
    return result && written == length;
#else
    char temp_file[] = "/tmp/printing_ffi_XXXXXX";
    int fd = mkstemp(temp_file);
    if (fd == -1) return false;

    FILE* fp = fdopen(fd, "wb");
    if (!fp) {
        close(fd);
        return false;
    }

    size_t written = fwrite(data, 1, length, fp);
    fclose(fp);

    if (written != length) {
        unlink(temp_file);
        return false;
    }

    int job_id = cupsPrintFile(printer_name, temp_file, doc_name, 0, NULL);
    unlink(temp_file);
    return job_id > 0;
#endif
}

FFI_PLUGIN_EXPORT bool list_print_jobs(const char* printer_name, uint32_t* job_ids, char** job_titles, uint32_t* job_statuses, int* count) {
#ifdef _WIN32
    HANDLE hPrinter;
    DWORD needed, returned;

    if (!OpenPrinterA((LPSTR)printer_name, &hPrinter, NULL)) return false;

    EnumJobsA(hPrinter, 0, 0xFFFFFFFF, 2, NULL, 0, &needed, &returned);
    BYTE* buffer = (BYTE*)malloc(needed);
    if (!buffer) {
        ClosePrinter(hPrinter);
        return false;
    }

    if (EnumJobsA(hPrinter, 0, 0xFFFFFFFF, 2, buffer, needed, &needed, &returned)) {
        *count = returned;
        *job_titles = (char*)malloc(returned * 256);
        JOB_INFO_2A* jobs = (JOB_INFO_2A*)buffer;
        for (DWORD i = 0; i < returned; i++) {
            job_ids[i] = jobs[i].JobId;
            strcpy(*job_titles + (i * 256), jobs[i].pDocument ? jobs[i].pDocument : "Unknown");
            job_statuses[i] = jobs[i].Status;
        }
        free(buffer);
        ClosePrinter(hPrinter);
        return true;
    }
    free(buffer);
    ClosePrinter(hPrinter);
    return false;
#else
    cups_job_t* jobs;
    *count = cupsGetJobs(&jobs, printer_name, 1, CUPS_WHICHJOBS_ACTIVE);
    if (*count <= 0) return false;

    *job_titles = (char*)malloc(*count * 256);
    for (int i = 0; i < *count; i++) {
        job_ids[i] = jobs[i].id;
        strcpy(*job_titles + (i * 256), jobs[i].title ? jobs[i].title : "Unknown");
        job_statuses[i] = jobs[i].state;
    }
    cupsFreeJobs(*count, jobs);
    return true;
#endif
}

FFI_PLUGIN_EXPORT bool pause_print_job(const char* printer_name, uint32_t job_id) {
#ifdef _WIN32
    HANDLE hPrinter;
    if (!OpenPrinterA((LPSTR)printer_name, &hPrinter, NULL)) return false;
    bool result = SetJobA(hPrinter, job_id, 0, NULL, JOB_CONTROL_PAUSE);
    ClosePrinter(hPrinter);
    return result;
#else
    return cupsCancelJob2(CUPS_HTTP_DEFAULT, printer_name, job_id, IPP_HOLD_JOB) == 1;
#endif
}

FFI_PLUGIN_EXPORT bool resume_print_job(const char* printer_name, uint32_t job_id) {
#ifdef _WIN32
    HANDLE hPrinter;
    if (!OpenPrinterA((LPSTR)printer_name, &hPrinter, NULL)) return false;
    bool result = SetJobA(hPrinter, job_id, 0, NULL, JOB_CONTROL_RESUME);
    ClosePrinter(hPrinter);
    return result;
#else
    return cupsCancelJob2(CUPS_HTTP_DEFAULT, printer_name, job_id, IPP_RELEASE_JOB) == 1;
#endif
}

FFI_PLUGIN_EXPORT bool cancel_print_job(const char* printer_name, uint32_t job_id) {
#ifdef _WIN32
    HANDLE hPrinter;
    if (!OpenPrinterA((LPSTR)printer_name, &hPrinter, NULL)) return false;
    bool result = SetJobA(hPrinter, job_id, 0, NULL, JOB_CONTROL_CANCEL);
    ClosePrinter(hPrinter);
    return result;
#else
    return cupsCancelJob(printer_name, job_id) == 1;
#endif
}