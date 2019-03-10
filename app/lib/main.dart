/*
 * Copyright 2019 Luciano Iam <lucianito@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:yaml/yaml.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:barcode_scan/barcode_scan.dart';
import 'hex_color.dart';

void main() => runApp(WebApp());

class WebApp extends StatelessWidget {
  final Completer<WebViewController> _controller =
      Completer<WebViewController>();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging();

  @override
  Widget build(BuildContext context) {
    // Load configuration
    return FutureBuilder(
        future: DefaultAssetBundle.of(context).loadString('assets/config.yaml'),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.data == null) {
            // Configuration still not available
            return Container();
          }

          // Parse configuration
          final config = loadYaml(snapshot.data);
          final initialUrl =
              config['url'] + '?' + Random().nextInt(100).toString();
          final title = config['title'];

          // Setup app bar
          var appBar, themeData;
          if (config['app_bar'] != null && config['app_bar']['visible']) {
            appBar = AppBar(title: Text(title));
            final color = config['app_bar']['color'];
            if (color != null) {
              themeData = ThemeData(primaryColor: HexColor(color));
            }
          }

          // Setup notifications
          if (config['notifications']) {
            _enableNotifications(config);
          }

          // Trigger native geolocation permission request if needed
          if (config['geolocation']) {
            Geolocator()
                .getLastKnownPosition(desiredAccuracy: LocationAccuracy.high);
          }

          // Build application
          return MaterialApp(
              title: title,
              theme: themeData,
              home: Scaffold(
                  appBar: appBar,
                  // We're using a Builder here so we have a context that is below the Scaffold
                  // to allow calling Scaffold.of(context) so we can show a snackbar.
                  body: Builder(builder: (BuildContext context) {
                    return WebView(
                      initialUrl: initialUrl,
                      javascriptMode: JavascriptMode.unrestricted,
                      onWebViewCreated: (WebViewController webViewController) {
                        _controller.complete(webViewController);
                      },
                      javascriptChannels: <JavascriptChannel>[
                        _nativeJavascriptChannel(context),
                      ].toSet(),
                    );
                  })));
        });
  }

  void _enableNotifications(config) {
    // Request notifications permission on iOS
    _firebaseMessaging.requestNotificationPermissions();
    _firebaseMessaging.configure(onMessage: (Map<String, dynamic> msg) {
      print("FCM MESSAGE: ${(msg)}"); // FIXME
    });

    // Listen for token updates
    Stream<String> fcmStream = _firebaseMessaging.onTokenRefresh;
    fcmStream.listen((token) {
      print("FCM TOKEN IS: $token"); // FIXME
    });

    // Optionally subscribe to a FCM topic
    final fcmTopic = config['fcm_topic'];
    if (fcmTopic != null) {
      _firebaseMessaging.subscribeToTopic(fcmTopic);
    }
  }

  JavascriptChannel _nativeJavascriptChannel(BuildContext context) {
    return JavascriptChannel(
        name: 'Native',
        onMessageReceived: (JavascriptMessage message) {
          if (message.message == 'scanBarcode') {
            scanBarcode();
          }
        });
  }

  void scanBarcode() async {
    String js = '';
    try {
      String barcode = await BarcodeScanner.scan();
      js = 'if (typeof onBarcodeReady === "function") onBarcodeReady("' + barcode + '")';
    } on Exception catch (e) {
      js = 'if (typeof onBarcodeError === "function") onBarcodeError("' + e.toString() + '")';
    }
    _controller.future.then((controller) {
      controller.evaluateJavascript(js);
    });
  }
}
