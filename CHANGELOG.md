## 0.0.1

* **Initial Release**
* Added support for listing printers on macOS (via CUPS) and Windows (via winspool), including offline printers.
* Implemented raw data printing for sending formats like ZPL and ESC/POS directly to printers.
* Included print job management features: list, pause, resume, and cancel jobs.
* Utilizes FFI for direct native API communication, ensuring high performance.
