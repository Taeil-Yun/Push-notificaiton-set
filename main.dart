import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_cookie_manager/webview_cookie_manager.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

Future<void> main() async {
  runApp(AppRunner());
}

class AppRunner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  HomePage({Key key}) : super(key: key);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  static const tokenPlatform = const MethodChannel('example.flutter.apns/token');

  String tokenAPNS = '';

  Future<void> getAPNsTokens() async {
    String token;

    try {
      final String result = await tokenPlatform.invokeMethod('getAPNsToken');
      token = '$result';
    } on PlatformException catch (e) {
      token = "Failed to get APNs Token: '${e.message}'";
    }

    setState(() {
      tokenAPNS = token;
      print('akakakalakdlaskdlasdk: $tokenAPNS');
    });
  }

  @override
  void initState() {
    super.initState();

    if(Platform.isAndroid) {
      firebaseCloudMessagingListener();
    }
    getAPNsTokens();
  }

  void firebaseCloudMessagingListener() {
    FirebaseMessaging.instance.getToken().then((token){
      print('token: '+token);
    });

    // 앱이 포그라운드에 있는 경우 사용자가 알림을 누를 때
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {

    });

    // 앱이 백그라운드, 종료 된 경우 사용자가 알림을 누를 때
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {

    });

    // 앱이 백그라운드, 종료될 때 트리거 할 백그라운드 메시지 핸들러
    FirebaseMessaging.onBackgroundMessage((message) {

    });
  }

  @override
  void setState(fn) {
    super.setState(fn);
  }

  // 일정시간마다 cookie 리스트 가져오기
  void webViewGetCookie() {
    final cookieManager = WebviewCookieManager();

    Stream.periodic(Duration(seconds: 30)).listen((event) async {
      final gotCookies = await cookieManager.getCookies('your site');

      for (var item in gotCookies) {
        // print('cookies = $item');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    webViewGetCookie();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: WebView(
          initialUrl: 'your site',
          javascriptMode: JavascriptMode.unrestricted,
          gestureNavigationEnabled: true,
        ),
      ),
    );
  }
}
