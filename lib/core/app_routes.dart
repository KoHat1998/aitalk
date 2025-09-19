import 'package:flutter/material.dart';

import '../ui/screens/splash_screen.dart';
import '../ui/screens/sign_in_screen.dart';
import '../ui/screens/sign_up_screen.dart';
import '../ui/screens/shell.dart';
import '../ui/screens/contacts_screen.dart';
import '../ui/screens/chats_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/screens/new_group_screen.dart';
import '../ui/screens/thread_screen.dart';
import '../ui/screens/call_screen.dart';

// Call ringing screens
import '../ui/screens/outgoing_call_screen.dart';
import '../ui/screens/incoming_call_screen.dart';

// Contacts / friend features
import '../ui/screens/add_contact_screen.dart';
import '../ui/screens/my_code_screen.dart';
import '../ui/screens/qr_scan_screen.dart';
import '../ui/screens/edit_profile_screen.dart';

class AppRoutes {
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

  // New for ringing flow
  static const outgoingCall = '/outgoing-call';
  static const incomingCall = '/incoming-call';

  static const addContact = '/add-contact';
  static const myCode = '/my-code';
  static const scanQr = '/scan-qr';

  static const editProfile = '/edit-profile';

  static Route<dynamic> onGenerateRoute(RouteSettings s) {
    switch (s.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());

      case signIn:
        return MaterialPageRoute(builder: (_) => const SignInScreen());

      case signUp:
        return MaterialPageRoute(builder: (_) => const SignUpScreen());

      case shell:
        return MaterialPageRoute(builder: (_) => const Shell());

      case contacts:
        return MaterialPageRoute(builder: (_) => const ContactsScreen());

      case chats:
        return MaterialPageRoute(builder: (_) => const ChatsScreen());

      case settings:
        return MaterialPageRoute(builder: (_) => const SettingsScreen());

      case newGroup:
        return MaterialPageRoute(builder: (_) => const NewGroupScreen());

      case thread: {
        final args = s.arguments;
        if (args is! ThreadArgs) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Missing thread arguments')),
            ),
          );
        }
        return MaterialPageRoute(builder: (_) => ThreadScreen(args: args));
      }

      case call: {
        final args = s.arguments;
        if (args is! CallArgs) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Missing call arguments (threadId required)')),
            ),
          );
        }
        return MaterialPageRoute(builder: (_) => CallScreen(args: args));
      }

    // ---- New ringing routes ----
      case outgoingCall: {
        final args = s.arguments;
        if (args is! OutgoingCallArgs) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Missing outgoing call args')),
            ),
          );
        }
        return MaterialPageRoute(builder: (_) => OutgoingCallScreen(args: args));
      }

      case incomingCall: {
        final args = s.arguments;
        if (args is! IncomingCallArgs) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Missing incoming call args')),
            ),
          );
        }
        return MaterialPageRoute(builder: (_) => IncomingCallScreen(args: args));
      }

    // Contacts / codes / QR
      case addContact:
        return MaterialPageRoute(builder: (_) => const AddContactScreen());
      case myCode:
        return MaterialPageRoute(builder: (_) => const MyCodeScreen());
      case scanQr:
        return MaterialPageRoute(builder: (_) => const QrScanScreen());

    // Edit profile
      case editProfile:
        return MaterialPageRoute(builder: (_) => const EditProfileScreen());

      default:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
    }
  }
}
