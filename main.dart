import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_cookie_manager/webview_cookie_manager.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_analytics/observer.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_dynamic_links/firebase_dynamic_links.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
// import 'package:splashscreen/splashscreen.dart';
import 'package:new_version/new_version.dart';
import 'package:url_launcher/url_launcher.dart';

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

    await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
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
      color: Color(0xFF383837),
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

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  // 웹 뷰 컨트롤러
  final Completer<WebViewController> _webViewController = Completer<WebViewController>();

  // APNs 토큰 채널
  static const tokenPlatform = const MethodChannel('example.flutter.apns/token');

  // device token key 값 암호화
  var digest = Platform.isIOS
      ? sha256.convert(utf8.encode("your key for ios")).toString().substring(0, 32)
      : sha256.convert(utf8.encode("your key for android")).toString().substring(0, 32);

  final newVersion = NewVersion(
    androidId: "your bundle name",
    iOSId: "your bundle name",
    iOSAppStoreCountry: "use country"
  );
  bool appCanUpdate;
  String appLocalVersion;
  String appStoreVersion;
  String appStoreUrl;

  List cookieValue = [];
  String userID = '';
  String tokenAPNS = '';
  String tokenFCM = '';
  int selectIndex = 0;
  bool showMoreBtn = false;
  bool notificationPermission = false;
  bool splashState = false;
  Image img = Image.network('');

  Future<void> getAPNsTokens() async {
    String token;

    try {
      final String result = await tokenPlatform.invokeMethod('getAPNsToken');
      token = '$result';
    } on PlatformException catch (e) {
      print("Failed to get APNs Token: '${e.message}'");
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

    checkNotificationPermission();

    FirebaseDynamicLinks.instance.getDynamicLink(Uri.parse("your firebase dynamic link url")).then((value) {
      img = Image.network('${value.link}');
      return img;
    });

    appVersionCheck();

    Future.delayed(Duration(seconds: 1)).then((value) {
      final tokenEncryptKey = encrypt.Key.fromUtf8(digest);
      final tokenEncryptIV = encrypt.IV.fromUtf8(digest.substring(0, 16));
      final dataEncrypt = encrypt.Encrypter(encrypt.AES(tokenEncryptKey, mode: encrypt.AESMode.cbc));
      final dataEncrypted = dataEncrypt.encrypt("${userID!=null?userID:''};${Platform.isIOS ? tokenAPNS.toLowerCase() : tokenFCM}", iv: tokenEncryptIV).base64;

      if(tokenAPNS != null && notificationPermission == true || tokenFCM != null && notificationPermission == true) {
        DeviceInformationRequest().requestData(dataEncrypted);
      } else {
        print('Device Token Null.');
      }
    });
  }

  // the app latest version checking in store
  Future<VersionStatus> appVersionCheck() async {
    final status = await newVersion.getVersionStatus();

    appCanUpdate = status.canUpdate; // (true)
    appLocalVersion = status.localVersion; // (1.2.1)
    appStoreVersion = status.storeVersion; // (1.2.3)
    appStoreUrl = status.appStoreLink; // (https://itunes.apple.com/us/app/google/id284815942?mt=8)

    return null;
  }

  void firebaseCloudMessagingListener() {
    // get fcm token
    FirebaseMessaging.instance.getToken().then((token){
      print('FCM token: $token');
      return tokenFCM = token;
    });

    // push execution when the app is closed
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message.data.containsKey("_link")) {
        _webViewController.future.then((value) {
          value.loadUrl(message.data.values.first);
        });
      }
    });

    // app on foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      RemoteNotification notification = message.notification;
      AndroidNotification android = message.notification?.android;

      // download when get image push
      Future<String> _downloadAndSaveFile(String url, String fileName) async {
        final Directory directory = await getApplicationDocumentsDirectory();
        final String filePath = '${directory.path}/$fileName';
        final http.Response response = await http.get(Uri.parse(url));
        final File file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      }

      final String largeIconPath = message.notification.android.imageUrl != null ? await _downloadAndSaveFile(
        message.notification.android.imageUrl,
        'largeIcon_${DateTime.now().millisecondsSinceEpoch.toString()}'
      ) : null;
      final String bigPicturePath = message.notification.android.imageUrl != null ? await _downloadAndSaveFile(
        message.notification.android.imageUrl,
        'bigPicture_${DateTime.now().millisecondsSinceEpoch.toString()}'
      ) : null;

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
              icon: 'drawable/ic_stat_app_icon2',
              largeIcon: message.notification.android.imageUrl != null ? FilePathAndroidBitmap(largeIconPath) : null,
              styleInformation: message.notification.android.imageUrl != null ? BigPictureStyleInformation(
                FilePathAndroidBitmap(bigPicturePath),
                largeIcon: FilePathAndroidBitmap(largeIconPath),
              ) : BigTextStyleInformation(
                message.notification.body,
              ),
            ),
          ),
        );
      }

      // 앱이 포그라운드에 있으면서 푸시를 클릭하였을 때 호출
      var adn = AndroidInitializationSettings('drawable/ic_stat_app_icon2');
      var initializationSettings = InitializationSettings(android: adn);
      flutterLocalNotificationsPlugin.initialize(initializationSettings, onSelectNotification: (payload) {
        if(message.data.containsKey("_link")) {
          _webViewController.future.then((value) {
            value.loadUrl(message.data.values.first);
          });
        }
        return ;
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
      final gotCookies = await cookieManager.getCookies('your web site');

      if(userID == null || userID == '') {
        for (var item in gotCookies) {
          cookieValue.add(item.toString());
        }

        for (var i = 0; i < cookieValue.length; i++) {
          if (cookieValue[i].toString().contains("UserID=") &&
              cookieValue[i].toString().contains("Domain=YOUR WEB SITE;")) {
            setState(() {
              userID = cookieValue[i].toString().substring(7).split(";")[0];

              if(userID != null || userID != '') {
                final tokenEncryptKey = encrypt.Key.fromUtf8(digest);
                final tokenEncryptIV = encrypt.IV.fromUtf8(digest.substring(0, 16));
                final dataEncrypter = encrypt.Encrypter(encrypt.AES(tokenEncryptKey, mode: encrypt.AESMode.cbc));
                final dataEncrypted = dataEncrypter.encrypt("${userID!=null?userID:''};${Platform.isIOS ? tokenAPNS.toLowerCase() : tokenFCM}", iv: tokenEncryptIV).base64;

                if(tokenAPNS != null && notificationPermission == true || tokenFCM != null && notificationPermission == true) {
                  DeviceInformationRequest().requestData(dataEncrypted);
                } else {
                  print('Device Token Null.');
                }
              } else {
                print('userID Null');
              }
            });
          }
        }
      }
    });

  }

  void getMoreContainer() {
    setState(() {
      showMoreBtn = !showMoreBtn;
    });
  }

  Future<void> checkNotificationPermission() async {
    var permissionStatus = await Permission.notification.status;

    if (permissionStatus.isGranted) {
      setState(() {
        notificationPermission = true;
      });
    } else {
      setState(() {
        notificationPermission = false;
      });
    }
  }

  void openAppSettingPage() {
    openAppSettings().then((value) {
      return value;
    });
  }

  @override
  Widget build(BuildContext context) {
    webViewGetCookie();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            showWebView(),
            showMoreBtn ? navigationMoreWrapper() : Container(),
            splashState == false ? secondSplashScreen() : Container(),
            splashState == true && appCanUpdate == true ? appUpdatePopUp() : Container(),
          ],
        ),
      ),
      bottomNavigationBar: splashState == true ? bottomNavigationWidget() : null,
    );
  }

  Widget showWebView() {
    return WebView(
      initialUrl: 'your web site',
      javascriptMode: JavascriptMode.unrestricted,
      gestureNavigationEnabled: true,
      onWebViewCreated: (WebViewController webViewController) {
        _webViewController.complete(webViewController);
      },
    );
  }

  Widget appUpdatePopUp() {
    return Container(
      width: MediaQuery.of(context).size.width,
      height: MediaQuery.of(context).size.height,
      color: Color(0xFF000000).withOpacity(0.3),
      child: Platform.isAndroid ? AlertDialog(
        title: Text(
          'text',
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'text',
          style: TextStyle(
            fontSize: 13.0,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              launch(appStoreUrl);
            },
            child: Text('アップデートする'),
          ),
        ],
      ) : Stack(
        children: [
          // true = available action / false = invalid action
          appUpdatePopUpDesignForIOS(false),
          appUpdatePopUpDesignForIOS(true),
        ],
      ),
    );
  }
    Widget appUpdatePopUpDesignForIOS(boolean) {
      if(boolean == false) {
        return CupertinoAlertDialog(
          title: Container(
            margin: EdgeInsets.only(bottom: 5.0),
            child: Text(
              'text',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          content: Text(
            'text',
            style: TextStyle(
              fontSize: 12.0,
            ),
          ),
          actions: [
            CupertinoDialogAction(
              child: Text(
                'text',
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      }
      return CupertinoAlertDialog(
        title: Container(
          margin: EdgeInsets.only(bottom: 5.0),
          child: Text(
            'text',
            style: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        content: Text(
          'text',
          style: TextStyle(
            fontSize: 12.0,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () {
              launch(appStoreUrl);
            },
            child: Text(
              'text',
              style: TextStyle(
                fontSize: 16.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    }

  Widget navigationMoreWrapper() {
    return AnimatedOpacity(
      opacity: showMoreBtn ? 1.0 : 0.0,
      duration: Duration(seconds: 1),
      child: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        color: Color(0xFF000000).withOpacity(0.4),
        child: Row(
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  showMoreBtn = false;
                });
              },
              child: Container(
                width: (MediaQuery.of(context).size.width / 5.2) - 21.0,
                height: MediaQuery.of(context).size.height,
                alignment: Alignment.topLeft,
                margin: EdgeInsets.only(
                  top: 20.0,
                  left: 10.0,
                ),
                child: Icon(
                  Icons.close,
                  color: Color(0xFFffffff),
                  size: 30.0,
                ),
              ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: showMoreBtn ? navigationMoreContainer() : Container(),
            )
          ],
        ),
      ),
    );
  }
    Widget navigationMoreContainer() {
      if(showMoreBtn) {
        return Container(
          width: MediaQuery.of(context).size.width / 1.2,
          height: MediaQuery.of(context).size.height,
          color: Color(0xFFffffff),
          child: Column(
            children: [
              Container(
                width: MediaQuery.of(context).size.width,
                height: 162.0,
                child: InkWell(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 1.0,
                          color: Color(0xFFeeeeee),
                        ),
                      ),
                      image: DecorationImage(
                          image: AssetImage("assets/img/02.jpg"),
                          fit: BoxFit.fill
                      ),
                    ),
                  ),
                  onTap: () {
                    _webViewController.future.then((value) {
                      value.loadUrl("your web site page url");
                    });
                    setState(() {
                      showMoreBtn = false;
                    });
                  },
                ),
              ),
              Container(
                width: MediaQuery.of(context).size.width,
                padding: EdgeInsets.symmetric(horizontal: 13.0),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 1.0,
                      color: Color(0xFFeeeeee),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      child: Text('text'),
                    ),
                    Container(
                      child: Platform.isAndroid
                      ? Switch(
                        value: notificationPermission,
                        onChanged: (value) {
                          openAppSettingPage();
                          Stream.periodic(Duration(seconds: 1)).listen((event) async {
                            Permission.notification.isGranted.then((value) {
                              setState(() {
                                notificationPermission = value;
                              });
                            });
                          });
                        },
                      )
                      : CupertinoSwitch(
                        value: notificationPermission,
                        onChanged: (value) {
                          openAppSettingPage();
                          Stream.periodic(Duration(seconds: 1)).listen((event) async {
                            Permission.notification.isGranted.then((value) {
                              setState(() {
                                notificationPermission = value;
                              });
                            });
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: MediaQuery.of(context).size.width,
                padding: EdgeInsets.all(13.0),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 1.0,
                      color: Color(0xFFeeeeee),
                    ),
                  ),
                ),
                child: InkWell(
                  child: Container(
                    child: Text('text'),
                  ),
                  onTap: () {
                    _webViewController.future.then((value) {
                      value.loadUrl("your web site page url");
                    });
                    setState(() {
                      showMoreBtn = false;
                    });
                  },
                ),
              ),
              Container(
                width: MediaQuery.of(context).size.width,
                padding: EdgeInsets.all(13.0),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 1.0,
                      color: Color(0xFFeeeeee),
                    ),
                  ),
                ),
                child: InkWell(
                  child: Container(
                    child: Text('text'),
                  ),
                  onTap: () {
                    _webViewController.future.then((value) {
                      value.loadUrl("your web site page url");
                    });
                    setState(() {
                      showMoreBtn = false;
                    });
                  },
                ),
              ),
              Container(
                width: MediaQuery.of(context).size.width,
                padding: EdgeInsets.all(13.0),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 1.0,
                      color: Color(0xFFeeeeee),
                    ),
                  ),
                ),
                child: InkWell(
                  child: Container(
                    child: Text('text'),
                  ),
                  onTap: () {
                    _webViewController.future.then((value) {
                      value.loadUrl("your web site page url");
                    });
                    setState(() {
                      showMoreBtn = false;
                    });
                  },
                ),
              ),
              Container(
                width: MediaQuery.of(context).size.width,
                padding: EdgeInsets.all(13.0),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 1.0,
                      color: Color(0xFFeeeeee),
                    ),
                  ),
                ),
                child: InkWell(
                  child: Container(
                    child: Text('text'),
                  ),
                  onTap: () {
                    _webViewController.future.then((value) {
                      value.loadUrl("your web site page url");
                    });
                    setState(() {
                      showMoreBtn = false;
                    });
                  },
                ),
              ),
              Container(
                width: MediaQuery.of(context).size.width,
                padding: EdgeInsets.all(13.0),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 1.0,
                      color: Color(0xFFeeeeee),
                    ),
                  ),
                ),
                child: InkWell(
                  child: Container(
                    child: Text('text'),
                  ),
                  onTap: () {
                    _webViewController.future.then((value) {
                      value.loadUrl("your web site page url");
                    });
                    setState(() {
                      showMoreBtn = false;
                    });
                  },
                ),
              ),
              notificationPermission == false ? Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: MediaQuery.of(context).size.width,
                    margin: EdgeInsets.fromLTRB(10.0, 0.0, 10.0, 10.0),
                    padding: EdgeInsets.symmetric(horizontal: 7.0, vertical: 10.0),
                    color: Color(0xFFdddddd),
                    child: Text(
                      'text',
                      style: TextStyle(
                        color: Color(0xFFff0000),
                      ),
                    ),
                  ),
                ),
              ) : Container(),
            ],
          ),
        );
      }
      return null;
    }

  Widget secondSplashScreen() {
    return FutureBuilder(
      future: Future.delayed(Duration(seconds: 2)).then((value) {
        setState(() {
          splashState = true;
        });
      }),
      builder: (context, snapshot) {
        return splashState == false ? Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          decoration: BoxDecoration(
            color: Color(0xFF383837),
            image: DecorationImage(
              image: img.image,
              fit: BoxFit.cover,
            ),
          ),
        ) : Container();
      },
    );
  }

  Widget bottomNavigationWidget() {
    return FutureBuilder<WebViewController>(
      future: _webViewController.future,
      builder: (BuildContext context, AsyncSnapshot<WebViewController> controller) {
        if(controller.hasData) {
          return BottomNavigationBar(
            items: [
              BottomNavigationBarItem(icon: Icon(Icons.arrow_back), label: ""),
              BottomNavigationBarItem(icon: Icon(Icons.arrow_forward), label: ""),
              BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: ""),
              BottomNavigationBarItem(icon: Icon(Icons.refresh), label: ""),
              BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), label: ""),
              // BottomNavigationBarItem(icon: Icon(Icons.share_outlined), label: ""),
              // BottomNavigationBarItem(icon: Icon(Icons.notifications_none_outlined), label: ""),
              BottomNavigationBarItem(icon: Icon(Icons.more_horiz_outlined), label: ""),
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
                  controller.data.loadUrl("your web site");
                  break;
                case 3:
                  controller.data.reload();
                  break;
                case 4:
                  controller.data.loadUrl("your web site page url");
                  break;
                case 5:
                  getMoreContainer();
                  break;
              // case 6:
              //   break;
              // case 7:
              //   getMoreContainer();
              //   break;
              }
            },
            elevation: 0.0,
            selectedFontSize: 0,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Color(0xFF383837),
            selectedItemColor: Color(0xFFffffff),
            unselectedItemColor: Color(0xFFffffff),
          );
        }
        return BottomNavigationBar(
          items: [
            BottomNavigationBarItem(icon: Icon(Icons.arrow_back), label: ""),
            BottomNavigationBarItem(icon: Icon(Icons.arrow_forward), label: ""),
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: ""),
            BottomNavigationBarItem(icon: Icon(Icons.refresh), label: ""),
            BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), label: ""),
            // BottomNavigationBarItem(icon: Icon(Icons.share_outlined), label: ""),
            // BottomNavigationBarItem(icon: Icon(Icons.notifications_none_outlined), label: ""),
            BottomNavigationBarItem(icon: Icon(Icons.more_horiz_outlined), label: ""),
          ],
          elevation: 0.0,
        );
      },
    );
  }

}

class DeviceInformationRequest {
  final baseUrl = 'http://your server IP/api url';

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
