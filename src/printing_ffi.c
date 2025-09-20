#include "printing_ffi.h"
#include <string.h>

#ifdef _WIN32
#include <winspool.h>
#include <stdio.h>
#include <shellapi.h>
#include <wingdi.h>
#define strdup _strdup
#else
#include <cups/cups.h>
#include <cups/ppd.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <unistd.h>
#endif
#include <ctype.h>
#include <stdarg.h>

#ifdef _WIN32
// Include the main Pdfium header. This is located by CMake.
#include "fpdfview.h"
#include "fpdf_edit.h"

// --- PDFium Dynamic Loading ---
// Define function pointer types for all used PDFium functions.
typedef void (*FPDF_InitLibraryWithConfig_t)(const FPDF_LIBRARY_CONFIG *config);
typedef FPDF_DOCUMENT (*FPDF_LoadDocument_t)(FPDF_STRING file_path, FPDF_BYTESTRING password);
typedef unsigned long (*FPDF_GetLastError_t)(void);
typedef void (*FPDF_CloseDocument_t)(FPDF_DOCUMENT document);
typedef int (*FPDF_GetPageCount_t)(FPDF_DOCUMENT document);
typedef FPDF_PAGE (*FPDF_LoadPage_t)(FPDF_DOCUMENT document, int page_index);
typedef float (*FPDF_GetPageWidthF_t)(FPDF_PAGE page);
typedef float (*FPDF_GetPageHeightF_t)(FPDF_PAGE page);
typedef int (*FPDFPage_GetRotation_t)(FPDF_PAGE page);
typedef void (*FPDF_ClosePage_t)(FPDF_PAGE page);
typedef void (*FPDF_DestroyLibrary_t)(void);
// Type for direct rendering to a device context.
typedef void (*FPDF_RenderPage_t)(HDC dc, FPDF_PAGE page, int start_x, int start_y, int size_x, int size_y, int rotate, int flags);

// Struct to hold all our dynamically loaded PDFium function pointers.
static struct
{
    HMODULE module;
    FPDF_InitLibraryWithConfig_t FPDF_InitLibraryWithConfig;
    FPDF_LoadDocument_t FPDF_LoadDocument;
    FPDF_GetLastError_t FPDF_GetLastError;
    FPDF_CloseDocument_t FPDF_CloseDocument;
    FPDF_GetPageCount_t FPDF_GetPageCount;
    FPDF_LoadPage_t FPDF_LoadPage;
    FPDF_GetPageWidthF_t FPDF_GetPageWidthF;
    FPDF_GetPageHeightF_t FPDF_GetPageHeightF;
    FPDFPage_GetRotation_t FPDFPage_GetRotation;
    FPDF_ClosePage_t FPDF_ClosePage;
    FPDF_RenderPage_t FPDF_RenderPage;
    FPDF_DestroyLibrary_t FPDF_DestroyLibrary;
} g_pdfium = {0};

// Thread-safe initialization control for PDFium
static INIT_ONCE g_pdfium_init_once = INIT_ONCE_STATIC_INIT;
static bool g_pdfium_init_succeeded = false;
#endif

#define LOG(...)

// --- Last Error Handling ---

// Use thread-local storage for the last error message to ensure thread safety.
#ifdef _WIN32
__declspec(thread) static char *g_last_error_message = NULL;
#else // macOS, Linux
static __thread char *g_last_error_message = NULL;
#endif

// Internal helper to set the last error message for the current thread.
static void set_last_error(const char *format, ...)
{
    // Free the previous error message if it exists
    if (g_last_error_message)
    {
        free(g_last_error_message);
        g_last_error_message = NULL;
    }

    va_list args;
    va_start(args, format);

    // Determine the required buffer size
    va_list args_copy;
    va_copy(args_copy, args);
    int size = vsnprintf(NULL, 0, format, args_copy);
    va_end(args_copy);

    if (size >= 0)
    {
        g_last_error_message = (char *)malloc(size + 1);
        if (g_last_error_message)
            vsnprintf(g_last_error_message, size + 1, format, args);
    }
    va_end(args);
}

#ifdef _WIN32
// This is the function that will be called only once to initialize PDFium.
static BOOL CALLBACK InitPdfiumCallback(PINIT_ONCE InitOnce, PVOID Parameter, PVOID *Context)
{
    // Attempt to load the isolated DLL first, then fall back to the standard name.
    const char *pdfium_names[] = {"printing_ffi_pdfium.dll", "pdfium.dll", NULL};
    for (int i = 0; pdfium_names[i] != NULL; ++i)
    {
        g_pdfium.module = LoadLibraryA(pdfium_names[i]);
        if (g_pdfium.module)
        {
            LOG("Successfully loaded PDFium library as '%s'", pdfium_names[i]);
            break;
        }
    }

    if (!g_pdfium.module)
    {
        set_last_error("Failed to load pdfium.dll. Make sure it is present alongside the application executable.");
        LOG("Failed to load any of the PDFium DLL candidates.");
        g_pdfium_init_succeeded = false;
        return TRUE; // The one-time initialization itself completed, even if the logic failed.
    }

#define LOAD_PDFIUM_FUNC(name)                                                \
    g_pdfium.name = (name##_t)GetProcAddress(g_pdfium.module, #name);         \
    if (!g_pdfium.name)                                                       \
    {                                                                         \
        set_last_error("Failed to find function '%s' in PDFium DLL.", #name); \
        LOG("Failed to find function '%s' in PDFium DLL.", #name);            \
        FreeLibrary(g_pdfium.module);                                         \
        g_pdfium.module = NULL;                                               \
        g_pdfium_init_succeeded = false;                                      \
        return TRUE;                                                          \
    }

    // Load all required functions.
    LOAD_PDFIUM_FUNC(FPDF_InitLibraryWithConfig);
    LOAD_PDFIUM_FUNC(FPDF_LoadDocument);
    LOAD_PDFIUM_FUNC(FPDF_GetLastError);
    LOAD_PDFIUM_FUNC(FPDF_CloseDocument);
    LOAD_PDFIUM_FUNC(FPDF_GetPageCount);
    LOAD_PDFIUM_FUNC(FPDF_LoadPage);
    LOAD_PDFIUM_FUNC(FPDF_GetPageWidthF);
    LOAD_PDFIUM_FUNC(FPDF_GetPageHeightF);
    LOAD_PDFIUM_FUNC(FPDFPage_GetRotation);
    LOAD_PDFIUM_FUNC(FPDF_ClosePage);
    LOAD_PDFIUM_FUNC(FPDF_RenderPage);
    LOAD_PDFIUM_FUNC(FPDF_DestroyLibrary);

#undef LOAD_PDFIUM_FUNC

    // Now initialize the library
    FPDF_LIBRARY_CONFIG config;
    memset(&config, 0, sizeof(config));
    config.version = 2;
    g_pdfium.FPDF_InitLibraryWithConfig(&config);
    LOG("PDFium library initialized successfully.");
    g_pdfium_init_succeeded = true;
    return TRUE;
}

// Loads and initializes the PDFium DLL. This function is thread-safe and idempotent.
// Returns true on success, false on failure.
static bool ensure_pdfium_initialized()
{
    if (!InitOnceExecuteOnce(&g_pdfium_init_once, InitPdfiumCallback, NULL, NULL))
    {
        // This means the InitOnceExecuteOnce call itself failed, which is a system-level error.
        set_last_error("Failed to execute one-time PDFium initialization (InitOnceExecuteOnce failed).");
        return false;
    }
    // g_pdfium_init_succeeded is set inside the callback.
    if (!g_pdfium_init_succeeded)
    {
        // If the error message is not already set by the callback, set a generic one.
        if (g_last_error_message == NULL || strlen(g_last_error_message) == 0)
        {
            set_last_error("PDFium initialization failed for an unknown reason.");
        }
    }
    return g_pdfium_init_succeeded;
}

#endif

#ifdef _WIN32
// Helper to convert UTF-8 char* to wchar_t*
// The caller is responsible for freeing the returned string.
static wchar_t *to_utf16(const char *utf8_str)
{
    if (!utf8_str)
        return NULL;
    int len = MultiByteToWideChar(CP_UTF8, 0, utf8_str, -1, NULL, 0);
    if (len == 0)
    {
        LOG("MultiByteToWideChar to get len failed with error %lu", GetLastError());
        return NULL;
    }
    wchar_t *utf16_str = (wchar_t *)malloc(len * sizeof(wchar_t));
    if (!utf16_str)
        return NULL;
    if (MultiByteToWideChar(CP_UTF8, 0, utf8_str, -1, utf16_str, len) == 0)
    {
        LOG("MultiByteToWideChar to convert failed with error %lu", GetLastError());
        free(utf16_str);
        return NULL;
    }
    return utf16_str;
}

// Helper to convert wchar_t* to UTF-8 char*
// The caller is responsible for freeing the returned string.
static char *to_utf8(const wchar_t *utf16_str)
{
    if (!utf16_str)
        return strdup("");
    int len = WideCharToMultiByte(CP_UTF8, 0, utf16_str, -1, NULL, 0, NULL, NULL);
    if (len == 0)
        return strdup("");
    char *utf8_str = (char *)malloc(len);
    if (!utf8_str)
        return strdup(""); // Should not happen
    WideCharToMultiByte(CP_UTF8, 0, utf16_str, -1, utf8_str, len, NULL, NULL);
    return utf8_str;
}

// Helper function to parse page ranges.
// `range_str`: e.g., "1-3,5,8-10"
// `page_flags`: A pre-allocated array of bools of size `total_pages`.
// `total_pages`: Total number of pages in the document.
// Returns true on success, false on parsing error.
static bool parse_page_range(const char *range_str, bool *page_flags, int total_pages)
{
    // If range is empty or null, mark all pages for printing.
    if (!range_str || strlen(range_str) == 0)
    {
        for (int i = 0; i < total_pages; i++)
            page_flags[i] = true;
        return true;
    }

    // Otherwise, first mark all as false.
    for (int i = 0; i < total_pages; i++)
        page_flags[i] = false;

    char *str = strdup(range_str);
    if (!str)
        return false;
    char *to_free = str;

    // Use strtok for non-Windows, strtok_s for Windows
    char *token;
    char *context = NULL;

#ifdef _WIN32
    token = strtok_s(str, ",", &context);
#else
    token = strtok(str, ",");
#endif

    while (token)
    {
        // Trim whitespace
        while (isspace((unsigned char)*token))
            token++;
        char *end = token + strlen(token) - 1;
        while (end > token && isspace((unsigned char)*end))
            *end-- = '\0';

        if (strlen(token) == 0)
            goto next_token;

        // Make a copy of the token for parsing, so we can use the original for error messages.
        char *token_copy = strdup(token);
        if (!token_copy)
        {
            free(to_free);
            return false;
        }

        int start_page, end_page;
        char *dash = strchr(token_copy, '-');

        if (dash)
        { // It's a range like "3-5"
            *dash = '\0';
            start_page = atoi(token_copy);
            end_page = atoi(dash + 1);
        }
        else
        { // It's a single page like "7"
            start_page = end_page = atoi(token_copy);
        }

        free(token_copy); // Clean up the copy

        // Validate input
        // The page count must be positive.
        // The start page must be at least 1.
        // The end page must not be less than the start page.
        // The end page must not exceed the total number of pages in the document.
        if (total_pages <= 0 || start_page < 1 || end_page < start_page || end_page > total_pages)
        {
            // Use the original, unmodified token for the error message.
            set_last_error("Page range '%s' is invalid for a document with %d pages.", token, total_pages);
            LOG("Invalid page range value: '%s' for a document with %d pages.", token, total_pages);
            free(to_free);
            return false; // Invalid range
        }

        // Mark pages to be printed (adjusting for 0-based index)
        for (int i = start_page; i <= end_page; i++)
        {
            page_flags[i - 1] = true;
        }

    next_token:
#ifdef _WIN32
        token = strtok_s(NULL, ",", &context);
#else
        token = strtok(NULL, ",");
#endif
    }
    free(to_free);
    return true;
}

// Helper function to parse Windows-specific print options from the generic key-value array.
static void parse_windows_options(int num_options, const char **option_keys, const char **option_values,
                                  int *paper_size_id, int *paper_source_id, int *orientation,
                                  int *color_mode, int *print_quality, int *media_type_id, double *custom_scale,
                                  bool *collate, int *duplex_mode)
{
    // Set default values
    *paper_size_id = 0;
    *paper_source_id = 0;
    *orientation = 0;
    *color_mode = 0;
    *print_quality = 0;
    *media_type_id = 0;
    *custom_scale = 1.0; // Default to 100%
    *collate = true;     // Default to collated (complete copies printed together)
    *duplex_mode = 0;    // Default to single-sided (DMDUP_SIMPLEX)

    for (int i = 0; i < num_options; i++)
    {
        if (strcmp(option_keys[i], "paper-size-id") == 0)
        {
            *paper_size_id = atoi(option_values[i]);
        }
        else if (strcmp(option_keys[i], "paper-source-id") == 0)
        {
            *paper_source_id = atoi(option_values[i]);
        }
        else if (strcmp(option_keys[i], "orientation") == 0)
        {
            if (strcmp(option_values[i], "landscape") == 0)
                *orientation = 2; // DMORIENT_LANDSCAPE
            else
                *orientation = 1; // DMORIENT_PORTRAIT
        }
        else if (strcmp(option_keys[i], "color-mode") == 0)
        {
            if (strcmp(option_values[i], "monochrome") == 0)
            {
                *color_mode = 1; // DMCOLOR_MONOCHROME
            }
            else
            {
                *color_mode = 2; // DMCOLOR_COLOR
            }
            // For color/monochrome, also ensure print quality is set to trigger driver update.
            // If it's not already being set, use a neutral value.
            if (*print_quality == 0)
            {
                *print_quality = -3; // DMRES_MEDIUM
            }
        }
        else if (strcmp(option_keys[i], "print-quality") == 0)
        {
            if (strcmp(option_values[i], "draft") == 0)
                *print_quality = -1; // DMRES_DRAFT
            else if (strcmp(option_values[i], "low") == 0)
                *print_quality = -2; // DMRES_LOW
            else if (strcmp(option_values[i], "high") == 0)
                *print_quality = -4; // DMRES_HIGH
            else
                *print_quality = -3; // DMRES_MEDIUM / normal
        }
        else if (strcmp(option_keys[i], "media-type-id") == 0)
        {
            *media_type_id = atoi(option_values[i]);
        }
        else if (strcmp(option_keys[i], "custom-scale-factor") == 0)
        {
            *custom_scale = atof(option_values[i]);
        }
        else if (strcmp(option_keys[i], "collate") == 0)
        {
            // Parse collate option: true = collated (complete copies together), false = non-collated (all copies of each page together)
            *collate = (strcmp(option_values[i], "true") == 0);
        }
        else if (strcmp(option_keys[i], "duplex") == 0)
        {
            // Parse duplex option: singleSided, duplexLongEdge, duplexShortEdge
            if (strcmp(option_values[i], "singleSided") == 0)
            {
                *duplex_mode = 1; // DMDUP_SIMPLEX
            }
            else if (strcmp(option_values[i], "duplexLongEdge") == 0)
            {
                *duplex_mode = 2; // DMDUP_VERTICAL (long edge)
            }
            else if (strcmp(option_values[i], "duplexShortEdge") == 0)
            {
                *duplex_mode = 3; // DMDUP_HORIZONTAL (short edge)
            }
        }
    }
}
#endif

#ifdef _WIN32
// Helper to get a modified DEVMODE struct for a printer.
// The caller is responsible for freeing the returned struct.
static DEVMODEW *get_modified_devmode(wchar_t *printer_name_w, int paper_size_id, int paper_source_id, int orientation, int color_mode, int print_quality, int media_type_id, int copies, bool collate, int duplex_mode)
{
    if (!printer_name_w)
        return NULL;
    LOG("get_modified_devmode: Creating DEVMODE for '%ls' with paper_id:%d, source_id:%d, orientation:%d, color:%d, quality:%d, media_id:%d, copies:%d, duplex:%d",
        printer_name_w, paper_size_id, paper_source_id, orientation, color_mode, print_quality, media_type_id, copies, duplex_mode);

    HANDLE hPrinter;
    if (!OpenPrinterW(printer_name_w, &hPrinter, NULL))
    {
        LOG("get_modified_devmode: OpenPrinterW failed with error %lu", GetLastError());
        return NULL;
    }

    DEVMODEW *pDevMode = NULL;
    LONG devModeSize = DocumentPropertiesW(NULL, hPrinter, printer_name_w, NULL, NULL, 0);
    if (devModeSize <= 0)
    {
        LOG("get_modified_devmode: DocumentPropertiesW (get size) failed with error %lu. Size was %ld.", GetLastError(), devModeSize);
        ClosePrinter(hPrinter);
        return NULL;
    }

    pDevMode = (DEVMODEW *)malloc(devModeSize);
    if (!pDevMode)
    {
        LOG("get_modified_devmode: Failed to allocate memory for DEVMODE.");
        ClosePrinter(hPrinter);
        return NULL;
    }

    // Get the default DEVMODE for the printer.
    if (DocumentPropertiesW(NULL, hPrinter, printer_name_w, pDevMode, NULL, DM_OUT_BUFFER) != IDOK)
    {
        LOG("get_modified_devmode: DocumentPropertiesW (get defaults) failed with error %lu", GetLastError());
        free(pDevMode);
        ClosePrinter(hPrinter);
        return NULL;
    }
    LOG("get_modified_devmode: Successfully retrieved default DEVMODE.");

    bool modified = false;
    // A value <= 0 for IDs/orientation means "use default".
    if (paper_size_id > 0)
    {
        LOG("get_modified_devmode: Setting dmPaperSize to %d.", paper_size_id);
        pDevMode->dmFields |= DM_PAPERSIZE;
        pDevMode->dmPaperSize = (short)paper_size_id;
        modified = true;
    }
    if (paper_source_id > 0)
    {
        LOG("get_modified_devmode: Setting dmDefaultSource to %d.", paper_source_id);
        pDevMode->dmFields |= DM_DEFAULTSOURCE;
        pDevMode->dmDefaultSource = (short)paper_source_id;
        modified = true;
    }
    if (orientation > 0)
    {
        LOG("get_modified_devmode: Setting dmOrientation to %d.", orientation);
        // If changing orientation, swap paper dimensions to give the driver a hint.
        // The driver should correct this if it's wrong, but some drivers need the help.
        if ((pDevMode->dmFields & DM_ORIENTATION) && pDevMode->dmOrientation != (short)orientation)
        {
            LOG("get_modified_devmode: Swapping paper width (%d) and length (%d) for orientation change.", pDevMode->dmPaperWidth, pDevMode->dmPaperLength);
            short temp = pDevMode->dmPaperWidth;
            pDevMode->dmPaperWidth = pDevMode->dmPaperLength;
            pDevMode->dmPaperLength = temp;
        }
        pDevMode->dmFields |= DM_ORIENTATION;
        pDevMode->dmOrientation = (short)orientation;
        pDevMode->dmFields |= DM_PAPERSIZE; // Ensure paper size is considered with orientation
        modified = true;
    }
    if (color_mode > 0)
    {
        LOG("get_modified_devmode: Setting dmColor to %d.", color_mode);
        pDevMode->dmFields |= DM_COLOR;
        pDevMode->dmColor = (short)color_mode;
        modified = true;
    }
    if (print_quality != 0)
    {
        LOG("get_modified_devmode: Setting dmPrintQuality to %d.", print_quality);
        pDevMode->dmFields |= DM_PRINTQUALITY;
        pDevMode->dmPrintQuality = (short)print_quality;
        modified = true;
    }
    if (media_type_id > 0)
    {
        LOG("get_modified_devmode: Setting dmMediaType to %d.", media_type_id);
        pDevMode->dmFields |= DM_MEDIATYPE;
        pDevMode->dmMediaType = (short)media_type_id;
        modified = true;
    }
    if (duplex_mode > 0)
    {
        LOG("get_modified_devmode: Setting dmDuplex to %d.", duplex_mode);
        pDevMode->dmFields |= DM_DUPLEX;
        pDevMode->dmDuplex = (short)duplex_mode;
        modified = true;
    }

    if (copies > 1)
    {
        LOG("get_modified_devmode: Setting dmCopies to %d.", copies);
        pDevMode->dmFields |= DM_COPIES;
        pDevMode->dmCopies = (short)copies;
        modified = true;
    }

    // Set collate mode
    LOG("get_modified_devmode: Setting dmCollate to %s.", collate ? "true" : "false");
    pDevMode->dmFields |= DM_COLLATE;
    pDevMode->dmCollate = collate ? DMCOLLATE_TRUE : DMCOLLATE_FALSE;
    modified = true;

    if (modified)
    {
        LOG("get_modified_devmode: DEVMODE was modified. Validating with driver...");
        // Validate and merge the changes. The driver may update the DEVMODE struct.
        LONG result = DocumentPropertiesW(NULL, hPrinter, printer_name_w, pDevMode, pDevMode, DM_IN_BUFFER | DM_OUT_BUFFER);
        if (result != IDOK)
        {
            LOG("get_modified_devmode: DocumentPropertiesW (merge) failed with result %ld and error %lu. The driver may have rejected the settings. Continuing anyway.", result, GetLastError());
        }
        else
        {
            LOG("get_modified_devmode: Driver accepted and merged DEVMODE changes.");
        }
    }
    else
    {
        LOG("get_modified_devmode: No modifications requested, using default DEVMODE.");
    }

    ClosePrinter(hPrinter);
    return pDevMode;
}
#endif

FFI_PLUGIN_EXPORT void shutdown_pdfium_library()
{
#ifdef _WIN32
    if (g_pdfium_init_succeeded && g_pdfium.module && g_pdfium.FPDF_DestroyLibrary)
    {
        g_pdfium.FPDF_DestroyLibrary();
        // We don't free the library handle, as the process is likely shutting down.
        // Re-initializing after shutdown is not a supported scenario.
        LOG("PDFium library shut down.");
    }
#endif
}

FFI_PLUGIN_EXPORT void init_pdfium_library()
{
#ifdef _WIN32
    // This function now just ensures initialization. It's safe to call multiple times
    // from any thread. The underlying implementation uses InitOnceExecuteOnce.
    if (ensure_pdfium_initialized())
    {
        LOG("PDFium library explicitly initialized or already initialized.");
    }

#endif
}

FFI_PLUGIN_EXPORT int sum(int a, int b)
{
    return a + b;
}

FFI_PLUGIN_EXPORT int sum_long_running(int a, int b)
{
#ifdef _WIN32
    Sleep(5000);
#else
    usleep(5000 * 1000);
#endif
    return a + b;
}

FFI_PLUGIN_EXPORT PrinterList *get_printers(void)
{
    LOG("get_printers called");
    PrinterList *list = (PrinterList *)malloc(sizeof(PrinterList));
    if (!list)
        return NULL;
    list->count = 0;
    list->printers = NULL;

#ifdef _WIN32
    DWORD needed, returned;
    EnumPrintersW(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, NULL, 2, NULL, 0, &needed, &returned);
    LOG("EnumPrintersW needed %lu bytes for printer list", needed);
    if (needed == 0)
    {
        return list; // Return empty list
    }
    BYTE *buffer = (BYTE *)malloc(needed);
    if (!buffer)
    {
        free(list);
        return NULL;
    }

    if (EnumPrintersW(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, NULL, 2, buffer, needed, &needed, &returned))
    {
        LOG("Found %lu printers on Windows", returned);
        list->count = (int)returned; // Cast to int for consistency
        list->printers = (PrinterInfo *)malloc(returned * sizeof(PrinterInfo));
        if (!list->printers)
        {
            free(buffer);
            free(list);
            return NULL;
        }
        PRINTER_INFO_2W *printers = (PRINTER_INFO_2W *)buffer;
        for (DWORD i = 0; i < returned; i++)
        {
            list->printers[i].name = to_utf8(printers[i].pPrinterName);
            list->printers[i].state = (int)printers[i].Status;         // Cast to int
            list->printers[i].url = to_utf8(printers[i].pPrinterName); // Use printer name as URL for Windows
            list->printers[i].model = to_utf8(printers[i].pDriverName);
            list->printers[i].location = to_utf8(printers[i].pLocation);
            list->printers[i].comment = to_utf8(printers[i].pComment);
            list->printers[i].is_default = (printers[i].Attributes & PRINTER_ATTRIBUTE_DEFAULT) != 0;
            list->printers[i].is_available = (printers[i].Status & PRINTER_STATUS_OFFLINE) == 0;
        }
    }
    else
    {
        LOG("EnumPrintersW failed with error %lu", GetLastError());
    }
    free(buffer);
    return list;
#else // macOS / Linux
    cups_dest_t *dests = NULL;
    LOG("Calling cupsGetDests to find printers");
    int num_dests = cupsGetDests(&dests);
    if (num_dests <= 0)
    {
        cupsFreeDests(num_dests, dests);
        return list; // Return empty list
    }

    LOG("Found %d printers on CUPS-based system", num_dests);
    list->count = num_dests;
    list->printers = (PrinterInfo *)malloc(num_dests * sizeof(PrinterInfo));
    if (!list->printers)
    {
        cupsFreeDests(num_dests, dests);
        free(list);
        return NULL;
    }

    for (int i = 0; i < num_dests; i++)
    {
        list->printers[i].name = strdup(dests[i].name ? dests[i].name : "");
        list->printers[i].is_default = dests[i].is_default;

        const char *state_str = cupsGetOption("printer-state", dests[i].num_options, dests[i].options);
        list->printers[i].state = state_str ? atoi(state_str) : 3;     // Default to IPP_PRINTER_IDLE (3)
        list->printers[i].is_available = list->printers[i].state != 5; // 5 is IPP_PRINTER_STOPPED

        const char *uri_str = cupsGetOption("device-uri", dests[i].num_options, dests[i].options);
        list->printers[i].url = strdup(uri_str ? uri_str : "");

        const char *model_str = cupsGetOption("printer-make-and-model", dests[i].num_options, dests[i].options);
        list->printers[i].model = strdup(model_str ? model_str : "");

        const char *location_str = cupsGetOption("printer-location", dests[i].num_options, dests[i].options);
        list->printers[i].location = strdup(location_str ? location_str : "");

        const char *comment_str = cupsGetOption("printer-info", dests[i].num_options, dests[i].options);
        list->printers[i].comment = strdup(comment_str ? comment_str : "");
    }
    cupsFreeDests(num_dests, dests);
    return list;
#endif
}

FFI_PLUGIN_EXPORT void free_printer_list(PrinterList *printer_list)
{
    if (!printer_list)
        return;
    if (printer_list->printers)
    {
        for (int i = 0; i < printer_list->count; i++)
        {
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

FFI_PLUGIN_EXPORT PrinterInfo *get_default_printer(void)
{
    LOG("get_default_printer called");
#ifdef _WIN32
    DWORD len = 0;
    GetDefaultPrinterW(NULL, &len);
    if (len == 0)
    {
        return NULL; // No default printer or an error occurred
    }

    wchar_t *default_printer_name_w = (wchar_t *)malloc(len * sizeof(wchar_t));
    if (!default_printer_name_w)
        return NULL;

    if (!GetDefaultPrinterW(default_printer_name_w, &len))
    {
        LOG("GetDefaultPrinterW failed with error %lu", GetLastError());
        free(default_printer_name_w);
        return NULL;
    }

    HANDLE hPrinter;
    if (!OpenPrinterW(default_printer_name_w, &hPrinter, NULL))
    {
        LOG("OpenPrinterW for default printer failed with error %lu", GetLastError());
        free(default_printer_name_w);
        return NULL;
    }

    DWORD needed = 0;
    GetPrinterW(hPrinter, 2, NULL, 0, &needed);
    if (needed == 0)
    {
        LOG("GetPrinterW (to get size) failed with error %lu", GetLastError());
        ClosePrinter(hPrinter);
        free(default_printer_name_w);
        return NULL;
    }

    PRINTER_INFO_2W *pinfo2 = (PRINTER_INFO_2W *)malloc(needed);
    if (!pinfo2)
    {
        ClosePrinter(hPrinter);
        free(default_printer_name_w);
        return NULL;
    }

    if (!GetPrinterW(hPrinter, 2, (LPBYTE)pinfo2, needed, &needed))
    {
        LOG("GetPrinterW (to get data) failed with error %lu", GetLastError());
        free(pinfo2);
        ClosePrinter(hPrinter);
        free(default_printer_name_w);
        return NULL;
    }
    ClosePrinter(hPrinter);
    free(default_printer_name_w); // We have the info in pinfo2 now

    PrinterInfo *printer_info = (PrinterInfo *)malloc(sizeof(PrinterInfo));
    if (!printer_info)
    {
        free(pinfo2);
        return NULL;
    }
    printer_info->name = to_utf8(pinfo2->pPrinterName);
    printer_info->state = (int)pinfo2->Status; // Cast to int
    printer_info->url = to_utf8(pinfo2->pPrinterName);
    printer_info->model = to_utf8(pinfo2->pDriverName);
    printer_info->location = to_utf8(pinfo2->pLocation);
    printer_info->comment = to_utf8(pinfo2->pComment);
    printer_info->is_default = (pinfo2->Attributes & PRINTER_ATTRIBUTE_DEFAULT) != 0;
    printer_info->is_available = (pinfo2->Status & PRINTER_STATUS_OFFLINE) == 0;

    free(pinfo2);
    return printer_info;
#else // macOS / Linux
    const char *default_printer_name = cupsGetDefault();
    if (!default_printer_name)
    {
        LOG("cupsGetDefault returned null, no default printer found.");
        return NULL;
    }
    LOG("CUPS default printer name: %s", default_printer_name);

    cups_dest_t *dests = NULL;
    int num_dests = cupsGetDests(&dests);
    cups_dest_t *default_dest = cupsGetDest(default_printer_name, NULL, num_dests, dests);

    if (!default_dest)
    {
        cupsFreeDests(num_dests, dests);
        return NULL;
    }

    PrinterInfo *printer_info = (PrinterInfo *)malloc(sizeof(PrinterInfo));
    if (!printer_info)
    {
        cupsFreeDests(num_dests, dests);
        return NULL;
    }

    printer_info->name = strdup(default_dest->name ? default_dest->name : "");
    printer_info->is_default = default_dest->is_default;
    const char *state_str = cupsGetOption("printer-state", default_dest->num_options, default_dest->options);
    printer_info->state = state_str ? atoi(state_str) : 3;
    printer_info->is_available = printer_info->state != 5;
    const char *uri_str = cupsGetOption("device-uri", default_dest->num_options, default_dest->options);
    printer_info->url = strdup(uri_str ? uri_str : "");
    const char *model_str = cupsGetOption("printer-make-and-model", default_dest->num_options, default_dest->options);
    printer_info->model = strdup(model_str ? model_str : "");
    const char *location_str = cupsGetOption("printer-location", default_dest->num_options, default_dest->options);
    printer_info->location = strdup(location_str ? location_str : "");
    const char *comment_str = cupsGetOption("printer-info", default_dest->num_options, default_dest->options);
    printer_info->comment = strdup(comment_str ? comment_str : "");

    cupsFreeDests(num_dests, dests);
    return printer_info;
#endif
}

FFI_PLUGIN_EXPORT void free_printer_info(PrinterInfo *printer_info)
{
    if (!printer_info)
        return;
    free(printer_info->name);
    free(printer_info->url);
    free(printer_info->model);
    free(printer_info->location);
    free(printer_info->comment);
    free(printer_info);
}

FFI_PLUGIN_EXPORT bool raw_data_to_printer(const char *printer_name, const uint8_t *data, int length, const char *doc_name, int num_options, const char **option_keys, const char **option_values)
{
    LOG("raw_data_to_printer called for printer: '%s', doc: '%s', length: %d", printer_name, doc_name, length);

    // Validate input parameters
    if (!printer_name || !data || length <= 0 || !doc_name)
    {
        LOG("Invalid input parameters");
        return false;
    }

#ifdef _WIN32
    int paper_size_id, paper_source_id, orientation, color_mode, print_quality, media_type_id, duplex_mode;
    double custom_scale; // Dummy for raw printing
    bool collate = true; // Default to collated (complete copies printed together)
    parse_windows_options(num_options, option_keys, option_values, &paper_size_id, &paper_source_id, &orientation, &color_mode, &print_quality, &media_type_id, &custom_scale, &collate, &duplex_mode);

    wchar_t *printer_name_w = to_utf16(printer_name);
    if (!printer_name_w)
        return false;

    HANDLE hPrinter;
    DOC_INFO_1W docInfo;
    DEVMODEW *pDevMode = get_modified_devmode(printer_name_w, paper_size_id, paper_source_id, orientation, color_mode, print_quality, media_type_id, 1, collate, duplex_mode);

    PRINTER_DEFAULTSW printerDefaults = {NULL, pDevMode, PRINTER_ACCESS_USE};
    printerDefaults.pDatatype = L"RAW";

    if (!OpenPrinterW(printer_name_w, &hPrinter, &printerDefaults))
    {
        LOG("OpenPrinterW failed with error %lu", GetLastError());
        free(printer_name_w);
        if (pDevMode)
            free(pDevMode);
        return false;
    }

    wchar_t *doc_name_w = to_utf16(doc_name);
    docInfo.pDocName = doc_name_w;
    docInfo.pOutputFile = NULL;
    docInfo.pDatatype = L"RAW";

    if (StartDocPrinterW(hPrinter, 1, (LPBYTE)&docInfo) == 0)
    {
        ClosePrinter(hPrinter);
        LOG("StartDocPrinterW failed with error %lu", GetLastError());
        if (doc_name_w)
            free(doc_name_w);
        free(printer_name_w);
        if (pDevMode)
            free(pDevMode);
        return false;
    }
    if (doc_name_w)
        free(doc_name_w);

    if (!StartPagePrinter(hPrinter))
    {
        EndDocPrinter(hPrinter);
        ClosePrinter(hPrinter);
        LOG("StartPagePrinter failed with error %lu", GetLastError());
        free(printer_name_w);
        if (pDevMode)
            free(pDevMode);
        return false;
    }

    // --- Chunked Write with Message Pump ---
    // This prevents the STA thread from blocking if a very large raw data file is sent.
    const DWORD CHUNK_SIZE = 65536; // 64 KB
    DWORD total_written = 0;
    DWORD bytes_to_write = (DWORD)length;
    bool write_success = true;

    while (total_written < bytes_to_write)
    {
        DWORD chunk_to_write = (bytes_to_write - total_written > CHUNK_SIZE) ? CHUNK_SIZE : (bytes_to_write - total_written);
        DWORD written_this_chunk = 0;

        if (!WritePrinter(hPrinter, (LPVOID)(data + total_written), chunk_to_write, &written_this_chunk))
        {
            LOG("WritePrinter failed during chunked write with error %lu", GetLastError());
            write_success = false;
            break;
        }

        total_written += written_this_chunk;

        // Pump messages to keep the STA thread responsive.
        MSG msg;
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE))
        {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }

    EndPagePrinter(hPrinter);
    EndDocPrinter(hPrinter);
    ClosePrinter(hPrinter);
    free(printer_name_w);
    if (pDevMode)
        free(pDevMode);

    bool success = write_success && (total_written == (DWORD)length);
    if (!success)
    {
        LOG("WritePrinter failed. Success: %d, Bytes written: %lu, Expected: %d", write_success, total_written, length);
    }
    return success;
#else // macOS / Linux
    // Use getenv("TMPDIR") to get the correct temporary directory,
    // especially important for sandboxed macOS apps where /tmp is not writable.
    const char *tmpdir = getenv("TMPDIR");
    if (!tmpdir)
    {
        tmpdir = "/tmp"; // Fallback for Linux or non-sandboxed environments
    }

    char temp_file[PATH_MAX];
    snprintf(temp_file, sizeof(temp_file), "%s/printing_ffi_XXXXXX", tmpdir);
    LOG("Creating temporary file at: %s", temp_file);

    int fd = mkstemp(temp_file);
    if (fd == -1)
    {
        LOG("mkstemp failed to create temporary file");
        return false;
    }

    FILE *fp = fdopen(fd, "wb");
    if (!fp)
    {
        close(fd);
        unlink(temp_file);
        return false;
    }

    size_t written = fwrite(data, 1, (size_t)length, fp);
    fclose(fp);

    if (written != (size_t)length)
    {
        unlink(temp_file);
        return false;
    }

    // Add the "raw" option to tell CUPS not to filter the data.
    cups_option_t *options = NULL;
    int num_cups_options = 0;
    num_cups_options = cupsAddOption("raw", "true", num_cups_options, &options);

    for (int i = 0; i < num_options; i++)
    {
        if (option_keys && option_keys[i] && option_values && option_values[i])
        {
            num_cups_options = cupsAddOption(option_keys[i], option_values[i], num_cups_options, &options);
        }
    }

    int job_id = cupsPrintFile(printer_name, temp_file, doc_name, num_cups_options, options);
    if (job_id <= 0)
    {
        LOG("cupsPrintFile failed, error: %s", cupsLastErrorString());
    }
    cupsFreeOptions(num_cups_options, options);
    unlink(temp_file);
    LOG("raw_data_to_printer finished with job_id: %d", job_id);
    return job_id > 0;
#endif
}

// Internal helper to calculate the destination rectangle for scaling content to fit a target area.
static void _scale_to_fit(int src_width, int src_height, int target_width, int target_height, int *dest_width, int *dest_height)
{
    float page_aspect = 1.0f;
    if (src_height > 0)
    {
        page_aspect = (float)src_width / (float)src_height;
    }

    float target_aspect = 1.0f;
    if (target_height != 0)
    {
        target_aspect = (float)target_width / (float)target_height;
    }

    if (page_aspect > target_aspect)
    {
        *dest_width = target_width;
        *dest_height = (int)(target_width / page_aspect);
    }
    else
    {
        *dest_height = target_height;
        *dest_width = (int)(target_height * page_aspect);
    }
}

#ifdef _WIN32

// Common internal function for PDF printing on Windows.
// Returns a job ID if `submit_job` is true, otherwise returns 1 for success or 0 for failure.
static int32_t _print_pdf_job_win(const char *printer_name, const char *pdf_file_path, const char *doc_name, int scaling_mode, int copies, const char *page_range, const char *alignment, int num_options, const char **option_keys, const char **option_values, bool submit_job)
{
    // Ensure the PDFium library is loaded and initialized. This is thread-safe and idempotent.
    if (!ensure_pdfium_initialized())
    {
        // Error is already set by ensure_pdfium_initialized or its callback.
        return 0;
    }

    // Clear any previous errors at the start of an operation.
    set_last_error("");
    double custom_scale;
    int paper_size_id, paper_source_id, orientation, color_mode, print_quality, media_type_id, duplex_mode;
    bool collate = true; // Default to collated (complete copies printed together)
    parse_windows_options(num_options, option_keys, option_values, &paper_size_id, &paper_source_id, &orientation, &color_mode, &print_quality, &media_type_id, &custom_scale, &collate, &duplex_mode);

    wchar_t *printer_name_w = to_utf16(printer_name);
    if (!printer_name_w)
    {
        set_last_error("Failed to convert printer name to UTF-16.");
        LOG("print_pdf_job_win: Failed to convert printer name to UTF-16");
        return 0;
    }

    FPDF_DOCUMENT doc = g_pdfium.FPDF_LoadDocument((FPDF_STRING)pdf_file_path, NULL);
    if (!doc)
    {
        set_last_error("Failed to load PDF document at path '%s'. Error code: %ld. The file may be missing, corrupt, or password-protected.", pdf_file_path, g_pdfium.FPDF_GetLastError());
        LOG("print_pdf_job_win: FPDF_LoadDocument failed for path: %s. Error: %ld", pdf_file_path, g_pdfium.FPDF_GetLastError());
        free(printer_name_w);
        return 0;
    }
    LOG("print_pdf_job_win: PDF document loaded successfully.");

    DEVMODEW *pDevMode = get_modified_devmode(printer_name_w, paper_size_id, paper_source_id, orientation, color_mode, print_quality, media_type_id, copies, collate, duplex_mode);

    HDC hdc = CreateDCW(L"WINSPOOL", printer_name_w, NULL, pDevMode);
    if (pDevMode)
        free(pDevMode); // DEVMODE is copied by CreateDC, so we can free it now.

    if (!hdc)
    {
        set_last_error("Failed to create device context (CreateDCW) for printer '%s'. Error: %lu. This often indicates an invalid printer name or driver issue.", printer_name, GetLastError());
        LOG("print_pdf_job_win: CreateDCW failed for printer '%s' with error %lu. This often indicates an invalid DEVMODE.", printer_name, GetLastError());
        g_pdfium.FPDF_CloseDocument(doc);
        free(printer_name_w);
        return 0;
    }

    wchar_t *doc_name_w = to_utf16(doc_name);
    DOCINFOW di;
    memset(&di, 0, sizeof(DOCINFOW));
    di.cbSize = sizeof(DOCINFOW);
    di.lpszDocName = doc_name_w;
    int job_id = StartDocW(hdc, &di);

    if (job_id <= 0)
    {
        set_last_error("Failed to start print document (StartDocW). Error: %lu.", GetLastError());
        LOG("print_pdf_job_win: StartDocW failed with error %lu", GetLastError());
        if (doc_name_w)
            free(doc_name_w);
        DeleteDC(hdc);
        g_pdfium.FPDF_CloseDocument(doc);
        free(printer_name_w);
        return 0;
    }
    // doc_name_w is used by the system, don't free it until EndDoc.
    LOG("print_pdf_job_win: StartDocW succeeded with Job ID: %d", job_id);

    int page_count = g_pdfium.FPDF_GetPageCount(doc);
    if (page_count <= 0)
    {
        set_last_error("Could not get page count from the PDF document. The file may be empty, corrupt, or in an unsupported format. (Page count: %d)", page_count);
        LOG("print_pdf_job_win: FPDF_GetPageCount returned %d. Aborting.", page_count);
        if (doc_name_w)
            free(doc_name_w);
        AbortDoc(hdc);
        DeleteDC(hdc);
        g_pdfium.FPDF_CloseDocument(doc);
        free(printer_name_w);
        // We don't need to free pages_to_print as it's not allocated yet.
        return 0;
    }

    LOG("print_pdf_job_win: PDF has %d pages.", page_count);
    bool *pages_to_print = (bool *)malloc(page_count * sizeof(bool));
    if (!pages_to_print)
    {
        set_last_error("Failed to allocate memory for page range flags.");
        LOG("print_pdf_job_win: Failed to allocate memory for page range flags.");
        if (doc_name_w)
            free(doc_name_w);
        AbortDoc(hdc);
        DeleteDC(hdc);
        g_pdfium.FPDF_CloseDocument(doc);
        free(printer_name_w);
        return 0;
    }

    if (!parse_page_range(page_range, pages_to_print, page_count))
    {
        // If parse_page_range fails, it now sets a specific error. If it's still empty, provide a generic one.
        if (g_last_error_message == NULL || strlen(g_last_error_message) == 0)
            set_last_error("Invalid page range format: '%s'. Use a format like '1-3,5,7-9'.", page_range ? page_range : "");
        LOG("print_pdf_job_win: Invalid page range string provided: %s", page_range ? page_range : "(null)");
        free(pages_to_print);
        if (doc_name_w)
            free(doc_name_w);
        AbortDoc(hdc);
        DeleteDC(hdc);
        g_pdfium.FPDF_CloseDocument(doc);
        free(printer_name_w);
        return 0;
    }
    LOG("print_pdf_job_win: Page range parsed successfully. Copies: %d.", copies);

    // --- Alignment ---
    double align_x_factor = 0.5; // Default to center
    double align_y_factor = 0.5; // Default to center

    if (alignment)
    {
        char *alignment_lower = strdup(alignment);
        if (alignment_lower)
        {
            for (int i = 0; alignment_lower[i]; i++)
            {
                alignment_lower[i] = tolower(alignment_lower[i]);
            }

            if (strstr(alignment_lower, "left"))
            {
                align_x_factor = 0.0;
            }
            else if (strstr(alignment_lower, "right"))
            {
                align_x_factor = 1.0;
            }

            if (strstr(alignment_lower, "top"))
            {
                align_y_factor = 0.0;
            }
            else if (strstr(alignment_lower, "bottom"))
            {
                align_y_factor = 1.0;
            }

            free(alignment_lower);
        }
    }

    bool success = true;
    // The outer loop for copies is removed. The driver will handle it via DEVMODE.
    // for (int c = 0; c < copies && success; c++)
    // {
    // LOG("print_pdf_job_win: Starting copy %d of %d.", c + 1, copies);
    for (int i = 0; i < page_count && success; ++i)
    {
        if (!pages_to_print[i])
        {
            continue;
        }
        LOG("print_pdf_job_win: Printing page %d (0-indexed).", i);

        // Manually pump the Windows message queue. This is CRITICAL for STA threads
        // that perform long-running operations. It prevents the thread from becoming
        // unresponsive and causing deadlocks or other COM errors with the printer driver.
        MSG msg;
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE))
        {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }

        // Declare destination rectangle variables for the current page.
        int dest_x = 0, dest_y = 0, dest_width = 0, dest_height = 0;

        FPDF_PAGE page = g_pdfium.FPDF_LoadPage(doc, i);
        if (!page)
        {
            set_last_error("Failed to load PDF page %d.", i + 1);
            LOG("print_pdf_job_win: FPDF_LoadPage failed for page %d", i);
            success = false;
            break;
        }

        if (StartPage(hdc) <= 0)
        {
            set_last_error("Failed to start page %d. Error: %lu.", i + 1, GetLastError());
            LOG("print_pdf_job_win: StartPage failed for page %d with error %lu", i, GetLastError());
            // Clean up the page resource before breaking from the loop.
            g_pdfium.FPDF_ClosePage(page);
            success = false;
            break;
        }

        // --- Get PDF page dimensions and rotation ---
        float pdf_width_pt = g_pdfium.FPDF_GetPageWidthF(page);
        float pdf_height_pt = g_pdfium.FPDF_GetPageHeightF(page);

        int rotation = g_pdfium.FPDFPage_GetRotation(page);
        if (rotation == 1 || rotation == 3)
        { // 90 or 270 degrees, swap dimensions
            float temp = pdf_width_pt;
            pdf_width_pt = pdf_height_pt;
            pdf_height_pt = temp;
        }

        int dpi_x = GetDeviceCaps(hdc, LOGPIXELSX);
        int dpi_y = GetDeviceCaps(hdc, LOGPIXELSY);
        int printable_width_pixels = GetDeviceCaps(hdc, HORZRES);
        int printable_height_pixels = GetDeviceCaps(hdc, VERTRES);

        LOG("print_pdf_job_win: Page %d: PDF Dimensions (pt): %.2f x %.2f", i, pdf_width_pt, pdf_height_pt);
        LOG("print_pdf_job_win: Page %d: Device DPI: %d x %d", i, dpi_x, dpi_y);
        LOG("print_pdf_job_win: Page %d: Printable Area (pixels): %d x %d", i, printable_width_pixels, printable_height_pixels);

        // Calculate the PDF page size in device pixels.
        int pdf_pixel_width = (int)(pdf_width_pt / 72.0f * dpi_x);
        int pdf_pixel_height = (int)(pdf_height_pt / 72.0f * dpi_y);

        if (scaling_mode == 0)
        { // Fit to Printable Area (formerly Fit Page)
            _scale_to_fit(pdf_pixel_width, pdf_pixel_height, printable_width_pixels, printable_height_pixels, &dest_width, &dest_height);
            LOG("print_pdf_job_win: Page %d: ScalingMode=FitToPrintableArea, Dest=(%d,%d)", i, dest_width, dest_height);
        }
        else if (scaling_mode == 1)
        { // Actual Size
            // Calculate actual size in device pixels
            dest_width = pdf_pixel_width;
            dest_height = pdf_pixel_height;
            LOG("print_pdf_job_win: Page %d: ScalingMode=ActualSize, Dest=(%d,%d)", i, dest_width, dest_height);
        }
        else if (scaling_mode == 2)
        { // Shrink to Fit
            // If the PDF page is larger than the printable area, scale down to fit.
            // Otherwise, print at actual size.
            if (pdf_pixel_width > printable_width_pixels || pdf_pixel_height > printable_height_pixels)
            {
                _scale_to_fit(pdf_pixel_width, pdf_pixel_height, printable_width_pixels, printable_height_pixels, &dest_width, &dest_height);
                LOG("print_pdf_job_win: Page %d: ScalingMode=ShrinkToFit (scaled), Dest=(%d,%d)", i, dest_width, dest_height);
            }
            else
            {
                dest_width = pdf_pixel_width;
                dest_height = pdf_pixel_height;
                LOG("print_pdf_job_win: Page %d: ScalingMode=ShrinkToFit (actual size), Dest=(%d,%d)", i, dest_width, dest_height);
            }
        }
        else if (scaling_mode == 3)
        { // Fit to Paper
            int paper_width = GetDeviceCaps(hdc, PHYSICALWIDTH);
            int paper_height = GetDeviceCaps(hdc, PHYSICALHEIGHT);
            _scale_to_fit(pdf_pixel_width, pdf_pixel_height, paper_width, paper_height, &dest_width, &dest_height);
            LOG("print_pdf_job_win: Page %d: ScalingMode=FitToPaper, Dest=(%d,%d)", i, dest_width, dest_height);
        }
        else if (scaling_mode == 4)
        { // Custom Scale
            // Apply custom scale factor
            dest_width = (int)(pdf_pixel_width * custom_scale);
            dest_height = (int)(pdf_pixel_height * custom_scale);
            LOG("print_pdf_job_win: Page %d: ScalingMode=CustomScale (%.2f), Dest=(%d,%d)", i, custom_scale, dest_width, dest_height);
        }
        else
        { // Default to Fit to Printable Area
            _scale_to_fit(pdf_pixel_width, pdf_pixel_height, printable_width_pixels, printable_height_pixels, &dest_width, &dest_height);
            LOG("print_pdf_job_win: Page %d: ScalingMode=Default (FitToPrintableArea), Dest=(%d,%d)", i, dest_width, dest_height);
        }

        if (scaling_mode == 3)
        { // Fit to Paper alignment is relative to physical paper
            int paper_width = GetDeviceCaps(hdc, PHYSICALWIDTH);
            int paper_height = GetDeviceCaps(hdc, PHYSICALHEIGHT);
            int offset_x = GetDeviceCaps(hdc, PHYSICALOFFSETX);
            int offset_y = GetDeviceCaps(hdc, PHYSICALOFFSETY);
            dest_x = (int)((paper_width - dest_width) * align_x_factor) - offset_x;
            dest_y = (int)((paper_height - dest_height) * align_y_factor) - offset_y;
        }
        else
        { // All other modes are relative to the printable area
            dest_x = (int)((printable_width_pixels - dest_width) * align_x_factor);
            dest_y = (int)((printable_height_pixels - dest_height) * align_y_factor);
        }

        LOG("print_pdf_job_win: Page %d: Final DestRect=(%d,%d, %dx%d)", i, dest_x, dest_y, dest_width, dest_height);

        // --- Direct Rendering to Printer DC ---
        // Render the page directly to the printer's device context. This simplifies
        // the code by avoiding an intermediate bitmap.
        // NOTE: This is a synchronous, blocking call. While simpler, it prevents
        // the message pump from running during rendering, which could cause
        // issues on very complex pages. The previous progressive rendering
        // implementation was more complex but kept the thread responsive.
        g_pdfium.FPDF_RenderPage(hdc, page, dest_x, dest_y, dest_width, dest_height, rotation, FPDF_ANNOT | FPDF_PRINTING | FPDF_NO_NATIVETEXT);

        if (EndPage(hdc) <= 0)
        {
            set_last_error("Failed to end page %d. Error: %lu.", i + 1, GetLastError());
            LOG("print_pdf_job_win: EndPage failed for page %d with error %lu", i, GetLastError());
            success = false;
        }

        // Now, close the page object itself to prevent memory leaks.
        g_pdfium.FPDF_ClosePage(page);

        if (!success)
        {
            break; // Exit the loop on failure
        }
    }
    // }

    free(pages_to_print);
    if (doc_name_w)
        free(doc_name_w);

    if (success)
    {
        LOG("print_pdf_job_win: All pages processed successfully. Calling EndDoc.");
        EndDoc(hdc);
    }
    else
    {
        LOG("print_pdf_job_win: A failure occurred. Calling AbortDoc.");
        AbortDoc(hdc);
    }

    DeleteDC(hdc);
    g_pdfium.FPDF_CloseDocument(doc);
    free(printer_name_w);

    if (submit_job)
    {
        LOG("_print_pdf_job_win (submit) finished with result: %d, job_id: %d", success, job_id);
        return success ? job_id : 0;
    }
    else
    {
        LOG("_print_pdf_job_win (print) finished with result: %d", success);
        return success ? 1 : 0;
    }
}
#endif

FFI_PLUGIN_EXPORT const char *get_last_error()
{
    return g_last_error_message ? g_last_error_message : "";
}

FFI_PLUGIN_EXPORT bool print_pdf(const char *printer_name, const char *pdf_file_path, const char *doc_name, int scaling_mode, int copies, const char *page_range, int num_options, const char **option_keys, const char **option_values, const char *alignment)
{
    LOG("print_pdf called for printer: '%s', path: '%s', doc: '%s'", printer_name, pdf_file_path, doc_name);

    // Validate input parameters
    if (!printer_name || !pdf_file_path || !doc_name || copies <= 0)
    {
        LOG("Invalid input parameters");
        return false;
    }

#ifdef _WIN32
    return _print_pdf_job_win(printer_name, pdf_file_path, doc_name, scaling_mode, copies, page_range, alignment, num_options, option_keys, option_values, false) == 1;
#else // macOS / Linux (CUPS)
    cups_option_t *options = NULL;
    int num_cups_options = 0;

    for (int i = 0; i < num_options; i++)
    {
        if (option_keys && option_keys[i] && option_values && option_values[i])
        {
            LOG("Adding CUPS option: %s=%s", option_keys[i], option_values[i]);
            num_cups_options = cupsAddOption(option_keys[i], option_values[i], num_cups_options, &options);
        }
    }

    int job_id = cupsPrintFile(printer_name, pdf_file_path, doc_name, num_cups_options, options);
    if (job_id <= 0)
    {
        LOG("cupsPrintFile failed, error: %s", cupsLastErrorString());
    }
    cupsFreeOptions(num_cups_options, options);
    LOG("print_pdf finished with job_id: %d", job_id);
    return job_id > 0;
#endif
}

FFI_PLUGIN_EXPORT JobList *get_print_jobs(const char *printer_name)
{
    JobList *list = (JobList *)malloc(sizeof(JobList));
    if (!list)
        return NULL;
    list->count = 0;
    list->jobs = NULL;

    if (!printer_name)
    {
        LOG("get_print_jobs called with null printer name");
        return list; // Return empty list
    }

    LOG("get_print_jobs called for printer: '%s'", printer_name);
#ifdef _WIN32
    HANDLE hPrinter;
    DWORD needed, returned;

    wchar_t *printer_name_w = to_utf16(printer_name);
    if (!printer_name_w)
    {
        free(list);
        return NULL;
    }
    if (!OpenPrinterW(printer_name_w, &hPrinter, NULL))
    {
        free(list);
        LOG("OpenPrinterW failed with error %lu", GetLastError());
        free(printer_name_w);
        return NULL;
    }

    EnumJobsW(hPrinter, 0, 0xFFFFFFFF, 2, NULL, 0, &needed, &returned);
    if (needed == 0)
    {
        ClosePrinter(hPrinter);
        free(printer_name_w);
        return list;
    }
    BYTE *buffer = (BYTE *)malloc(needed);
    if (!buffer)
    {
        ClosePrinter(hPrinter);
        free(printer_name_w);
        free(list);
        return NULL;
    }

    if (EnumJobsW(hPrinter, 0, 0xFFFFFFFF, 2, buffer, needed, &needed, &returned))
    {
        LOG("Found %lu jobs on Windows", returned);
        list->count = (int)returned;
        list->jobs = (JobInfo *)malloc(returned * sizeof(JobInfo));
        if (!list->jobs)
        {
            free(buffer);
            ClosePrinter(hPrinter);
            free(printer_name_w);
            free(list);
            return NULL;
        }
        JOB_INFO_2W *jobs = (JOB_INFO_2W *)buffer;
        for (DWORD i = 0; i < returned; i++)
        {
            list->jobs[i].id = jobs[i].JobId;
            list->jobs[i].title = to_utf8(jobs[i].pDocument);
            list->jobs[i].status = (int)jobs[i].Status;
        }
    }
    else
    {
        LOG("EnumJobsW failed with error %lu", GetLastError());
    }
    free(buffer);
    free(printer_name_w);
    ClosePrinter(hPrinter);
    return list;
#else // macOS / Linux
    cups_job_t *jobs;
    LOG("Calling cupsGetJobs for active jobs");
    int num_jobs = cupsGetJobs(&jobs, printer_name, 1, CUPS_WHICHJOBS_ACTIVE);
    if (num_jobs <= 0)
    {
        cupsFreeJobs(num_jobs, jobs);
        return list;
    }

    LOG("Found %d active jobs on CUPS-based system", num_jobs);
    list->count = num_jobs;
    list->jobs = (JobInfo *)malloc(num_jobs * sizeof(JobInfo));
    if (!list->jobs)
    {
        cupsFreeJobs(num_jobs, jobs);
        free(list);
        return NULL;
    }

    for (int i = 0; i < num_jobs; i++)
    {
        list->jobs[i].id = (uint32_t)jobs[i].id;
        list->jobs[i].title = strdup(jobs[i].title ? jobs[i].title : "Unknown");
        list->jobs[i].status = jobs[i].state;
    }
    cupsFreeJobs(num_jobs, jobs);
    return list;
#endif
}

FFI_PLUGIN_EXPORT void free_job_list(JobList *job_list)
{
    if (!job_list)
        return;
    if (job_list->jobs)
    {
        for (int i = 0; i < job_list->count; i++)
        {
            free(job_list->jobs[i].title);
        }
        free(job_list->jobs);
    }
    free(job_list);
}

FFI_PLUGIN_EXPORT int open_printer_properties(const char *printer_name, intptr_t hwnd)
{
    LOG("open_printer_properties called for printer: '%s'", printer_name);
#ifdef _WIN32
    if (!printer_name)
    {
        LOG("Printer name is null");
        return 0; // Error
    }

    wchar_t *printer_name_w = to_utf16(printer_name);
    if (!printer_name_w)
    {
        LOG("Failed to convert printer name to UTF-16");
        return 0; // Error
    }

    HANDLE hPrinter;
    PRINTER_DEFAULTSW printerDefaults = {NULL, NULL, PRINTER_ALL_ACCESS};
    if (!OpenPrinterW(printer_name_w, &hPrinter, &printerDefaults))
    {
        LOG("OpenPrinterW failed with error %lu", GetLastError());
        free(printer_name_w);
        return 0; // Error
    }

    // The modern and recommended way to show the printer properties dialog is
    // by using DocumentProperties with the DM_PROMPT flag.

    // First, get the size of the DEVMODE structure for the printer.
    LONG devModeSize = DocumentPropertiesW(NULL, hPrinter, printer_name_w, NULL, NULL, 0);
    if (devModeSize <= 0)
    {
        LOG("DocumentProperties (get size) failed with error %lu", GetLastError());
        ClosePrinter(hPrinter);
        free(printer_name_w);
        return 0; // Error
    }

    DEVMODEW *pDevMode = (DEVMODEW *)malloc(devModeSize);
    if (!pDevMode)
    {
        LOG("Failed to allocate memory for DEVMODE structure.");
        ClosePrinter(hPrinter);
        free(printer_name_w);
        return 0; // Error
    }

    // Get the current printer settings to populate the dialog.
    if (DocumentPropertiesW(NULL, hPrinter, printer_name_w, pDevMode, NULL, DM_OUT_BUFFER) != IDOK)
    {
        LOG("DocumentProperties (get defaults) failed with error %lu", GetLastError());
        free(pDevMode);
        ClosePrinter(hPrinter);
        free(printer_name_w);
        return 0; // Error
    }

    // Display the properties dialog. The user's changes will be written back to pDevMode.
    LONG result = DocumentPropertiesW((HWND)hwnd, hPrinter, printer_name_w, pDevMode, pDevMode, DM_IN_BUFFER | DM_OUT_BUFFER | DM_PROMPT);

    int return_status = 0; // Default to error

    if (result == IDOK)
    {
        LOG("Printer properties dialog closed with OK. Applying changes to printer defaults.");

        // To apply the changes, we need to use SetPrinter with PRINTER_INFO_2.
        DWORD needed = 0;
        // Get the size needed for PRINTER_INFO_2
        GetPrinterW(hPrinter, 2, NULL, 0, &needed);
        if (needed > 0)
        {
            PRINTER_INFO_2W *pinfo2 = (PRINTER_INFO_2W *)malloc(needed);
            if (pinfo2)
            {
                // Get the current printer info
                if (GetPrinterW(hPrinter, 2, (LPBYTE)pinfo2, needed, &needed))
                {
                    // Update the DEVMODE pointer in the PRINTER_INFO_2 struct with the user's changes.
                    pinfo2->pDevMode = pDevMode;
                    // Security descriptor must be NULL for SetPrinter.
                    pinfo2->pSecurityDescriptor = NULL;

                    // Apply the changes to the printer's defaults.
                    if (!SetPrinterW(hPrinter, 2, (LPBYTE)pinfo2, 0))
                    {
                        LOG("SetPrinterW failed with error %lu", GetLastError());
                    }
                    else
                    {
                        LOG("SetPrinterW succeeded. Broadcasting change.");
                        SendMessageTimeout(HWND_BROADCAST, WM_WININICHANGE, 0, (LPARAM)L"windows", SMTO_NORMAL, 1000, NULL);
                    }
                }
                free(pinfo2);
            }
        }
        return_status = 1; // OK
    }
    else if (result == IDCANCEL)
    {
        LOG("Printer properties dialog was cancelled.");
        return_status = 2; // Cancel
    }
    else
    {
        LOG("DocumentProperties (prompt) failed with result: %ld, error: %lu", result, GetLastError());
        return_status = 0; // Error
    }

    free(pDevMode);
    ClosePrinter(hPrinter);
    free(printer_name_w);
    return return_status;
#else
    (void)hwnd; // hwnd is Windows-specific
    if (!printer_name)
    {
        LOG("Printer name is null");
        return 0; // Error
    }
    char command[PATH_MAX];
    snprintf(command, sizeof(command),
#ifdef __APPLE__
             "open http://localhost:631/printers/\"%s\"",
#else // Linux
             "xdg-open http://localhost:631/printers/\"%s\"",
#endif
             printer_name);
    LOG("Executing command: %s", command);
    int cmd_result = system(command);
    if (cmd_result != 0)
    {
        LOG("Command '%s' failed with exit code %d", command, cmd_result);
        return 0; // Error
    }
    return 1; // Dispatched
#endif
}

FFI_PLUGIN_EXPORT bool pause_print_job(const char *printer_name, uint32_t job_id)
{
    if (!printer_name)
    {
        LOG("pause_print_job called with null printer name");
        return false;
    }

    LOG("pause_print_job called for printer: '%s', job_id: %u", printer_name, job_id);
#ifdef _WIN32
    HANDLE hPrinter;
    wchar_t *printer_name_w = to_utf16(printer_name);
    if (!printer_name_w)
        return false;
    if (!OpenPrinterW(printer_name_w, &hPrinter, NULL))
    {
        free(printer_name_w);
        return false;
    }
    free(printer_name_w);

    bool result = SetJobW(hPrinter, job_id, 0, NULL, JOB_CONTROL_PAUSE);
    if (!result)
        LOG("SetJobW(PAUSE) failed with error %lu", GetLastError());
    ClosePrinter(hPrinter);
    return result;
#else
    bool result = cupsCancelJob2(CUPS_HTTP_DEFAULT, printer_name, (int)job_id, IPP_HOLD_JOB) == 1;
    if (!result)
        LOG("cupsCancelJob2(IPP_HOLD_JOB) failed, error: %s", cupsLastErrorString());
    return result;
#endif
}

FFI_PLUGIN_EXPORT bool resume_print_job(const char *printer_name, uint32_t job_id)
{
    if (!printer_name)
    {
        LOG("resume_print_job called with null printer name");
        return false;
    }

    LOG("resume_print_job called for printer: '%s', job_id: %u", printer_name, job_id);
#ifdef _WIN32
    HANDLE hPrinter;
    wchar_t *printer_name_w = to_utf16(printer_name);
    if (!printer_name_w)
        return false;
    if (!OpenPrinterW(printer_name_w, &hPrinter, NULL))
    {
        free(printer_name_w);
        return false;
    }
    free(printer_name_w);

    bool result = SetJobW(hPrinter, job_id, 0, NULL, JOB_CONTROL_RESUME);
    if (!result)
        LOG("SetJobW(RESUME) failed with error %lu", GetLastError());
    ClosePrinter(hPrinter);
    return result;
#else
    bool result = cupsCancelJob2(CUPS_HTTP_DEFAULT, printer_name, (int)job_id, IPP_RELEASE_JOB) == 1;
    if (!result)
        LOG("cupsCancelJob2(IPP_RELEASE_JOB) failed, error: %s", cupsLastErrorString());
    return result;
#endif
}

FFI_PLUGIN_EXPORT bool cancel_print_job(const char *printer_name, uint32_t job_id)
{
    if (!printer_name)
    {
        LOG("cancel_print_job called with null printer name");
        return false;
    }

    LOG("cancel_print_job called for printer: '%s', job_id: %u", printer_name, job_id);
#ifdef _WIN32
    HANDLE hPrinter;
    wchar_t *printer_name_w = to_utf16(printer_name);
    if (!printer_name_w)
        return false;
    if (!OpenPrinterW(printer_name_w, &hPrinter, NULL))
    {
        free(printer_name_w);
        return false;
    }
    free(printer_name_w);

    bool result = SetJobW(hPrinter, job_id, 0, NULL, JOB_CONTROL_CANCEL);
    if (!result)
        LOG("SetJobW(CANCEL) failed with error %lu", GetLastError());
    ClosePrinter(hPrinter);
    return result;
#else
    bool result = cupsCancelJob(printer_name, (int)job_id) == 1;
    if (!result)
        LOG("cupsCancelJob failed, error: %s", cupsLastErrorString());
    return result;
#endif
}

FFI_PLUGIN_EXPORT CupsOptionList *get_supported_cups_options(const char *printer_name)
{
    if (!printer_name)
    {
        LOG("get_supported_cups_options called with null printer name");
        CupsOptionList *list = (CupsOptionList *)malloc(sizeof(CupsOptionList));
        if (list)
        {
            list->count = 0;
            list->options = NULL;
        }
        return list;
    }

    LOG("get_supported_cups_options called for printer: '%s'", printer_name);
    CupsOptionList *list = (CupsOptionList *)malloc(sizeof(CupsOptionList));
    if (!list)
        return NULL;
    list->count = 0;
    list->options = NULL;

#ifdef _WIN32
    // Not supported on Windows
    return list;
#else // macOS / Linux (CUPS)
    const char *ppd_filename = cupsGetPPD(printer_name);
    if (!ppd_filename)
    {
        LOG("cupsGetPPD failed for '%s', error: %s", printer_name, cupsLastErrorString());
        return list;
    }
    LOG("Found PPD file: %s", ppd_filename);

    ppd_file_t *ppd = ppdOpenFile(ppd_filename);
    if (!ppd)
    {
        LOG("ppdOpenFile failed for '%s'", ppd_filename);
        unlink(ppd_filename); // Clean up temporary PPD file
        return list;
    }

    ppdMarkDefaults(ppd);

    int num_ui_options = 0;
    for (int i = 0; i < ppd->num_groups; i++)
    {
        num_ui_options += ppd->groups[i].num_options;
    }

    if (num_ui_options == 0)
    {
        ppdClose(ppd);
        unlink(ppd_filename);
        LOG("No UI options found in PPD");
        return list;
    }

    list->count = num_ui_options;
    LOG("Found %d UI options in PPD", num_ui_options);
    list->options = (CupsOption *)malloc(num_ui_options * sizeof(CupsOption));
    if (!list->options)
    {
        ppdClose(ppd);
        unlink(ppd_filename);
        free(list);
        return NULL;
    }

    int current_option_index = 0;
    ppd_option_t *option;
    for (int i = 0; i < ppd->num_groups; i++)
    {
        ppd_group_t *group = ppd->groups + i;
        for (int j = 0; j < group->num_options; j++)
        {
            option = group->options + j;

            list->options[current_option_index].name = strdup(option->keyword ? option->keyword : "");
            list->options[current_option_index].default_value = strdup(option->defchoice ? option->defchoice : "");

            list->options[current_option_index].supported_values.count = option->num_choices;
            if (option->num_choices > 0)
            {
                list->options[current_option_index].supported_values.choices = (CupsOptionChoice *)malloc(option->num_choices * sizeof(CupsOptionChoice));
                if (list->options[current_option_index].supported_values.choices)
                {
                    for (int k = 0; k < option->num_choices; k++)
                    {
                        list->options[current_option_index].supported_values.choices[k].choice = strdup(option->choices[k].choice ? option->choices[k].choice : "");
                        list->options[current_option_index].supported_values.choices[k].text = strdup(option->choices[k].text ? option->choices[k].text : "");
                    }
                }
                else
                {
                    list->options[current_option_index].supported_values.count = 0;
                }
            }
            else
            {
                list->options[current_option_index].supported_values.choices = NULL;
            }
            current_option_index++;
        }
    }

    ppdClose(ppd);
    unlink(ppd_filename); // Clean up temporary PPD file
    LOG("get_supported_cups_options finished");
    return list;
#endif
}

FFI_PLUGIN_EXPORT void free_cups_option_list(CupsOptionList *option_list)
{
    if (!option_list)
        return;
    if (option_list->options)
    {
        for (int i = 0; i < option_list->count; i++)
        {
            free(option_list->options[i].name);
            free(option_list->options[i].default_value);
            if (option_list->options[i].supported_values.choices)
            {
                for (int j = 0; j < option_list->options[i].supported_values.count; j++)
                {
                    free(option_list->options[i].supported_values.choices[j].choice);
                    free(option_list->options[i].supported_values.choices[j].text);
                }
                free(option_list->options[i].supported_values.choices);
            }
        }
        free(option_list->options);
    }
    free(option_list);
}

FFI_PLUGIN_EXPORT WindowsPrinterCapabilities *get_windows_printer_capabilities(const char *printer_name)
{
    if (!printer_name)
    {
        LOG("get_windows_printer_capabilities called with null printer name");
        return (WindowsPrinterCapabilities *)calloc(1, sizeof(WindowsPrinterCapabilities));
    }

    LOG("get_windows_printer_capabilities called for printer: '%s'", printer_name);
#ifndef _WIN32
    return (WindowsPrinterCapabilities *)calloc(1, sizeof(WindowsPrinterCapabilities));
#else
    wchar_t *printer_name_w = to_utf16(printer_name);
    if (!printer_name_w)
    {
        LOG("Failed to convert printer name to UTF-16");
        return (WindowsPrinterCapabilities *)calloc(1, sizeof(WindowsPrinterCapabilities));
    }

    HANDLE hPrinter;
    if (!OpenPrinterW(printer_name_w, &hPrinter, NULL))
    {
        LOG("OpenPrinterW failed with error %lu", GetLastError());
        free(printer_name_w);
        return (WindowsPrinterCapabilities *)calloc(1, sizeof(WindowsPrinterCapabilities));
    }

    // First, get the size of the DEVMODE structure.
    LONG devModeSize = DocumentPropertiesW(NULL, hPrinter, printer_name_w, NULL, NULL, 0);
    if (devModeSize <= 0)
    {
        LOG("DocumentProperties (get size) failed with error %lu", GetLastError());
        ClosePrinter(hPrinter);
        free(printer_name_w);
        return (WindowsPrinterCapabilities *)calloc(1, sizeof(WindowsPrinterCapabilities));
    }

    DEVMODEW *pDevMode = (DEVMODEW *)malloc(devModeSize);
    if (!pDevMode)
    {
        LOG("Failed to allocate memory for DEVMODE structure.");
        ClosePrinter(hPrinter);
        free(printer_name_w);
        return (WindowsPrinterCapabilities *)calloc(1, sizeof(WindowsPrinterCapabilities));
    }

    // Get the default DEVMODE for the printer.
    if (DocumentPropertiesW(NULL, hPrinter, printer_name_w, pDevMode, NULL, DM_OUT_BUFFER) != IDOK)
    {
        LOG("DocumentProperties (get defaults) failed with error %lu", GetLastError());
        free(pDevMode);
        ClosePrinter(hPrinter);
        free(printer_name_w);
        return (WindowsPrinterCapabilities *)calloc(1, sizeof(WindowsPrinterCapabilities));
    }

    WindowsPrinterCapabilities *caps = (WindowsPrinterCapabilities *)calloc(1, sizeof(WindowsPrinterCapabilities));
    if (!caps)
    {
        free(pDevMode);
        ClosePrinter(hPrinter);
        free(printer_name_w);
        return NULL;
    }

    // --- Check DEVMODE fields for supported features ---
    caps->supports_landscape = (pDevMode->dmFields & DM_ORIENTATION) != 0;
    if (pDevMode->dmFields & DM_COLOR)
    {
        if (pDevMode->dmColor == DMCOLOR_COLOR)
        {
            caps->is_color_supported = true;
            caps->is_monochrome_supported = true; // Color printers can always print monochrome
        }
        else
        {
            caps->is_color_supported = false;
            caps->is_monochrome_supported = true;
        }
    }
    else
    {
        // If the DM_COLOR field is not supported, we can assume monochrome.
        caps->is_color_supported = false;
        caps->is_monochrome_supported = true;
    }

    // Get PRINTER_INFO_2 to find the port name required by DeviceCapabilities
    DWORD needed = 0;
    GetPrinterW(hPrinter, 2, NULL, 0, &needed);
    if (needed == 0)
    {
        LOG("GetPrinterW (to get size) failed with error %lu", GetLastError());
        // We can still return the basic caps from DEVMODE
        free(pDevMode);
        ClosePrinter(hPrinter);
        free(printer_name_w);
        return caps;
    }
    PRINTER_INFO_2W *pinfo2 = (PRINTER_INFO_2W *)malloc(needed);
    if (!pinfo2)
    {
        LOG("Failed to allocate memory for PRINTER_INFO_2W");
        free(pDevMode);
        ClosePrinter(hPrinter);
        free(printer_name_w);
        return caps; // Return what we have
    }
    if (!GetPrinterW(hPrinter, 2, (LPBYTE)pinfo2, needed, &needed))
    {
        LOG("GetPrinterW failed with error %lu", GetLastError());
        // Fallback to DEVMODE if GetPrinterW fails
        caps->supports_landscape = (pDevMode->dmFields & DM_ORIENTATION) != 0;
        caps->is_color_supported = (pDevMode->dmFields & DM_COLOR) && (pDevMode->dmColor == DMCOLOR_COLOR);
        caps->is_monochrome_supported = true;
        free(pinfo2);
        free(pDevMode);
        ClosePrinter(hPrinter);
        free(printer_name_w);
        return caps; // Return what we have
    }

    const wchar_t *port_w = pinfo2->pPortName;
    if (!port_w)
    {
        LOG("pPortName is NULL for printer '%s'. Cannot get extended capabilities.", printer_name);
        // Fallback to DEVMODE if port name is not available
        caps->supports_landscape = (pDevMode->dmFields & DM_ORIENTATION) != 0;
        caps->is_color_supported = (pDevMode->dmFields & DM_COLOR) && (pDevMode->dmColor == DMCOLOR_COLOR);
        caps->is_monochrome_supported = true;
    }
    else
    {
        // Use DeviceCapabilities for more reliable capability detection.
        caps->supports_landscape = (DeviceCapabilitiesW(printer_name_w, port_w, DC_ORIENTATION, NULL, pDevMode) > 0);
        caps->is_color_supported = (DeviceCapabilitiesW(printer_name_w, port_w, DC_COLORDEVICE, NULL, NULL) == 1);
        caps->is_monochrome_supported = true; // All printers should support monochrome.
        // --- Get Paper Sizes ---
        long num_papers = DeviceCapabilitiesW(printer_name_w, port_w, DC_PAPERS, NULL, NULL);
        if (num_papers > 0)
        {
            WORD *papers = (WORD *)malloc(num_papers * sizeof(WORD));
            wchar_t(*paper_names_w)[64] = (wchar_t(*)[64])malloc(num_papers * 64 * sizeof(wchar_t));
            POINT *paper_sizes_points = (POINT *)malloc(num_papers * sizeof(POINT));

            if (papers && paper_names_w && paper_sizes_points)
            {
                DeviceCapabilitiesW(printer_name_w, port_w, DC_PAPERS, (LPWSTR)papers, NULL);
                DeviceCapabilitiesW(printer_name_w, port_w, DC_PAPERNAMES, (LPWSTR)paper_names_w, NULL);
                DeviceCapabilitiesW(printer_name_w, port_w, DC_PAPERSIZE, (LPWSTR)paper_sizes_points, NULL);

                caps->paper_sizes.count = (int)num_papers;
                caps->paper_sizes.papers = (PaperSize *)malloc(num_papers * sizeof(PaperSize));
                if (caps->paper_sizes.papers)
                {
                    for (long i = 0; i < num_papers; i++)
                    {
                        caps->paper_sizes.papers[i].id = papers[i];
                        caps->paper_sizes.papers[i].name = to_utf8(paper_names_w[i]);
                        caps->paper_sizes.papers[i].width_mm = (float)paper_sizes_points[i].x / 10.0f;
                        caps->paper_sizes.papers[i].height_mm = (float)paper_sizes_points[i].y / 10.0f;
                    }
                }
            }
            if (papers)
                free(papers);
            if (paper_names_w)
                free(paper_names_w);
            if (paper_sizes_points)
                free(paper_sizes_points);
        }

        // --- Get Paper Bins (Sources) ---
        long num_bins = DeviceCapabilitiesW(printer_name_w, port_w, DC_BINS, NULL, NULL);
        if (num_bins > 0)
        {
            WORD *bins = (WORD *)malloc(num_bins * sizeof(WORD));
            wchar_t(*bin_names_w)[24] = (wchar_t(*)[24])malloc(num_bins * 24 * sizeof(wchar_t));

            if (bins && bin_names_w)
            {
                DeviceCapabilitiesW(printer_name_w, port_w, DC_BINS, (LPWSTR)bins, NULL);
                DeviceCapabilitiesW(printer_name_w, port_w, DC_BINNAMES, (LPWSTR)bin_names_w, NULL);

                caps->paper_sources.count = (int)num_bins;
                caps->paper_sources.sources = (PaperSource *)malloc(num_bins * sizeof(PaperSource));
                if (caps->paper_sources.sources)
                {
                    for (long i = 0; i < num_bins; i++)
                    {
                        caps->paper_sources.sources[i].id = bins[i];
                        caps->paper_sources.sources[i].name = to_utf8(bin_names_w[i]);
                    }
                }
            }
            if (bins)
                free(bins);
            if (bin_names_w)
                free(bin_names_w);
        }
    }

    free(pinfo2);
    free(pDevMode);
    ClosePrinter(hPrinter);
    free(printer_name_w);
    return caps;
#endif
}

FFI_PLUGIN_EXPORT void free_windows_printer_capabilities(WindowsPrinterCapabilities *capabilities)
{
    if (!capabilities)
        return;
    if (capabilities->paper_sizes.papers)
    {
        for (int i = 0; i < capabilities->paper_sizes.count; i++)
        {
            free(capabilities->paper_sizes.papers[i].name);
        }
        free(capabilities->paper_sizes.papers);
    }
    if (capabilities->paper_sources.sources)
    {
        for (int i = 0; i < capabilities->paper_sources.count; i++)
        {
            free(capabilities->paper_sources.sources[i].name);
        }
        free(capabilities->paper_sources.sources);
    }
    if (capabilities->media_types.types)
    {
        for (int i = 0; i < capabilities->media_types.count; i++)
        {
            free(capabilities->media_types.types[i].name);
        }
        free(capabilities->media_types.types);
    }
    if (capabilities->resolutions.resolutions)
    {
        free(capabilities->resolutions.resolutions);
    }
    free(capabilities);
}

FFI_PLUGIN_EXPORT int32_t submit_raw_data_job(const char *printer_name, const uint8_t *data, int length, const char *doc_name, int num_options, const char **option_keys, const char **option_values)
{
    LOG("submit_raw_data_job called for printer: '%s', doc: '%s', length: %d", printer_name, doc_name, length);

    // Validate input parameters
    if (!printer_name || !data || length <= 0 || !doc_name)
    {
        LOG("Invalid input parameters");
        return 0;
    }

#ifdef _WIN32
    int paper_size_id, paper_source_id, orientation, color_mode, print_quality, media_type_id, duplex_mode;
    double custom_scale; // Dummy
    bool collate = true; // Default to collated (complete copies printed together)
    parse_windows_options(num_options, option_keys, option_values, &paper_size_id, &paper_source_id, &orientation, &color_mode, &print_quality, &media_type_id, &custom_scale, &collate, &duplex_mode);

    DWORD job_id = 0;
    wchar_t *printer_name_w = to_utf16(printer_name);
    if (!printer_name_w)
        return 0;

    HANDLE hPrinter;
    DOC_INFO_1W docInfo;
    DEVMODEW *pDevMode = get_modified_devmode(printer_name_w, paper_size_id, paper_source_id, orientation, color_mode, print_quality, media_type_id, 1, collate, duplex_mode);

    PRINTER_DEFAULTSW printerDefaults = {NULL, pDevMode, PRINTER_ACCESS_USE};
    printerDefaults.pDatatype = L"RAW";

    if (!OpenPrinterW(printer_name_w, &hPrinter, &printerDefaults))
    {
        LOG("OpenPrinterW failed with error %lu", GetLastError());
        free(printer_name_w);
        if (pDevMode)
            free(pDevMode);
        return 0;
    }

    wchar_t *doc_name_w = to_utf16(doc_name);
    docInfo.pDocName = doc_name_w;
    docInfo.pOutputFile = NULL;
    docInfo.pDatatype = L"RAW";

    job_id = StartDocPrinterW(hPrinter, 1, (LPBYTE)&docInfo);
    if (job_id == 0)
    {
        ClosePrinter(hPrinter);
        LOG("StartDocPrinterW failed with error %lu", GetLastError());
        if (doc_name_w)
            free(doc_name_w);
        free(printer_name_w);
        if (pDevMode)
            free(pDevMode);
        return 0;
    }
    if (doc_name_w)
        free(doc_name_w);

    if (!StartPagePrinter(hPrinter))
    {
        EndDocPrinter(hPrinter);
        LOG("StartPagePrinter failed with error %lu", GetLastError());
        ClosePrinter(hPrinter);
        free(printer_name_w);
        if (pDevMode)
            free(pDevMode);
        return 0;
    }

    // --- Chunked Write with Message Pump ---
    // This prevents the STA thread from blocking if a very large raw data file is sent.
    const DWORD CHUNK_SIZE = 65536; // 64 KB
    DWORD total_written = 0;
    DWORD bytes_to_write = (DWORD)length;
    bool write_success = true;

    while (total_written < bytes_to_write)
    {
        DWORD chunk_to_write = (bytes_to_write - total_written > CHUNK_SIZE) ? CHUNK_SIZE : (bytes_to_write - total_written);
        DWORD written_this_chunk = 0;

        if (!WritePrinter(hPrinter, (LPVOID)(data + total_written), chunk_to_write, &written_this_chunk))
        {
            LOG("WritePrinter failed during chunked write with error %lu", GetLastError());
            write_success = false;
            break;
        }

        total_written += written_this_chunk;

        // Pump messages to keep the STA thread responsive.
        MSG msg;
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE))
        {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }

    EndPagePrinter(hPrinter);
    EndDocPrinter(hPrinter);
    ClosePrinter(hPrinter);
    free(printer_name_w);
    if (pDevMode)
        free(pDevMode);

    if (!write_success || total_written != (DWORD)length)
    {
        LOG("WritePrinter failed. Success: %d, Bytes written: %lu, Expected: %d", write_success, total_written, length);
        // The job might have been created but failed to write. The caller can still track this job ID to see its error state.
    }
    return (int32_t)job_id;
#else // macOS / Linux
    const char *tmpdir = getenv("TMPDIR");
    if (!tmpdir)
    {
        tmpdir = "/tmp";
    }

    char temp_file[PATH_MAX];
    snprintf(temp_file, sizeof(temp_file), "%s/printing_ffi_XXXXXX", tmpdir);
    LOG("Creating temporary file at: %s", temp_file);

    int fd = mkstemp(temp_file);
    if (fd == -1)
    {
        LOG("mkstemp failed to create temporary file");
        return 0;
    }

    FILE *fp = fdopen(fd, "wb");
    if (!fp)
    {
        close(fd);
        unlink(temp_file);
        return 0;
    }

    size_t written = fwrite(data, 1, (size_t)length, fp);
    fclose(fp);

    if (written != (size_t)length)
    {
        unlink(temp_file);
        return 0;
    }

    cups_option_t *options = NULL;
    int num_cups_options = 0;
    num_cups_options = cupsAddOption("raw", "true", num_cups_options, &options);

    for (int i = 0; i < num_options; i++)
    {
        if (option_keys && option_keys[i] && option_values && option_values[i])
        {
            num_cups_options = cupsAddOption(option_keys[i], option_values[i], num_cups_options, &options);
        }
    }

    int job_id = cupsPrintFile(printer_name, temp_file, doc_name, num_cups_options, options);
    if (job_id <= 0)
    {
        LOG("cupsPrintFile failed, error: %s", cupsLastErrorString());
    }
    cupsFreeOptions(num_cups_options, options);
    unlink(temp_file);
    LOG("submit_raw_data_job finished with job_id: %d", job_id);
    return job_id > 0 ? job_id : 0;
#endif
}

FFI_PLUGIN_EXPORT int32_t submit_pdf_job(const char *printer_name, const char *pdf_file_path, const char *doc_name, int scaling_mode, int copies, const char *page_range, int num_options, const char **option_keys, const char **option_values, const char *alignment)
{
    LOG("submit_pdf_job called for printer: '%s', path: '%s', doc: '%s'", printer_name, pdf_file_path, doc_name);

    // Validate input parameters
    if (!printer_name || !pdf_file_path || !doc_name || copies <= 0)
    {
        LOG("Invalid input parameters");
        return 0;
    }

#ifdef _WIN32
    return _print_pdf_job_win(printer_name, pdf_file_path, doc_name, scaling_mode, copies, page_range, alignment, num_options, option_keys, option_values, true);
#else // macOS / Linux (CUPS)
    cups_option_t *options = NULL;
    int num_cups_options = 0;
    for (int i = 0; i < num_options; i++)
    {
        if (option_keys && option_keys[i] && option_values && option_values[i])
        {
            num_cups_options = cupsAddOption(option_keys[i], option_values[i], num_cups_options, &options);
        }
    }

    int job_id = cupsPrintFile(printer_name, pdf_file_path, doc_name, num_cups_options, options);
    if (job_id <= 0)
    {
        LOG("cupsPrintFile failed, error: %s", cupsLastErrorString());
    }
    cupsFreeOptions(num_cups_options, options);
    LOG("submit_pdf_job finished with job_id: %d", job_id);
    return job_id > 0 ? job_id : 0;
#endif
}