import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/auth/sign_in_screen.dart';
import 'screens/auth/sign_up_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'screens/new_chat_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/boost_center_screen.dart';
import 'screens/main_screen.dart';
import 'services/auth_wrapper.dart';
import 'services/appwrite_service.dart';
import 'services/storage_service.dart';
import 'services/avatar_cache.dart';
import 'services/feed_prefetcher.dart';
import 'providers/theme_provider.dart';

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Silence red error UI in release builds.
  FlutterError.onError = (FlutterErrorDetails details) {
    if (kReleaseMode) {
      // In release, avoid showing error overlays; just log.
      Zone.current.handleUncaughtError(
        details.exception,
        details.stack ?? StackTrace.empty,
      );
    } else {
      FlutterError.presentError(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (!kReleaseMode) {
      FlutterError.presentError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    }
    return true;
  };
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }
  // Opt into edge-to-edge for Android 15+ and earlier versions.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  await _bootstrapServices();

  runApp(const XapZapApp());
  // Remove splash quickly (1 second cap), regardless of long inits.
  if (!kIsWeb) {
    Future<void>.delayed(const Duration(seconds: 1), () {
      FlutterNativeSplash.remove();
    });
  }
}

Future<void> _bootstrapServices() async {
  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {}
  try {
    await AppwriteService.initialize();
  } catch (_) {}
  try {
    await WasabiService.initialize();
  } catch (_) {}
  try {
    await AvatarCache.initialize();
  } catch (_) {}
  if (!kIsWeb) {
    try {
      MobileAds.instance.initialize();
    } catch (_) {}
  }
  // Start preloading the home feeds in the background so that
  // the HomeScreen can render instantly when opened.
  // On web we skip this to reduce first-load work and rely on
  // HomeScreen to fetch lazily when it mounts.
  if (!kIsWeb) {
    FeedPrefetcher.preloadHomeFeeds();
  }
}

class XapZapApp extends StatelessWidget {
  const XapZapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'XapZap',
            scrollBehavior: const MaterialScrollBehavior().copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
                PointerDeviceKind.stylus,
              },
            ),
            builder: (context, child) {
              final theme = Theme.of(context);
              final overlayStyle = theme.brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light.copyWith(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor: theme.scaffoldBackgroundColor,
                      systemNavigationBarDividerColor:
                          theme.scaffoldBackgroundColor,
                    )
                  : SystemUiOverlayStyle.dark.copyWith(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor: theme.scaffoldBackgroundColor,
                      systemNavigationBarDividerColor:
                          theme.scaffoldBackgroundColor,
                    );
              // On web/desktop, let the app use full width with no global centering.
              if (kIsWeb) {
                return AnnotatedRegion<SystemUiOverlayStyle>(
                  value: overlayStyle,
                  child: child ?? const SizedBox.shrink(),
                );
              }
              // On mobile, keep safe areas and optional max-width centering.
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: overlayStyle,
                child: Container(
                  color: theme.scaffoldBackgroundColor,
                  child: SafeArea(
                    top: true,
                    bottom: true,
                    left: false,
                    right: false,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxWidth = constraints.maxWidth > 1200
                            ? 1200.0
                            : constraints.maxWidth;
                        return Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxWidth),
                            child: child ?? const SizedBox.shrink(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
            theme: ThemeData(
              brightness: Brightness.light,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF1DA1F2),
                brightness: Brightness.light,
              ),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF1DA1F2),
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
            ),
            themeMode: themeProvider.themeMode,
            home: const DecisionScreen(),
            routes: {
              '/main': (context) =>
                  kIsWeb ? const MainScreen() : const AuthWrapper(),
              '/signin': (context) => const SignInScreen(),
              '/signup': (context) => const SignUpScreen(),
              '/privacy': (context) => const PrivacyPolicyScreen(),
              '/new_chat': (context) => const NewChatScreen(),
              '/admin': (context) => const AdminDashboardScreen(),
              '/boosts': (context) => const BoostCenterScreen(),
            },
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

class DecisionScreen extends StatefulWidget {
  const DecisionScreen({super.key});

  @override
  State<DecisionScreen> createState() => _DecisionScreenState();
}

class _DecisionScreenState extends State<DecisionScreen> {
  bool _hasAcceptedPolicy = false;
  bool _checkedAuth = false;

  @override
  void initState() {
    super.initState();
    _checkPolicy();
  }

  Future<void> _checkPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hasAcceptedPolicy = prefs.getBool('has_accepted_policy') ?? false;
      _checkedAuth = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedAuth) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasAcceptedPolicy) {
      return const PrivacyPolicyScreen();
    }
    // On web, let users browse as guests without forcing app-based auth.
    if (kIsWeb) {
      return const MainScreen();
    }
    return const AuthWrapper();
  }
}
