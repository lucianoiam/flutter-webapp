/*
 * Copyright 2018 Luciano Iam <lucianito@gmail.com>
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
import 'hex_color.dart';

void main() => runApp(WebApp());

class WebApp extends StatelessWidget {
  // This widget is the root of your application.
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
        var appBar, themeData;
        if (config['app_bar']['visible']) {
          appBar = AppBar(title: Text(title));
          final color = HexColor(config['app_bar']['color']);
          themeData = ThemeData(primaryColor: color);
        }
        if (config['geolocation']) {
          // Use geolocator plugin to trigger native permission request
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
}
