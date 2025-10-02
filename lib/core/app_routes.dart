// lib/core/app_routes.dart
import 'package:flutter/material.dart';

import '../ui/screens/blocked_users_screen.dart';
import '../ui/screens/splash_screen.dart';
import '../ui/screens/sign_in_screen.dart';
import '../ui/screens/sign_up_screen.dart';
import '../ui/screens/shell.dart';
import '../ui/screens/contacts_screen.dart';
import '../ui/screens/chats_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/screens/new_group_screen.dart';
import '../ui/screens/thread_screen.dart' show ThreadArgs, ThreadScreen;
import '../ui/screens/call_screen.dart' show CallArgs, CallScreen;

// Call ringing screens
import '../ui/screens/outgoing_call_screen.dart' show OutgoingCallArgs, OutgoingCallScreen;
import '../ui/screens/incoming_call_screen.dart' show IncomingCallArgs, IncomingCallScreen;

// Contacts / friend features
import '../ui/screens/add_contact_screen.dart';
import '../ui/screens/my_code_screen.dart';
import '../ui/screens/qr_scan_screen.dart';
import '../ui/screens/edit_profile_screen.dart';

class AppRoutes {
  // REMOVE: navigatorKey here. We use pushNavKey from push_route_handler.dart in main.dart.
  // static final navigatorKey = GlobalKey<NavigatorState>();

  static const splash = '/';
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const shell = '/shell';

  static const contacts = '/contacts';
  static const chats = '/chats';
  static const news = "/post";
  static const settings = '/settings';
  static const newGroup = '/new-group';

  static const thread = '/thread';
  static const call = '/call';

  // Ringing flow
  static const outgoingCall = '/outgoing-call';
  static const incomingCall = '/incoming-call'; // <- keep hyphen form (matches your handler)

  static const addContact = '/add-contact';
  static const myCode = '/my-code';
  static const scanQr = '/scan-qr';
  static const blockedUsers = '/blocked-users';

  static const editProfile = '/edit-profile';


  static Route<dynamic> onGenerateRoute(RouteSettings s) {
    switch (s.name) {
      case splash:
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
          settings: const RouteSettings(name: splash),
        );

      case signIn:
        return MaterialPageRoute(
          builder: (_) => const SignInScreen(),
          settings: const RouteSettings(name: signIn),
        );

      case signUp:
        return MaterialPageRoute(
          builder: (_) => const SignUpScreen(),
          settings: const RouteSettings(name: signUp),
        );

      case shell:
        return MaterialPageRoute(
          builder: (_) => const Shell(),
          settings: const RouteSettings(name: shell),
        );

      case contacts:
        return MaterialPageRoute(
          builder: (_) => const ContactsScreen(),
          settings: const RouteSettings(name: contacts),
        );

      case chats:
        return MaterialPageRoute(
          builder: (_) => const ChatsScreen(),
          settings: const RouteSettings(name: chats),
        );

      case settings:
        return MaterialPageRoute(
          builder: (_) => const SettingsScreen(),
          settings: const RouteSettings(name: settings),
        );

      case newGroup:
        return MaterialPageRoute(
          builder: (_) => const NewGroupScreen(),
          settings: const RouteSettings(name: newGroup),
        );

      case thread: {
        final args = s.arguments;
        if (args is! ThreadArgs) {
          return _badArgs('Missing thread arguments', name: thread);
        }
        return MaterialPageRoute(
          builder: (_) => ThreadScreen(args: args),
          settings: const RouteSettings(name: thread),
        );
      }

      case call: {
        final args = s.arguments;
        if (args is! CallArgs) {
          return _badArgs('Missing call arguments (threadId required)', name: call);
        }
        return MaterialPageRoute(
          builder: (_) => CallScreen(args: args),
          settings: const RouteSettings(name: call),
        );
      }

    // ---- Ringing routes ----
      case outgoingCall: {
        final args = s.arguments;
        if (args is! OutgoingCallArgs) {
          return _badArgs('Missing outgoing call args', name: outgoingCall);
        }
        // Fullscreen so it sits above UI during setup
        return MaterialPageRoute(
          builder: (_) => OutgoingCallScreen(args: args),
          fullscreenDialog: true,
          settings: const RouteSettings(name: outgoingCall),
        );
      }

      case incomingCall: {
        final args = s.arguments;
        if (args is! IncomingCallArgs) {
          return _badArgs('Missing incoming call args', name: incomingCall);
        }
        // Fullscreen so it overlays when restored from notification tap (cold-start too)
        return MaterialPageRoute(
          builder: (_) => IncomingCallScreen(args: args),
          fullscreenDialog: true,
          settings: const RouteSettings(name: incomingCall),
        );
      }

      case blockedUsers:
        return MaterialPageRoute(
          builder: (_) => const BlockedUsersScreen(),
          settings: const RouteSettings(name: blockedUsers),
        );

      case addContact:
        String? initialContactCodeFromArgs;
        if (s.arguments is Map<String, dynamic>) {
          final args = s.arguments as Map<String, dynamic>;
          // Only try to extract 'initialContactCode' as that's what AddContactScreen now expects
          initialContactCodeFromArgs = args['initialContactCode'] as String?;
        }

        return MaterialPageRoute(
          builder: (_) => AddContactScreen(
            initialContactCode: initialContactCodeFromArgs,
          ),
          settings: const RouteSettings(name: addContact),
        );

      case myCode:
        return MaterialPageRoute(
          builder: (_) => const MyCodeScreen(),
          settings: const RouteSettings(name: myCode),
        );

      case scanQr:
        return MaterialPageRoute(
          builder: (_) => const QrScanScreen(),
          settings: const RouteSettings(name: scanQr),
        );

      case editProfile:
        return MaterialPageRoute(
          builder: (_) => const EditProfileScreen(),
          settings: const RouteSettings(name: editProfile),
        );

      default:
      // Fallback to splash to avoid a blank screen on unknown names
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
          settings: const RouteSettings(name: splash),
        );
    }
  }

  static MaterialPageRoute _badArgs(String message, {required String name}) {
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(name)),
        body: Center(child: Text(message)),
      ),
      settings: RouteSettings(name: name),
    );
  }
}