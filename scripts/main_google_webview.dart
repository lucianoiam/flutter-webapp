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
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:yaml/yaml.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:barcode_scan/barcode_scan.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'hex_color.dart';

//void main() => runApp(WebApp());

class WebApp extends StatelessWidget {
  static const String CONFIG = 'assets/config.yaml';

  final Completer<WebViewController> _controller =
      Completer<WebViewController>();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging();
  final FlutterLocalNotificationsPlugin _localNotifications =
      new FlutterLocalNotificationsPlugin();
  final Completer<Map> _config = Completer<Map>();

  @override
  Widget build(BuildContext context) {
    // Load configuration
    return FutureBuilder(
        future: DefaultAssetBundle.of(context).loadString(CONFIG),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.data == null) {
            // Configuration still not available
            return Container();
          }

          // Parse configuration
          final config = loadYaml(snapshot.data);
          final initialUrl = config['url'];
          final title = config['title'];
          _config.complete(config);

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

    // Listen for messages
    _firebaseMessaging.configure(
      onMessage: (Map<String, dynamic> msg) {
        print('Got FCM message in foreground ${(msg)}');
        _handleRemoteMessage(msg, true);
      },
      onLaunch: (Map<String, dynamic> msg) {
        print('Pending FCM message on launch ${(msg)}');
        _handleRemoteMessage(msg, false);
      },
      onResume: (Map<String, dynamic> msg) {
        print('Pending FCM message on resume ${(msg)}');
        _handleRemoteMessage(msg, false);
      },
    );

    // Optionally subscribe to a FCM topic
    final fcmTopic = config['fcm_topic'];
    if (fcmTopic != null) {
      _firebaseMessaging.subscribeToTopic(fcmTopic);
    }

    // Listen for token updates
    _firebaseMessaging.onTokenRefresh.listen(_handleFcmToken);

    // Setup local notifications
    var initializationSettings = new InitializationSettings(
        new AndroidInitializationSettings('ic_notification'),
        new IOSInitializationSettings());
    _localNotifications.initialize(initializationSettings,
        onSelectNotification: (url) {
      _controller.future.then((controller) {
        controller.loadUrl(url);
      });
    });
  }

  void _handleFcmToken(token) {
    print('Got FCM token $token');
    _invokeJavascriptCallback('onFcmToken', token);
  }

  void _handleRemoteMessage(msg, showNotification) {
    print('Got remote message $msg');
    if (!msg.containsKey('notification') ||
        !msg.containsKey('data') ||
        !msg['notification'].containsKey('title') ||
        !msg['notification'].containsKey('body') ||
        !msg['data'].containsKey('url')) {
      print('Malformed remote message');
      return;
    }
    final url = msg['data']['url'];
    if (showNotification) {
      _config.future.then((config) {
        var androidDetails = new AndroidNotificationDetails(
            'main', config['title'], '',
            importance: Importance.Max, priority: Priority.High);
        var platformChannelSpecifics = new NotificationDetails(
            androidDetails, new IOSNotificationDetails());
        _localNotifications.show(0, msg['notification']['title'],
            msg['notification']['body'], platformChannelSpecifics,
            payload: url);
      });
    } else {
      _controller.future.then((controller) {
        controller.loadUrl(url);
      });
    }
  }

  // Expose native features to JavaScript code

  JavascriptChannel _nativeJavascriptChannel(BuildContext context) {
    return JavascriptChannel(
        name: 'FlutterHost',
        onMessageReceived: (JavascriptMessage message) {
          switch (message.message) {
            case 'fcmToken':
              _firebaseMessaging.getToken().then((token) {
                _invokeJavascriptCallback('onFcmToken', token);
              });
              break;
            case 'scanBarcode':
              _scanBarcode();
              break;
          }
        });
  }

  void _scanBarcode() async {
    try {
      String barcode = await BarcodeScanner.scan();
      _invokeJavascriptCallback('onBarcodeData', barcode);
    } on Exception catch (e) {
      _invokeJavascriptCallback('onBarcodeError', e.toString());
    }
  }

  void _invokeJavascriptCallback(function, arg) {
    _controller.future.then((controller) {
      String js = 'if (typeof $function === "function") $function("$arg")';
      controller.evaluateJavascript(js);
    });
  }
}
