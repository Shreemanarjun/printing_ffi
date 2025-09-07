#include "printing_ffi.h"
#include <string.h>

#ifdef _WIN32
#include <winspool.h>
#define strdup _strdup
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

FFI_PLUGIN_EXPORT PrinterList* get_printers(void) {
    PrinterList* list = (PrinterList*)malloc(sizeof(PrinterList));
    if (!list) return NULL;
    list->count = 0;
    list->printers = NULL;

#ifdef _WIN32
    DWORD needed, returned;
    EnumPrintersA(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, NULL, 2, NULL, 0, &needed, &returned);
    if (needed == 0) {
        return list; // Return empty list
    }
    BYTE* buffer = (BYTE*)malloc(needed);
    if (!buffer) {
        free(list);
        return NULL;
    }

    if (EnumPrintersA(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, NULL, 2, buffer, needed, &needed, &returned)) {
        list->count = returned;
        list->printers = (PrinterInfo*)malloc(returned * sizeof(PrinterInfo));
        if (!list->printers) {
            free(buffer);
            free(list);
            return NULL;
        }
        PRINTER_INFO_2A* printers = (PRINTER_INFO_2A*)buffer;
        for (DWORD i = 0; i < returned; i++) {
            list->printers[i].name = strdup(printers[i].pPrinterName ? printers[i].pPrinterName : "");
            list->printers[i].state = printers[i].Status;
            list->printers[i].url = strdup(printers[i].pPrinterName ? printers[i].pPrinterName : "");
            list->printers[i].model = strdup(printers[i].pDriverName ? printers[i].pDriverName : "");
            list->printers[i].location = strdup(printers[i].pLocation ? printers[i].pLocation : "");
            list->printers[i].comment = strdup(printers[i].pComment ? printers[i].pComment : "");
            list->printers[i].is_default = (printers[i].Attributes & PRINTER_ATTRIBUTE_DEFAULT) != 0;
            list->printers[i].is_available = (printers[i].Status & PRINTER_STATUS_OFFLINE) == 0;
        }
    }
    free(buffer);
    return list;
#else // macOS
    cups_dest_t* dests = NULL;
    int num_dests = cupsGetDests(&dests);
    if (num_dests <= 0) {
        cupsFreeDests(num_dests, dests);
        return list; // Return empty list
    }

    list->count = num_dests;
    list->printers = (PrinterInfo*)malloc(num_dests * sizeof(PrinterInfo));
    if (!list->printers) {
        cupsFreeDests(num_dests, dests);
        free(list);
        return NULL;
    }

    for (int i = 0; i < num_dests; i++) {
        list->printers[i].name = strdup(dests[i].name);
        list->printers[i].is_default = dests[i].is_default;

        const char* state_str = cupsGetOption("printer-state", dests[i].num_options, dests[i].options);
        list->printers[i].state = state_str ? atoi(state_str) : 3; // Default to IPP_PRINTER_IDLE (3)
        list->printers[i].is_available = list->printers[i].state != 5; // 5 is IPP_PRINTER_STOPPED

        const char* uri_str = cupsGetOption("device-uri", dests[i].num_options, dests[i].options);
        list->printers[i].url = strdup(uri_str ? uri_str : "");

        const char* model_str = cupsGetOption("printer-make-and-model", dests[i].num_options, dests[i].options);
        list->printers[i].model = strdup(model_str ? model_str : "");

        const char* location_str = cupsGetOption("printer-location", dests[i].num_options, dests[i].options);
        list->printers[i].location = strdup(location_str ? location_str : "");

        const char* comment_str = cupsGetOption("printer-info", dests[i].num_options, dests[i].options);
        list->printers[i].comment = strdup(comment_str ? comment_str : "");
    }
    cupsFreeDests(num_dests, dests);
    return list;
#endif
}

FFI_PLUGIN_EXPORT void free_printer_list(PrinterList* printer_list) {
    if (!printer_list) return;
    if (printer_list->printers) {
        for (int i = 0; i < printer_list->count; i++) {
            free(printer_list->printers[i].name);
            free(printer_list->printers[i].url);
            free(printer_list->printers[i].model);
            free(printer_list->printers[i].location);
            free(printer_list->printers[i].comment);
        }
        free(printer_list->printers);
    }
    free(printer_list);
}

FFI_PLUGIN_EXPORT PrinterInfo* get_default_printer(void) {
#ifdef _WIN32
    DWORD len = 0;
    GetDefaultPrinterA(NULL, &len);
    if (len == 0) {
        return NULL; // No default printer or an error occurred
    }

    char* default_printer_name = (char*)malloc(len);
    if (!default_printer_name) return NULL;

    if (!GetDefaultPrinterA(default_printer_name, &len)) {
        free(default_printer_name);
        return NULL;
    }

    HANDLE hPrinter;
    if (!OpenPrinterA(default_printer_name, &hPrinter, NULL)) {
        free(default_printer_name);
        return NULL;
    }
    free(default_printer_name);

    DWORD needed = 0;
    GetPrinterA(hPrinter, 2, NULL, 0, &needed);
    if (needed == 0) {
        ClosePrinter(hPrinter);
        return NULL;
    }

    PRINTER_INFO_2A* pinfo2 = (PRINTER_INFO_2A*)malloc(needed);
    if (!pinfo2) {
        ClosePrinter(hPrinter);
        return NULL;
    }

    if (!GetPrinterA(hPrinter, 2, (LPBYTE)pinfo2, needed, &needed)) {
        free(pinfo2);
        ClosePrinter(hPrinter);
        return NULL;
    }
    ClosePrinter(hPrinter);

    PrinterInfo* printer_info = (PrinterInfo*)malloc(sizeof(PrinterInfo));
    if (!printer_info) {
        free(pinfo2);
        return NULL;
    }

    printer_info->name = strdup(pinfo2->pPrinterName ? pinfo2->pPrinterName : "");
    printer_info->state = pinfo2->Status;
    printer_info->url = strdup(pinfo2->pPrinterName ? pinfo2->pPrinterName : "");
    printer_info->model = strdup(pinfo2->pDriverName ? pinfo2->pDriverName : "");
    printer_info->location = strdup(pinfo2->pLocation ? pinfo2->pLocation : "");
    printer_info->comment = strdup(pinfo2->pComment ? pinfo2->pComment : "");
    printer_info->is_default = (pinfo2->Attributes & PRINTER_ATTRIBUTE_DEFAULT) != 0;
    printer_info->is_available = (pinfo2->Status & PRINTER_STATUS_OFFLINE) == 0;

    free(pinfo2);
    return printer_info;
#else // macOS
    const char* default_printer_name = cupsGetDefault();
    if (!default_printer_name) return NULL;

    cups_dest_t* dests = NULL;
    int num_dests = cupsGetDests(&dests);
    cups_dest_t* default_dest = cupsGetDest(default_printer_name, NULL, num_dests, dests);

    if (!default_dest) {
        cupsFreeDests(num_dests, dests);
        return NULL;
    }

    PrinterInfo* printer_info = (PrinterInfo*)malloc(sizeof(PrinterInfo));
    if (!printer_info) {
        cupsFreeDests(num_dests, dests);
        return NULL;
    }

    printer_info->name = strdup(default_dest->name);
    printer_info->is_default = default_dest->is_default;
    const char* state_str = cupsGetOption("printer-state", default_dest->num_options, default_dest->options);
    printer_info->state = state_str ? atoi(state_str) : 3;
    printer_info->is_available = printer_info->state != 5;
    const char* uri_str = cupsGetOption("device-uri", default_dest->num_options, default_dest->options);
    printer_info->url = strdup(uri_str ? uri_str : "");
    const char* model_str = cupsGetOption("printer-make-and-model", default_dest->num_options, default_dest->options);
    printer_info->model = strdup(model_str ? model_str : "");
    const char* location_str = cupsGetOption("printer-location", default_dest->num_options, default_dest->options);
    printer_info->location = strdup(location_str ? location_str : "");
    const char* comment_str = cupsGetOption("printer-info", default_dest->num_options, default_dest->options);
    printer_info->comment = strdup(comment_str ? comment_str : "");

    cupsFreeDests(num_dests, dests);
    return printer_info;
#endif
}

FFI_PLUGIN_EXPORT void free_printer_info(PrinterInfo* printer_info) {
    if (!printer_info) return;
    free(printer_info->name);
    free(printer_info->url);
    free(printer_info->model);
    free(printer_info->location);
    free(printer_info->comment);
    free(printer_info);
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

FFI_PLUGIN_EXPORT JobList* get_print_jobs(const char* printer_name) {
    JobList* list = (JobList*)malloc(sizeof(JobList));
    if (!list) return NULL;
    list->count = 0;
    list->jobs = NULL;

#ifdef _WIN32
    HANDLE hPrinter;
    DWORD needed, returned;

    if (!OpenPrinterA((LPSTR)printer_name, &hPrinter, NULL)) {
        free(list);
        return NULL;
    }

    EnumJobsA(hPrinter, 0, 0xFFFFFFFF, 2, NULL, 0, &needed, &returned);
    if (needed == 0) {
        ClosePrinter(hPrinter);
        return list;
    }
    BYTE* buffer = (BYTE*)malloc(needed);
    if (!buffer) {
        ClosePrinter(hPrinter);
        free(list);
        return NULL;
    }

    if (EnumJobsA(hPrinter, 0, 0xFFFFFFFF, 2, buffer, needed, &needed, &returned)) {
        list->count = returned;
        list->jobs = (JobInfo*)malloc(returned * sizeof(JobInfo));
        if (!list->jobs) {
            free(buffer);
            ClosePrinter(hPrinter);
            free(list);
            return NULL;
        }
        JOB_INFO_2A* jobs = (JOB_INFO_2A*)buffer;
        for (DWORD i = 0; i < returned; i++) {
            list->jobs[i].id = jobs[i].JobId;
            list->jobs[i].title = strdup(jobs[i].pDocument ? jobs[i].pDocument : "Unknown");
            list->jobs[i].status = jobs[i].Status;
        }
    }
    free(buffer);
    ClosePrinter(hPrinter);
    return list;
#else // macOS
    cups_job_t* jobs;
    int num_jobs = cupsGetJobs(&jobs, printer_name, 1, CUPS_WHICHJOBS_ACTIVE);
    if (num_jobs <= 0) {
        cupsFreeJobs(num_jobs, jobs);
        return list;
    }

    list->count = num_jobs;
    list->jobs = (JobInfo*)malloc(num_jobs * sizeof(JobInfo));
    if (!list->jobs) {
        cupsFreeJobs(num_jobs, jobs);
        free(list);
        return NULL;
    }

    for (int i = 0; i < num_jobs; i++) {
        list->jobs[i].id = jobs[i].id;
        list->jobs[i].title = strdup(jobs[i].title ? jobs[i].title : "Unknown");
        list->jobs[i].status = jobs[i].state;
    }
    cupsFreeJobs(num_jobs, jobs);
    return list;
#endif
}

FFI_PLUGIN_EXPORT void free_job_list(JobList* job_list) {
    if (!job_list) return;
    if (job_list->jobs) {
        for (int i = 0; i < job_list->count; i++) {
            free(job_list->jobs[i].title);
        }
        free(job_list->jobs);
    }
    free(job_list);
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