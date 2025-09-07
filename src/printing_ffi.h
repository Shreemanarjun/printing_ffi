#ifndef PRINTING_FFI_H
#define PRINTING_FFI_H

#include <stdint.h>
#include <stdbool.h>

#if _WIN32
#include <windows.h>
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#include <pthread.h>
#include <unistd.h>
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

// Struct for returning printer information
typedef struct {
    char* name;
    uint32_t state;
    char* url;
    char* model;
    char* location;
    char* comment;
    bool is_default;
    bool is_available;
} PrinterInfo;

typedef struct {
    int count;
    PrinterInfo* printers;
} PrinterList;

// Struct for returning print job information
typedef struct {
    uint32_t id;
    char* title;
    uint32_t status;
} JobInfo;

typedef struct {
    int count;
    JobInfo* jobs;
} JobList;

FFI_PLUGIN_EXPORT int sum(int a, int b);
FFI_PLUGIN_EXPORT int sum_long_running(int a, int b);
FFI_PLUGIN_EXPORT PrinterList* get_printers(void);
FFI_PLUGIN_EXPORT void free_printer_list(PrinterList* printer_list);
FFI_PLUGIN_EXPORT bool raw_data_to_printer(const char* printer_name, const uint8_t* data, int length, const char* doc_name);
FFI_PLUGIN_EXPORT JobList* get_print_jobs(const char* printer_name);
FFI_PLUGIN_EXPORT void free_job_list(JobList* job_list);
FFI_PLUGIN_EXPORT bool pause_print_job(const char* printer_name, uint32_t job_id);
FFI_PLUGIN_EXPORT bool resume_print_job(const char* printer_name, uint32_t job_id);
FFI_PLUGIN_EXPORT bool cancel_print_job(const char* printer_name, uint32_t job_id);

#endif