# flutter-webapp

An incredibly quick way to setup a webapp targeting iOS and Android using Flutter

### Features

- Firebase push notifications
- QR and barcodes scanner
- HTML5 Geolocation on both platforms
- Currently only supports remotely hosted content

### How to use

- Clone repo
- Tune `config/config.yml`
- Run

### Notes

- `master` branch is based on the official Google's flutter_webview plugin.
Currently this plugin doesn't support keyboard input on Android due to PlatformView limitations
- `altwebview` branch is based on flutter_webview_plugin, which do allows keyboard input but lacks support for displaying Flutter views on top of the web view

Released under Apache 2.0 license. Feel free to comment and contribute.
