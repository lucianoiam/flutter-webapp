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

import 'package:flutter/material.dart';
import 'package:flutter_webview_plugin/flutter_webview_plugin.dart';
import 'package:yaml/yaml.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'hex_color.dart';

void main() => runApp(WebApp());

class WebApp extends StatelessWidget {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging();

  @override
  Widget build(BuildContext context) {
    // Load configuration
    return FutureBuilder(
      future: DefaultAssetBundle.of(context).loadString('assets/config.yaml'),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        // Parse configuration
        final config = loadYaml(snapshot.data);
        final url = config['url'];
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
          enableNotifications(config);
        }

        // Trigger native geolocation permission request if needed
        if (config['geolocation']) {
          Geolocator().getLastKnownPosition(desiredAccuracy: LocationAccuracy.high);
        }

        // Build application
        return MaterialApp(
          title: title,
          theme: themeData,
          home: WebviewScaffold(
            url: url,
            geolocationEnabled: true,
            appBar: appBar,
            hidden: true
          )
        );
      }            
    );
  }

  void enableNotifications(config) {
    // Request notifications permission on iOS
    _firebaseMessaging.requestNotificationPermissions();
    _firebaseMessaging.configure( onMessage: (Map<String, dynamic> msg) {
      print("FCM MESSAGE: ${(msg)}");  // FIXME
    });

    // Listen for token updates
    Stream<String> fcmStream = _firebaseMessaging.onTokenRefresh;
    fcmStream.listen((token) {
      print("FCM TOKEN IS: $token");  // FIXME
    });

    // Optionally subscribe to a FCM topic
    final fcmTopic = config['fcm_topic'];
    if (fcmTopic != null) {
      _firebaseMessaging.subscribeToTopic(fcmTopic);
    }
  }
}
