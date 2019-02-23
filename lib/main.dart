import 'package:flutter/material.dart';
import 'package:flutter_webview_plugin/flutter_webview_plugin.dart';
import 'package:yaml/yaml.dart';
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
        // Build application
        return MaterialApp(
          title: title,
          theme: themeData,
          home: WebviewScaffold(url: url, appBar: appBar)
        );
      }            
    );
  }
}
