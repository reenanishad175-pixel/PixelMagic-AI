// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'local_editors.dart';
import 'local_downloads.dart';
import 'local_background_remover.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://lmpvwgzpyprsqxcxecss.supabase.co';
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  }
  runApp(const PixelMagicApp());
}

class PixelMagicApp extends StatelessWidget {
  const PixelMagicApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'PixelMagic AI',
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B0D16),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF18C6B8), brightness: Brightness.dark),
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        filled: true, fillColor: Color(0xFF111F2B),
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
      ),
    ),
    home: supabaseKey.isEmpty ? const SetupScreen() : const AuthGate(),
  );
}


class PixelMagicLogo extends StatelessWidget {
  final double size;
  final bool wordmark;
  const PixelMagicLogo({super.key, this.size = 64, this.wordmark = false});

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size, height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          colors: [Color(0xFF25D7C5), Color(0xFF126A78), Color(0xFF172B47)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF8AF1E3).withOpacity(0.45), width: 1.2),
        boxShadow: [BoxShadow(color: const Color(0xFF19C9B6).withOpacity(0.22), blurRadius: size * 0.24, spreadRadius: 1)],
      ),
      child: Stack(alignment: Alignment.center, children: [
        Icon(Icons.auto_awesome_rounded, size: size * 0.56, color: const Color(0xFFFFD98A)),
        Positioned(right: size * 0.15, bottom: size * 0.16,
          child: Container(width: size * 0.13, height: size * 0.13,
            decoration: BoxDecoration(color: const Color(0xFFFFD98A), borderRadius: BorderRadius.circular(size * 0.035)))),
        Positioned(left: size * 0.16, top: size * 0.17,
          child: Container(width: size * 0.09, height: size * 0.09,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(size * 0.025)))),
      ]),
    );
    if (!wordmark) return mark;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      mark,
      const SizedBox(width: 14),
      const Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('PixelMagic', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
        Text('AI CREATIVE STUDIO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 2.0, color: Color(0xFF55DCCB))),
      ]),
    ]);
  }
}

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Padding(
      padding: EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        PixelMagicLogo(size: 76),
        SizedBox(height: 18),
        Text('PixelMagic AI', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        SizedBox(height: 12),
        Text('App setup is being completed. Please install the latest test build.', textAlign: TextAlign.center),
      ]),
    )),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: Supabase.instance.client.auth.onAuthStateChange,
    builder: (context, snapshot) {
      if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
        return const PasswordRecoveryScreen();
      }
      return Supabase.instance.client.auth.currentSession == null
          ? const LoginScreen()
          : const HomeScreen();
    },
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  bool creating = false, busy = false, usePhone = false;
  String? error;
  String? notice;

  String get normalizedPhone {
    final digits = phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('91') && digits.length == 12) return '+$digits';
    if (digits.length == 10) return '+91$digits';
    return '';
  }

  Future<void> submit() async {
    FocusScope.of(context).unfocus();
    setState(() { busy = true; error = null; notice = null; });
    try {
      final auth = Supabase.instance.client.auth;
      if (creating) {
        if (email.text.trim().isEmpty || !email.text.contains('@')) {
          throw const AuthException('Please enter a valid email address.');
        }
        if (normalizedPhone.isEmpty) {
          throw const AuthException('Please enter a valid 10-digit Indian mobile number.');
        }
        if (password.text.length < 6) {
          throw const AuthException('Password must be at least 6 characters.');
        }
        if (name.text.trim().isEmpty) {
          throw const AuthException('Please enter your name.');
        }
        await auth.signUp(
          email: email.text.trim(),
          password: password.text,
          emailRedirectTo: 'io.supabase.pixelmagic://login-callback/',
          data: {'full_name': name.text.trim(), 'mobile_number': normalizedPhone},
        );
        if (mounted) setState(() => notice = 'Registration complete. Please verify your email using the link sent to your Gmail/email inbox.');
      } else if (usePhone) {
        if (normalizedPhone.isEmpty) {
          throw const AuthException('Please enter a valid 10-digit Indian mobile number.');
        }
        final response = await Supabase.instance.client.functions.invoke(
          'phone-password-login',
          body: {'phone': normalizedPhone, 'password': password.text},
        );
        if (response.status != 200 || response.data is! Map || response.data['refresh_token'] == null) {
          throw const AuthException('Mobile number or password is incorrect.');
        }
        await auth.setSession(response.data['refresh_token'] as String);
      } else {
        if (email.text.trim().isEmpty) {
          throw const AuthException('Please enter your email address.');
        }
        await auth.signInWithPassword(email: email.text.trim(), password: password.text);
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => error = e.code == '23505'
            ? 'This mobile number is already registered with another account. Please use a different number.'
            : 'Could not complete this step. Check your details and try again.');
      }
    } on AuthException catch (e) {
      final authMessage = e.message.toLowerCase();
      final duplicateMobile = authMessage.contains('profiles_mobile_number_unique') ||
          authMessage.contains('duplicate key') ||
          authMessage.contains('already exists') ||
          authMessage.contains('database error saving new user');
      if (mounted) {
        setState(() => error = duplicateMobile
            ? 'This mobile number may already be registered with another account. Please use a different number or contact support if the problem continues.'
            : e.message);
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Could not complete this step. Check your details and try again.');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> sendPasswordReset() async {
    FocusScope.of(context).unfocus();
    final address = email.text.trim();
    if (address.isEmpty || !address.contains('@')) {
      setState(() => error = 'Enter your registered email address first.');
      return;
    }
    setState(() { busy = true; error = null; notice = null; });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        address,
        redirectTo: 'io.supabase.pixelmagic://login-callback/',
      );
      if (mounted) setState(() => notice = 'Password reset link sent. Open the email on this phone and follow the link to set a new password.');
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not send the reset link. Please try again.');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> signInWithGoogle() async {
    setState(() { busy = true; error = null; notice = null; });
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.pixelmagic://login-callback/',
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Google sign-in is not configured yet. Please try email login.');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void dispose() { name.dispose(); email.dispose(); phone.dispose(); password.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const PixelMagicLogo(size: 76),
        const SizedBox(height: 16),
        const Text('PixelMagic AI', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Create something amazing', textAlign: TextAlign.center),
        const SizedBox(height: 28),
        if (creating) ...[
          TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 12),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email address')),
          const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, maxLength: 10, decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91 ', counterText: '')),
        ] else ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Email'), icon: Icon(Icons.email_outlined)),
              ButtonSegment(value: true, label: Text('Mobile'), icon: Icon(Icons.phone_android)),
            ],
            selected: {usePhone},
            onSelectionChanged: busy ? null : (value) => setState(() { usePhone = value.first; error = null; }),
          ),
          const SizedBox(height: 12),
          if (usePhone)
            TextField(controller: phone, keyboardType: TextInputType.phone, maxLength: 10, decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91 ', counterText: ''))
          else
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email address')),
        ],
        const SizedBox(height: 12),
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
        if (notice != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(notice!, style: const TextStyle(color: Colors.greenAccent, fontSize: 12))),
        const SizedBox(height: 18),
        FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Please wait…' : creating ? 'Register' : 'Login')),
        if (!creating && !usePhone)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: busy ? null : sendPasswordReset,
              child: const Text('Forgot password?'),
            ),
          ),
        if (!creating) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : signInWithGoogle,
            icon: const Icon(Icons.g_mobiledata, size: 28),
            label: const Text('Continue with Google'),
          ),
        ],
        TextButton(onPressed: busy ? null : () => setState(() { creating = !creating; error = null; notice = null; }), child: Text(creating ? 'Already registered? Login' : 'New here? Register')),
        if (creating)
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('Register with your name, Gmail, mobile number and password. Verify your email from the link sent to your inbox. After verification, use either Gmail or mobile number with the same password.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 11))),
      ],
    )),
  )));
}

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> savePassword() async {
    FocusScope.of(context).unfocus();
    if (password.text.length < 6) {
      setState(() => error = 'Password must be at least 6 characters.');
      return;
    }
    if (password.text != confirm.text) {
      setState(() => error = 'Both passwords do not match.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password.text),
      );
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated. Please log in with your new password.')),
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not update your password. Please reopen the reset link and try again.');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void dispose() {
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Set a new password')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_reset, size: 58, color: Color(0xFF55DCCB)),
              const SizedBox(height: 18),
              const Text('Create a new password', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 22),
              TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
              const SizedBox(height: 12),
              TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password')),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
              const SizedBox(height: 18),
              FilledButton(onPressed: busy ? null : savePassword, child: Text(busy ? 'Please wait…' : 'Save new password')),
            ],
          ),
        ),
      ),
    ),
  );
}

class Feature {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool needsPhoto;
  const Feature(this.title, this.subtitle, this.icon, {this.needsPhoto = true});
}

const features = [
  Feature('AI Photo', 'Turn a text idea into an image', Icons.auto_awesome, needsPhoto: false),
  Feature('Photo Editing', '20+ filters, preview and save', Icons.tune),
  Feature('Video Editor', 'Trim, music, text, filters and merge', Icons.video_camera_back),
  Feature('Background Remover', 'Remove a person’s background offline', Icons.layers_clear),
  Feature('Photo Enhancer', 'Choose a photo to enhance', Icons.hd),
  Feature('Photo to Video', 'Prepare a photo for animation', Icons.movie),
  Feature('Text to Video', 'Describe the video you imagine', Icons.video_library, needsPhoto: false),
  Feature('AI Reels', 'Plan a short vertical video', Icons.smart_display, needsPhoto: false),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? mobileNumber;
  bool checkingMobile = true;
  int selectedTab = 0;

  @override
  void initState() {
    super.initState();
    loadMobile();
  }

  Future<void> loadMobile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => checkingMobile = false);
      return;
    }
    try {
      final row = await Supabase.instance.client.from('profiles')
          .select('mobile_number').eq('id', user.id).maybeSingle();
      if (mounted) {
        setState(() {
          mobileNumber = row?['mobile_number'] as String?;
          checkingMobile = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => checkingMobile = false);
    }
  }

  Future<void> addMobile() async {
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => const AddMobileDialog(),
    );
    final digits = (entered ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 10) {
      if (entered != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid 10-digit mobile number.')),
        );
      }
      return;
    }
    final normalized = '+91$digits';
    try {
      final user = Supabase.instance.client.auth.currentUser!;
      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        'mobile_number': normalized,
        'email': user.email,
        'display_name': user.userMetadata?['full_name'] ?? user.userMetadata?['name'],
      });
      if (mounted) setState(() => mobileNumber = normalized);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mobile number saved.')),
        );
      }
    } on PostgrestException catch (e) {
      final message = e.code == '23505'
          ? 'This mobile number is already registered with another account. Please use a different number.'
          : 'Could not save this mobile number. Please try again.';
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save this mobile number. Please try again.')),
        );
      }
    }
  }

  Widget _homeContent() => ListView(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
    children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0xFF145B5A), Color(0xFF162D3B)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('YOUR CREATIVE STUDIO', style: TextStyle(letterSpacing: 1.4, fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFBCEFE8))),
          SizedBox(height: 10),
          Text('Make your ideas\\nlook magical.', style: TextStyle(fontSize: 27, height: 1.18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Pick a tool and start with a photo or a prompt.', style: TextStyle(color: Colors.white70)),
        ]),
      ),
      const SizedBox(height: 22),
      const CreditsPanel(),
      const SizedBox(height: 24),
      const Text('Creative tools', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: features.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 168,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemBuilder: (context, index) {
          final feature = features[index];
          return Material(
            color: const Color(0xFF111F2B),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => feature.title == 'Photo Editing' || feature.title == 'Photo Enhancer'
                    ? const LocalPhotoEditorScreen()
                    : feature.title == 'Video Editor'
                        ? const LocalVideoEditorScreen()
                        : feature.title == 'Background Remover'
                            ? const BackgroundRemoverScreen()
                            : FeatureScreen(feature: feature),
              )),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 45, height: 45,
                      decoration: BoxDecoration(color: const Color(0xFF153E43), borderRadius: BorderRadius.circular(14)),
                      child: Icon(feature.icon, color: const Color(0xFF55DCCB), size: 25),
                    ),
                    const Spacer(),
                    Text(feature.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(feature.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 18),
      const Center(child: Text('More creative features are being added.', style: TextStyle(color: Colors.white38, fontSize: 11))),
    ],
  );

  Future<void> _editDisplayName() async {
    final controller = TextEditingController(
      text: (Supabase.instance.client.auth.currentUser?.userMetadata?['full_name'] ??
          Supabase.instance.client.auth.currentUser?.userMetadata?['name'] ?? '').toString(),
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Your name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser!;
      await client.auth.updateUser(UserAttributes(data: {
        ...?user.userMetadata,
        'full_name': value.trim(),
      }));
      await client.from('profiles').upsert({
        'id': user.id,
        'email': user.email,
        'display_name': value.trim(),
      });
      if (mounted) setState(() {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name updated successfully.')),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update your name. Please try again.')),
      );
    }
  }

  Widget _settingsContent() {
    final user = Supabase.instance.client.auth.currentUser;
    final displayName = (user?.userMetadata?['full_name'] ??
        user?.userMetadata?['name'] ?? 'PixelMagic user').toString();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text('Account & Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Your profile, credits, rewards and subscription in one place.',
            style: TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 18),
        Card(
          color: const Color(0xFF111F2B),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const CircleAvatar(radius: 25, backgroundColor: Color(0xFF153E43),
                    child: Icon(Icons.person, color: Color(0xFF55DCCB), size: 28)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(displayName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  Text(user?.email ?? 'Email not available',
                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ])),
                IconButton(onPressed: _editDisplayName, icon: const Icon(Icons.edit, color: Color(0xFF55DCCB)),
                    tooltip: 'Edit name'),
              ]),
              const Divider(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone_android, color: Color(0xFF55DCCB)),
                title: const Text('Mobile number'),
                subtitle: Text(checkingMobile ? 'Loading…' : (mobileNumber ?? 'Not added yet')),
                trailing: mobileNumber == null
                    ? TextButton(onPressed: checkingMobile ? null : addMobile, child: const Text('Add once'))
                    : const Icon(Icons.verified, color: Colors.greenAccent),
              ),
              const Text('Your mobile number can be added once and cannot be changed later.',
                  style: TextStyle(color: Colors.white38, fontSize: 10)),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        const CreditsPanel(),
        const SizedBox(height: 14),
        const DailyRewardsPanel(),
        const SizedBox(height: 14),
        const SubscriptionPanel(),
        const SizedBox(height: 14),
        Card(
          color: const Color(0xFF111F2B),
          child: ListTile(
            leading: const Icon(Icons.lock_reset, color: Color(0xFF55DCCB)),
            title: const Text('Change password'),
            subtitle: const Text('Update your account password securely'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const PasswordChangeDialog(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          color: const Color(0xFF24191E),
          child: ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Log out'),
            subtitle: const Text('Sign out from this PixelMagic AI account'),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Log out?'),
                  content: const Text('Are you sure you want to sign out?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Log out')),
                  ],
                ),
              );
              if (confirm == true) await Supabase.instance.client.auth.signOut();
            },
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _downloadsContent() => const LocalDownloadsScreen();

  @override
  Widget build(BuildContext context) {
    final titles = ['PixelMagic AI', 'Downloads', 'Account & Settings'];
    final pages = [_homeContent(), _downloadsContent(), _settingsContent()];
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const PixelMagicLogo(size: 34),
          const SizedBox(width: 9),
          Text(titles[selectedTab], style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      ),
      body: SafeArea(child: IndexedStack(index: selectedTab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) => setState(() => selectedTab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Downloads'),
          NavigationDestination(icon: Icon(Icons.manage_accounts_outlined), selectedIcon: Icon(Icons.manage_accounts), label: 'Account'),
        ],
      ),
    );
  }
}

class AddMobileDialog extends StatefulWidget {
  const AddMobileDialog({super.key});

  @override
  State<AddMobileDialog> createState() => _AddMobileDialogState();
}

class _AddMobileDialogState extends State<AddMobileDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add mobile number'),
    content: TextField(
      controller: controller,
      keyboardType: TextInputType.phone,
      maxLength: 10,
      decoration: const InputDecoration(
        labelText: '10-digit mobile number',
        prefixText: '+91 ',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}

class FeatureScreen extends StatefulWidget {
  final Feature feature;
  const FeatureScreen({super.key, required this.feature});
  @override
  State<FeatureScreen> createState() => _FeatureScreenState();
}

class _FeatureScreenState extends State<FeatureScreen> {
  final picker = ImagePicker();
  final prompt = TextEditingController();
  XFile? selectedImage;
  bool picking = false;

  Future<void> chooseImage() async {
    setState(() => picking = true);
    try {
      final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
      if (image != null && mounted) setState(() => selectedImage = image);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the photo gallery. Please try again.')));
    }
    if (mounted) setState(() => picking = false);
  }

  @override
  void dispose() { prompt.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final needsPhoto = widget.feature.needsPhoto;
    return Scaffold(
      appBar: AppBar(title: Text(widget.feature.title)),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(widget.feature.subtitle, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 18),
        if (needsPhoto) InkWell(
          onTap: picking ? null : chooseImage,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 270, width: double.infinity,
            decoration: BoxDecoration(color: const Color(0xFF111F2B), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF286A68))),
            clipBehavior: Clip.antiAlias,
            child: selectedImage == null
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.add_photo_alternate_outlined, size: 54, color: Color(0xFF55DCCB)), const SizedBox(height: 12), Text(picking ? 'Opening gallery…' : 'Tap to choose a photo'), const SizedBox(height: 5), const Text('Select an image from your phone', style: TextStyle(color: Colors.white54, fontSize: 12))])
              : Image.file(File(selectedImage!.path), fit: BoxFit.contain),
          ),
        ),
        if (selectedImage != null) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [const Icon(Icons.check_circle, color: Colors.greenAccent, size: 17), const SizedBox(width: 7), const Expanded(child: Text('Photo selected on this device', style: TextStyle(color: Colors.white70, fontSize: 12))), TextButton(onPressed: chooseImage, child: const Text('Change'))]),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: prompt, minLines: 3, maxLines: 5,
          decoration: InputDecoration(
            labelText: widget.feature.title == 'AI Photo' || widget.feature.title == 'Text to Video' || widget.feature.title == 'AI Reels' ? 'Describe your idea' : 'What would you like to change?',
            hintText: 'Write your creative idea here…', alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.cloud_off),
          label: const Text('AI service will be connected after testing'),
        ),
        const SizedBox(height: 12),
        const Text('This tool needs an AI service/API. Photo selection and prompt entry are available now; generation will be enabled after the first APK test.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 11)),
      ]),
    );
  }
}


class PasswordChangeDialog extends StatefulWidget {
  const PasswordChangeDialog({super.key});

  @override
  State<PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<PasswordChangeDialog> {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> save() async {
    if (next.text.length < 6 || next.text != confirm.text) {
      setState(() => error = next.text.length < 6
          ? 'New password must be at least 6 characters.'
          : 'New passwords do not match.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: next.text, currentPassword: current.text),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed successfully.')),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not change password. Check your current password and try again.');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void dispose() {
    current.dispose(); next.dispose(); confirm.dispose(); super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change password'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: current, obscureText: true,
          decoration: const InputDecoration(labelText: 'Current password')),
      const SizedBox(height: 10),
      TextField(controller: next, obscureText: true,
          decoration: const InputDecoration(labelText: 'New password')),
      const SizedBox(height: 10),
      TextField(controller: confirm, obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirm new password')),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 10),
          child: Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
    ])),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Saving…' : 'Update')),
    ],
  );
}

class DailyRewardsPanel extends StatefulWidget {
  const DailyRewardsPanel({super.key});

  @override
  State<DailyRewardsPanel> createState() => _DailyRewardsPanelState();
}

class _DailyRewardsPanelState extends State<DailyRewardsPanel> {
  static const rewards = [1, 3, 5, 7, 10, 15, 20];
  bool busy = false;
  Map<String, dynamic>? latest;
  String? error;

  @override
  void initState() {
    super.initState();
    loadStatus();
  }

  Future<void> loadStatus() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final row = await Supabase.instance.client.from('daily_checkins')
          .select('reward_date,cycle_day,credits_awarded')
          .eq('user_id', user.id)
          .order('reward_date', ascending: false)
          .limit(1)
          .maybeSingle();
      if (mounted) setState(() => latest = row);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load daily rewards.');
    }
  }

  bool get claimedToday {
    final date = latest?['reward_date']?.toString();
    if (date == null) return false;
    final now = DateTime.now();
    final today = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return date == today;
  }

  Future<void> claim() async {
    setState(() { busy = true; error = null; });
    try {
      final result = await Supabase.instance.client.rpc('claim_daily_reward');
      await loadStatus();
      final data = Map<String, dynamic>.from(result as Map);
      if (!mounted) return;
      final added = (data['credits_added'] as num?)?.toInt() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(data['claimed'] == true
            ? 'You earned $added credits! Keep your 7-day streak going.'
            : 'Today’s reward has already been claimed.'),
      ));
    } catch (_) {
      if (mounted) setState(() => error = 'Reward could not be claimed. Please try again.');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final nextDay = claimedToday
        ? (((latest?['cycle_day'] as num?)?.toInt() ?? 0) >= 7
            ? 1 : ((latest?['cycle_day'] as num?)?.toInt() ?? 0) + 1)
        : latest == null ? 1 : (((latest?['cycle_day'] as num?)?.toInt() ?? 0) >= 7
            ? 1 : ((latest?['cycle_day'] as num?)?.toInt() ?? 0) + 1);
    return Card(
      color: const Color(0xFF111F2B),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.calendar_month, color: Color(0xFFFFD479)),
            const SizedBox(width: 8),
            const Expanded(child: Text('7-day daily check-in', style: TextStyle(fontWeight: FontWeight.bold))),
            Text(claimedToday ? 'Claimed today' : 'Day $nextDay next',
                style: const TextStyle(color: Color(0xFF55DCCB), fontSize: 11)),
          ]),
          const SizedBox(height: 12),
          Row(children: List.generate(7, (i) => Expanded(child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
            decoration: BoxDecoration(
              color: (latest?['cycle_day'] as num? ?? 0) >= i + 1
                  ? const Color(0xFF174A45) : const Color(0xFF1A2632),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: i + 1 == nextDay
                  ? const Color(0xFF55DCCB) : Colors.white10),
            ),
            child: Column(children: [
              Text('D${i + 1}', style: const TextStyle(fontSize: 9, color: Colors.white60)),
              const SizedBox(height: 4),
              const Icon(Icons.bolt, size: 13, color: Color(0xFFFFD479)),
              Text('${rewards[i]}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ]),
          )))),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: busy || claimedToday ? null : claim,
            icon: Icon(claimedToday ? Icons.check_circle : Icons.card_giftcard),
            label: Text(busy ? 'Claiming…' : claimedToday ? 'Come back tomorrow' : 'Claim today’s free credits'),
          )),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 11))),
          const Text('Miss a day? Your 7-day cycle starts again from Day 1. Ad rewards will be added after the ad service is connected.',
              style: TextStyle(color: Colors.white38, fontSize: 10)),
        ]),
      ),
    );
  }
}

class SubscriptionPanel extends StatelessWidget {
  const SubscriptionPanel({super.key});

  Future<Map<String, dynamic>?> loadSubscription() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    return Supabase.instance.client.from('subscriptions')
        .select('plan_code,status,current_period_end,created_at')
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFF111F2B),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.workspace_premium, color: Color(0xFFFFD479)),
          SizedBox(width: 8),
          Text('Subscription', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 10),
        FutureBuilder<Map<String, dynamic>?>(
          future: loadSubscription(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
            }
            final row = snapshot.data;
            if (row == null) {
              return const Text('Current plan: Free. Choose a plan below when payment is enabled.',
                  style: TextStyle(color: Colors.white70, fontSize: 12));
            }
            final plan = (row['plan_code'] ?? 'free').toString().toUpperCase();
            final status = (row['status'] ?? 'pending').toString().toUpperCase();
            final end = row['current_period_end']?.toString();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Plan: $plan   •   Status: $status', style: const TextStyle(color: Color(0xFF55DCCB))),
              if (end != null) Text('Valid until: ${end.split('T').first}',
                  style: const TextStyle(color: Colors.white60, fontSize: 11)),
            ]);
          },
        ),
        const Divider(height: 22),
        const Text('Available plans', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _planRow('Monthly', 'monthly', '30 days'),
        _planRow('Yearly', 'yearly', '365 days'),
        _planRow('Lifetime', 'lifetime', 'One-time access'),
        const SizedBox(height: 8),
        const Text('Plan prices and secure payment activation are pending payment-gateway setup. No payment will be taken until the final price and gateway are configured.',
            style: TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
    ),
  );

  Widget _planRow(String name, String code, String duration) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.verified_outlined, color: Color(0xFF55DCCB)),
    title: Text(name),
    subtitle: Text(duration),
    trailing: const Text('Price pending', style: TextStyle(color: Colors.white54, fontSize: 10)),
  );
}

class CreditsPanel extends StatelessWidget {
  const CreditsPanel({super.key});

  Future<int?> loadCredits() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final row = await Supabase.instance.client
        .from('user_credits')
        .select('balance')
        .eq('user_id', user.id)
        .maybeSingle();
    return row == null ? 0 : (row['balance'] as num).toInt();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<int?>(
    future: loadCredits(),
    builder: (context, snapshot) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111F2B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF254D50)),
      ),
      child: Row(children: [
        const Icon(Icons.bolt, color: Color(0xFFFFD479), size: 25),
        const SizedBox(width: 10),
        const Expanded(child: Text('Your credits', style: TextStyle(fontWeight: FontWeight.w600))),
        Text(
          snapshot.hasError ? '—' : snapshot.hasData ? '${snapshot.data ?? 0}' : '…',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF55DCCB)),
        ),
      ]),
    ),
  );
}


