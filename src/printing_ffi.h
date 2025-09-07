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

FFI_PLUGIN_EXPORT int sum(int a, int b);
FFI_PLUGIN_EXPORT int sum_long_running(int a, int b);
FFI_PLUGIN_EXPORT bool list_printers(char** printer_list, int* count, uint32_t* printer_states);
FFI_PLUGIN_EXPORT bool raw_data_to_printer(const char* printer_name, const uint8_t* data, int length, const char* doc_name);
FFI_PLUGIN_EXPORT bool list_print_jobs(const char* printer_name, uint32_t* job_ids, char** job_titles, uint32_t* job_statuses, int* count);
FFI_PLUGIN_EXPORT bool pause_print_job(const char* printer_name, uint32_t job_id);
FFI_PLUGIN_EXPORT bool resume_print_job(const char* printer_name, uint32_t job_id);
FFI_PLUGIN_EXPORT bool cancel_print_job(const char* printer_name, uint32_t job_id);

#endif