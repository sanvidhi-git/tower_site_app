// Renders the real app screens into PNGs (screenshots/), fed with API responses captured
// from a demo ERPNext site (test/fixtures/api.json). Only the server is faked.
// Run: flutter test test/screenshots_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:sanvidhi_site/core/api.dart';
import 'package:sanvidhi_site/core/brand.dart';
import 'package:sanvidhi_site/core/session.dart';
import 'package:sanvidhi_site/screens/daily_report_screen.dart';
import 'package:sanvidhi_site/screens/home_shell.dart';
import 'package:sanvidhi_site/screens/login_screen.dart';
import 'package:sanvidhi_site/screens/receipt_screen.dart';
import 'package:sanvidhi_site/screens/site_screen.dart';
import 'package:sanvidhi_site/screens/submission_screen.dart';
import 'package:sanvidhi_site/services/location.dart';
import 'package:sanvidhi_site/services/outbox.dart';

late Map<String, dynamic> api;

class FakeErp implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    var key = o.path.split('mobile_api.').last.split('?').first;
    if (key == 'get_submission') {
      key = o.queryParameters['doctype'] == 'Daily Site Report' ? 'get_submission_dsr' : 'get_submission_smr';
    }
    if (key.startsWith('submit_')) {
      // the phone is "offline": queued reports stay waiting
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
    }
    if (!api.containsKey(key)) {
      return ResponseBody.fromString(jsonEncode({'exception': 'No fixture for $key'}), 404,
          headers: {Headers.contentTypeHeader: ['application/json']});
    }
    return ResponseBody.fromString(jsonEncode({'message': api[key]}), 200,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

ThemeData theme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Brand.purple),
      cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6)),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );

Future<void> loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT']!;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> f(String n) async => ByteData.view(Uint8List.fromList(File('$dir/$n').readAsBytesSync()).buffer);
  final roboto = FontLoader('Roboto');
  for (final n in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Light.ttf']) {
    if (File('$dir/$n').existsSync()) roboto.addFont(f(n));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(f('MaterialIcons-Regular.otf'));
  await icons.load();
}

final rootKey = GlobalKey();
late Session session;

Widget app(Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: Outbox.instance),
      ],
      child: RepaintBoundary(
        key: rootKey,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: theme(), home: home),
      ),
    );

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      // real-time timeout: a stalled image load must never hang the whole run
      await precacheImage((e.widget as Image).image, e)
          .timeout(const Duration(seconds: 5), onTimeout: () {});
    }
  });
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

Future<void> shot(WidgetTester t, String name) async {
  await settle(t);
  await t.runAsync(() async {
    final boundary = rootKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('screenshots/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> finish(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(minutes: 5)); // drain timers (http timeouts, debounce)
  debugDisableShadows = true; // the test binding checks it is restored
}

void signIn() {
  session = Session()
    ..debugSignIn(
      user: 'santosh@towerdemo.local',
      server: 'https://erp.yourcompany.com',
      boot: Map<String, dynamic>.from(api['bootstrap'] as Map),
    );
}

Map<String, dynamic> get siteDetail => Map<String, dynamic>.from(api['site_detail'] as Map);
String get siteId => (siteDetail['site'] as Map)['name'] as String;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadFonts();
    api = Map<String, dynamic>.from(jsonDecode(File('test/fixtures/api.json').readAsStringSync()) as Map);
    ApiClient.instance.configure(baseUrl: 'https://erp.yourcompany.com', apiKey: 'k', apiSecret: 's');
    ApiClient.instance.dio.httpClientAdapter = FakeErp();
    // decode on this isolate: the default transformer uses a background isolate for large
    // responses, which never completes inside the fake-async test zone
    ApiClient.instance.dio.transformer = SyncTransformer();
    LocationService.debugPosition = Position(
      latitude: 19.4123, longitude: 72.8311, timestamp: DateTime.now(), accuracy: 6, altitude: 12,
      altitudeAccuracy: 3, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
  });

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2340);
    view.devicePixelRatio = 2.625;
    debugDisableShadows = false; // real shadows in the screenshots
  });

  testWidgets('01 login', (t) async {
    session = Session()
      ..ready = true
      ..serverUrl = 'erp.yourcompany.com';
    await t.pumpWidget(app(const LoginScreen()));
    await t.enterText(find.byType(TextFormField).at(1), 'santosh@towerdemo.local');
    await t.enterText(find.byType(TextFormField).at(2), 'secret-pass');
    FocusManager.instance.primaryFocus?.unfocus();
    await shot(t, '01_login');
    await finish(t);
  });

  testWidgets('02 my sites + tabs', (t) async {
    signIn();
    await t.pumpWidget(app(const HomeShell()));
    await shot(t, '02_my_sites');
    session.offline = true;
    Outbox.instance.debugAdd(OutboxItem(
      ref: 'demo-1', kind: OutboxKind.dailyReport, site: 'IN-DM0021', title: 'Excavation for tower foundation pits',
      created: DateTime.now().subtract(const Duration(minutes: 25)), payload: const {}));
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Submissions')));
    await shot(t, '07_submissions_offline_queue');
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Me')));
    await shot(t, '08_me');
    Outbox.instance.debugClear();
    await finish(t);
  });

  testWidgets('03 site detail', (t) async {
    signIn();
    final site = session.sites.firstWhere((s) => s['name'] == siteId);
    await t.pumpWidget(app(SiteScreen(site: site)));
    await shot(t, '03_site_detail');
    await t.drag(find.byType(ListView).first, const Offset(0, -900));
    await shot(t, '03b_site_milestones_boq');
    await finish(t);
  });

  testWidgets('04 daily report', (t) async {
    signIn();
    await t.pumpWidget(app(DailyReportScreen(siteId: siteId, detail: siteDetail)));
    await settle(t);
    await t.enterText(find.byType(TextFormField).at(0), '8');
    await t.enterText(find.byType(TextFormField).at(1), 'OD BTS slab casting completed, curing started');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.tap(find.text('Add BOQ item'));
    await settle(t);
    await t.tap(find.byType(ListTile).first);
    await settle(t);
    await t.enterText(find.widgetWithText(TextFormField, 'Today'), '4.5');
    FocusManager.instance.primaryFocus?.unfocus();
    await shot(t, '04_daily_report');
    await t.drag(find.byType(ListView).first, const Offset(0, -700));
    await t.tap(find.text('Add expense'));
    await settle(t);
    await shot(t, '04b_daily_report_expenses');
    await finish(t);
  });

  testWidgets('05 receipt against PO', (t) async {
    signIn();
    await t.pumpWidget(app(ReceiptScreen(siteId: siteId, detail: siteDetail)));
    await settle(t);
    final po = (siteDetail['open_pos'] as List).first as Map;
    await t.tap(find.byType(DropdownButtonFormField<String>).first);
    await settle(t);
    await t.tap(find.text('${po['name']} · ${po['supplier_name']}').last);
    await settle(t);
    await t.enterText(find.byType(TextFormField).at(0), 'OSE/1182');
    await t.enterText(find.byType(TextFormField).at(1), 'MH48 BK 4471');
    FocusManager.instance.primaryFocus?.unfocus();
    await shot(t, '05_receipt_vendor_po');
    await finish(t);
  });

  testWidgets('06 receipt Indus material', (t) async {
    signIn();
    await t.pumpWidget(app(ReceiptScreen(siteId: siteId, detail: siteDetail)));
    await settle(t);
    await t.tap(find.text('Indus material'));
    await settle(t);
    await t.enterText(find.byType(TextFormField).at(0), 'MAW - Pune Warehouse');
    await t.enterText(find.byType(TextFormField).at(1), 'INDUS/DC/55871');
    await t.tap(find.text('Add Indus material'));
    await settle(t);
    await t.enterText(find.widgetWithText(TextFormField, 'Description (as on Indus DC)'), 'SMPS 12kW with MPPT');
    await t.enterText(find.widgetWithText(TextFormField, 'Received'), '1');
    await t.enterText(find.widgetWithText(TextFormField, 'Serial nos (one per line)'), 'SMPS-77812');
    FocusManager.instance.primaryFocus?.unfocus();
    await shot(t, '06_receipt_indus_material');
    await finish(t);
  });
  testWidgets('09 open a submission from the list', (t) async {
    signIn();
    await t.pumpWidget(app(const HomeShell()));
    await settle(t);
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Submissions')));
    await settle(t);
    final dsr = (api['get_submission_dsr'] as Map)['name'] as String;
    await t.tap(find.textContaining(dsr).first);
    await shot(t, '09_submission_daily_report');
    await t.drag(find.byType(ListView).last, const Offset(0, -800));
    await shot(t, '09b_submission_daily_report_more');
    await finish(t);
  });

  testWidgets('10 material receipt detail', (t) async {
    signIn();
    final smr = api['get_submission_smr'] as Map;
    await t.pumpWidget(app(SubmissionScreen(doctype: 'Site Material Receipt', name: smr['name'] as String)));
    await shot(t, '10_submission_material_receipt');
    await finish(t);
  });

  testWidgets('11 report still on the phone', (t) async {
    signIn();
    final item = OutboxItem(
      ref: 'demo-2', kind: OutboxKind.dailyReport, site: siteId, title: 'Backfilling',
      created: DateTime.now().subtract(const Duration(minutes: 40)),
      payload: {
        'tower_site': siteId, 'report_date': '2026-11-03', 'labour_count': 7, 'milestone_achieved': null,
        'work_completed': 'Backfilling in layers with compaction around tower foundation',
        'work_items': [
          {'item_code': 'DM-25-BACKFILL', 'description': 'Backfilling in layers with compaction', 'uom': 'Cubic Meter', 'qty_completed': 12.5}
        ],
        'materials': [],
        'expenses': [
          {'expense_type': 'Labour Wages', 'amount': 4550, 'paid_to': 'Labour contractor'}
        ],
        'photos': [],
        'pending_work': 'Earth resistance test',
        'latitude': 19.2964, 'longitude': 73.0631,
      });
    await t.pumpWidget(app(SubmissionScreen.local(item: item)));
    await shot(t, '11_submission_on_phone');
    await finish(t);
  });
}
