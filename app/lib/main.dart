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
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webview_plugin/flutter_webview_plugin.dart';
import 'package:yaml/yaml.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:barcode_scan/barcode_scan.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'hex_color.dart';

void main() => runApp(WebApp());

class WebApp extends StatelessWidget {
  static const String CONFIG = 'assets/config.yaml';
  static const String MESSAGE_PREFIX = 'flutterHost';

  final FlutterWebviewPlugin _webviewPlugin = new FlutterWebviewPlugin();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging();
  final FlutterLocalNotificationsPlugin _localNotifications =
      new FlutterLocalNotificationsPlugin();
  final Completer<Map> _config = Completer<Map>();

  String _initialUrl, _displayedUrl;

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
          _initialUrl = config['url'];
          final title = config['title'];
          if (!_config.isCompleted) {
            _config.complete(config);
          }

          // Setup app bar
          Widget appBar = PlaceholderAppBar(Color.fromARGB(1, 1, 1, 1));
          ThemeData themeData = ThemeData();
          if (config['app_bar'] != null) {
            if (config['app_bar']['visible']) {
              appBar = AppBar(title: Text(title));
            }
            final hexColor = config['app_bar']['color'];
            if (hexColor != null) {
              final color = HexColor(hexColor);
              themeData = ThemeData(primaryColor: color);
              appBar = PlaceholderAppBar(color);
            }
          }

          // Setup remote notifications
          if (config['notifications']) {
            _enableRemoteNotifications(config);
          }

          // Setup local notifications
          var initializationSettings = new InitializationSettings(
              new AndroidInitializationSettings('ic_notification'),
              new IOSInitializationSettings());
          _localNotifications.initialize(initializationSettings,
              onSelectNotification: (url) {
            if (url != null) {
              _webviewPlugin.reloadUrl(url);
            }
          });

          // Trigger native geolocation permission request if needed
          if (config['geolocation']) {
            Geolocator()
                .getLastKnownPosition(desiredAccuracy: LocationAccuracy.high);
          }

          // Setup js->flutter bridge
          _webviewPlugin.onUrlChanged.listen((String url) {
            _displayedUrl = url;
            String fragment = Uri.parse(url).fragment;
            if (fragment.startsWith(MESSAGE_PREFIX)) {
              String message = fragment.substring(MESSAGE_PREFIX.length + 1);
              _onJavascriptMessage(message);
            }
          });

          // Android: make sure app exits when there is no web history left and user pressed back
         _webviewPlugin.onBack.listen((_) {
           if (_displayedUrl == _initialUrl) {
            SystemNavigator.pop();
           }
         });

          // Build application
          return MaterialApp(
              title: title,
              theme: themeData,
              home: Scaffold(
                primary: true,
                appBar: appBar,
                body: WebviewScaffold(
                  url: _initialUrl,
                  primary: true,
                  geolocationEnabled: true,
              )
            )  
          );
        });
  }

  void _enableRemoteNotifications(config) {
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

    // Listen for token updates, will also trigger callback now
    _firebaseMessaging.onTokenRefresh.listen(_handleFcmToken);
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
      _webviewPlugin.launch(url);
    }
  }

  // Expose native features to JavaScript code

  void _onJavascriptMessage(String message) {
    _webviewPlugin.evalJavascript('_messageArgs').then((jsonArgs) {
      _webviewPlugin.evalJavascript('_messageArgs = "{}";');
      var args;
      try {
        if (Platform.isAndroid) {
          // flutter_webview_plugin bug?
          jsonArgs = jsonArgs.replaceAll(new RegExp(r'\\\"'), "\"");
          jsonArgs = jsonArgs.substring(1, jsonArgs.length - 1);
        }
        args = json.decode(jsonArgs);
      } on FormatException catch (e) {
        args = {};
      }
      switch (message) {
        case 'scheduleNotification':
          _scheduleLocalNotification(args['id'], args['title'], args['body'],
              DateTime.parse(args['date']));
          break;
        case 'unscheduleNotification':
          _unscheduleLocalNotification(args['id']);
          break;
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

  void _scheduleLocalNotification(id, title, body, date) {
    _config.future.then((config) {
      final androidDetails = new AndroidNotificationDetails(
          'main', config['title'], '',
          importance: Importance.Max, priority: Priority.High);
      NotificationDetails platformChannelSpecifics =
          new NotificationDetails(androidDetails, IOSNotificationDetails());
      _localNotifications.schedule(
          id, title, body, date, platformChannelSpecifics);
    });
  }

  void _unscheduleLocalNotification(id) {
    _localNotifications.cancel(id);
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
    String js = 'if (typeof $function === "function") $function("$arg")';
    _webviewPlugin.evalJavascript(js);
  }
}

class PlaceholderAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Color color;
  
  PlaceholderAppBar(this.color);

  @override
  Widget build(BuildContext context) {
    return Container(color: color);
  }
  
  @override
  Size get preferredSize => Size(0.0,0.0);
}
