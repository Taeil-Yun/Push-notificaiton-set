import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:firebase_analytics/observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_cookie_manager/webview_cookie_manager.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';

// Google Analytics
FirebaseAnalytics analytics = FirebaseAnalytics();

// 앱이 백그라운드에 있을 때
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  print('Handling a background message ${message.data}');
}

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel', // id
  'High Importance Notifications', // title
  'This channel is used for important notifications.', // description
  importance: Importance.high,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  if(Platform.isAndroid) {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  runApp(AppRunner());
}

class AppRunner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      home: HomePage(),
      navigatorObservers: [
        FirebaseAnalyticsObserver(analytics: analytics),
      ],
    );
  }
}

class HomePage extends StatefulWidget {
  HomePage({Key key}) : super(key: key);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  // 웹 뷰 컨트롤러
  final Completer<WebViewController> _webViewController = Completer<WebViewController>();

  // APNs 토큰 채널
  static const tokenPlatform = const MethodChannel('example.flutter.apns/token');

  // device token key 값 암호화
  var digest = Platform.isIOS ? sha256.convert(utf8.encode("example-example1ios")).toString().substring(0, 32)
                              : sha256.convert(utf8.encode("example-example1android")).toString().substring(0, 32);

  List cookieValue = [];

  String userID = '';
  String tokenAPNS = '';
  String tokenFCM = '';

  int selectIndex = 0;

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
      tokenAPNS = tokenAPNS.split('"')[1];
    });
  }

  @override
  void initState() {
    super.initState();

    if(Platform.isAndroid) {
      firebaseCloudMessagingListener();
    } else {
      getAPNsTokens();
    }
  }

  void firebaseCloudMessagingListener() {
    // fcm token 얻기
    FirebaseMessaging.instance.getToken().then((token){
      print('FCM token: $token');
      return tokenFCM = token;
    });

    // 앱이 종료되어있을 때 푸시가 오면 실행
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message.data.containsKey("_link")) {
        _webViewController.future.then((value) {
          value.loadUrl(message.data.values.first);
        });
      }
    });

    // 앱이 포그라운드에 있을 때
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification notification = message.notification;
      AndroidNotification android = message.notification?.android;

      if (notification != null && android != null) {
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channel.description,
              icon: 'launch_background',
            ),
          )
        );
      }

      // 앱이 포그라운드에 있으면서 푸시를 클릭하였을 때 호출
      var adn = AndroidInitializationSettings('app_icon');
      var initializationSettings = InitializationSettings(android: adn);
      flutterLocalNotificationsPlugin.initialize(initializationSettings, onSelectNotification: (payload) {
        if(message.data.containsKey("_link")) {
          _webViewController.future.then((value) {
            value.loadUrl(message.data.values.first);
          });
        }
      });
    });

    // 앱이 실행되고 있을 때 푸시를 클릭하면 호출되는 이벤트
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if(message.data.containsKey("_link")) {
        _webViewController.future.then((value) {
          value.loadUrl(message.data.values.first);
        });
      }
    });
  }

  // 일정시간마다 cookie 리스트 가져오기
  void webViewGetCookie() {
    final cookieManager = WebviewCookieManager();
    Stream.periodic(Duration(seconds: 30)).listen((event) async {
      cookieValue.clear();
      final gotCookies = await cookieManager.getCookies('https://your site');

      if(userID == null || userID == '') {
        for (var item in gotCookies) {
          cookieValue.add(item.toString());
        }

        for (var i = 0; i < cookieValue.length; i++) {
          if (cookieValue[i].toString().contains("UserID=") &&
              cookieValue[i].toString().contains("Domain=your site;")) {
            setState(() {
              userID = cookieValue[i].toString().substring(7).split(";")[0];
            });
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    webViewGetCookie();

    final tokenEncryptKey = encrypt.Key.fromUtf8(digest);
    final tokenEncryptIV = encrypt.IV.fromUtf8(digest.substring(0, 16));
    final dataEncrypter = encrypt.Encrypter(encrypt.AES(tokenEncryptKey, mode: encrypt.AESMode.cbc));
    final dataEncrypted = dataEncrypter.encrypt("${userID!=null?userID:''};${Platform.isIOS ? tokenAPNS.toLowerCase() : tokenFCM}", iv: tokenEncryptIV).base64;

    setState(() {
      if(userID != null || userID != '') {
        DeviceInformationRequest().requestData(dataEncrypted);
      }
    });

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Container(
          child: WebView(
            initialUrl: 'https://your site',
            javascriptMode: JavascriptMode.unrestricted,
            gestureNavigationEnabled: true,
            onWebViewCreated: (WebViewController webViewController) {
              _webViewController.complete(webViewController);
            },
          ),
        ),
      ),
      bottomNavigationBar: FutureBuilder<WebViewController>(
        future: _webViewController.future,
        builder: (BuildContext context, AsyncSnapshot<WebViewController> controller) {
          if(controller.hasData) {
            return BottomNavigationBar(
              items: [
                BottomNavigationBarItem(icon: Icon(Icons.arrow_back), label: "", backgroundColor: Color(0xFF000000)),
                BottomNavigationBarItem(icon: Icon(Icons.arrow_forward), label: "", backgroundColor: Color(0xFF000000)),
                BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: "", backgroundColor: Color(0xFF000000)),
                BottomNavigationBarItem(icon: Icon(Icons.refresh), label: "", backgroundColor: Color(0xFF000000)),
                BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), label: "", backgroundColor: Color(0xFF000000)),
                BottomNavigationBarItem(icon: Icon(Icons.share_outlined), label: "", backgroundColor: Color(0xFF000000)),
                BottomNavigationBarItem(icon: Icon(Icons.notifications_none_outlined), label: "", backgroundColor: Color(0xFF000000)),
                BottomNavigationBarItem(icon: Icon(Icons.more_horiz_outlined), label: "", backgroundColor: Color(0xFF000000)),
              ],
              onTap: (index) {
                switch(index) {
                  case 0:
                    controller.data.goBack();
                    break;
                  case 1:
                    controller.data.goForward();
                    break;
                  case 2:
                    controller.data.loadUrl("https://your site");
                    break;
                  case 3:
                    controller.data.reload();
                    break;
                  case 4:
                    controller.data.loadUrl("https://your site/page");
                    break;
                  case 5:
                    break;
                  case 6:
                    break;
                  case 7:
                    break;
                }
              },
              elevation: 0.0,
              selectedFontSize: 0,
            );
          }
          return BottomNavigationBar(
            items: [
              BottomNavigationBarItem(icon: Icon(Icons.arrow_back), label: "", backgroundColor: Color(0xFF000000)),
              BottomNavigationBarItem(icon: Icon(Icons.arrow_forward), label: "", backgroundColor: Color(0xFF000000)),
              BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: "", backgroundColor: Color(0xFF000000)),
              BottomNavigationBarItem(icon: Icon(Icons.refresh), label: "", backgroundColor: Color(0xFF000000)),
              BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), label: "", backgroundColor: Color(0xFF000000)),
              BottomNavigationBarItem(icon: Icon(Icons.share_outlined), label: "", backgroundColor: Color(0xFF000000)),
              BottomNavigationBarItem(icon: Icon(Icons.notifications_none_outlined), label: "", backgroundColor: Color(0xFF000000)),
              BottomNavigationBarItem(icon: Icon(Icons.more_horiz_outlined), label: "", backgroundColor: Color(0xFF000000)),
            ],
            elevation: 0.0,
          );
        },
      ),
    );
  }
}

class DeviceInformationRequest {
  final baseUrl = 'http://your ip/your uri';

  Future<DeviceInfoRequestModel> requestData(String cryptData) async {
    final deviceType = Platform.isIOS ? 'ios' : 'android';

    final request = await http.post(
        Uri.parse(baseUrl),
        body: {
          'appCode': '1',
          'deviceType': deviceType,
          'crypto': cryptData
        }
    );

    if(request.statusCode == 200) {
      print('data: ${DeviceInfoRequestModel.fromJson(json.decode(request.body))}');

      return DeviceInfoRequestModel.fromJson(json.decode(request.body));
    } else {
      print('data ${request.body}');
      throw Exception('failed to load data');
    }
  }
}

class DeviceInfoRequestModel {
  final String deviceToken, status;

  DeviceInfoRequestModel({this.deviceToken, this.status});

  factory DeviceInfoRequestModel.fromJson(Map<String, dynamic> json) {
    return DeviceInfoRequestModel(
      deviceToken: json['deviceToken'] != null ? json['deviceToken'] : '',
      status: json['status'] != null ? json['status'] : '',
    );
  }
}
