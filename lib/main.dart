import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://lmpvwgzpyprsqxcxecss.supabase.co';
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
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
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9B7BFF), brightness: Brightness.dark),
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        filled: true, fillColor: Color(0xFF171A29),
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
      ),
    ),
    home: supabaseKey.isEmpty ? const SetupScreen() : const AuthGate(),
  );
}

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Padding(
      padding: EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_awesome, size: 64, color: Color(0xFFB69CFF)),
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
    builder: (context, snapshot) => Supabase.instance.client.auth.currentSession == null
      ? const LoginScreen() : const HomeScreen(),
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
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not complete this step. Check your details and try again.');
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
        const Icon(Icons.auto_awesome, size: 62, color: Color(0xFFB69CFF)),
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

class Feature {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool needsPhoto;
  const Feature(this.title, this.subtitle, this.icon, {this.needsPhoto = true});
}

const features = [
  Feature('AI Photo', 'Turn a text idea into an image', Icons.auto_awesome, needsPhoto: false),
  Feature('Photo Editing', 'Choose a photo to edit', Icons.tune),
  Feature('Background Remover', 'Prepare a photo for background removal', Icons.layers_clear),
  Feature('Photo Enhancer', 'Choose a photo to enhance', Icons.hd),
  Feature('Photo to Video', 'Prepare a photo for animation', Icons.movie),
  Feature('Text to Video', 'Describe the video you imagine', Icons.video_library, needsPhoto: false),
  Feature('AI Reels', 'Plan a short vertical video', Icons.smart_display, needsPhoto: false),
];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Row(children: [Icon(Icons.auto_awesome, color: Color(0xFFB69CFF)), SizedBox(width: 9), Text('PixelMagic AI', style: TextStyle(fontWeight: FontWeight.bold))]),
      actions: [IconButton(tooltip: 'Sign out', onPressed: () => Supabase.instance.client.auth.signOut(), icon: const Icon(Icons.logout))],
    ),
    body: ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 28), children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [Color(0xFF49377D), Color(0xFF20223D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('YOUR CREATIVE STUDIO', style: TextStyle(letterSpacing: 1.4, fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD5C9FF))),
          SizedBox(height: 10),
          Text('Make your ideas\nlook magical.', style: TextStyle(fontSize: 27, height: 1.18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Pick a tool and start with a photo or a prompt.', style: TextStyle(color: Colors.white70)),
        ]),
      ),
      const SizedBox(height: 16),
      const CreditsPanel(),
      const SizedBox(height: 24),
      const Text('Creative tools', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        itemCount: features.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.08),
        itemBuilder: (context, index) {
          final feature = features[index];
          return Material(
            color: const Color(0xFF171A29),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FeatureScreen(feature: feature))),
              child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 45, height: 45, decoration: BoxDecoration(color: const Color(0xFF30274E), borderRadius: BorderRadius.circular(14)), child: Icon(feature.icon, color: const Color(0xFFC2AEFF), size: 25)),
                const Spacer(),
                Text(feature.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(feature.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ])),
            ),
          );
        },
      ),
      const SizedBox(height: 18),
      const Center(child: Text('More creative features are being added.', style: TextStyle(color: Colors.white38, fontSize: 11))),
    ]),
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
            decoration: BoxDecoration(color: const Color(0xFF171A29), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF514477))),
            clipBehavior: Clip.antiAlias,
            child: selectedImage == null
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.add_photo_alternate_outlined, size: 54, color: Color(0xFFC2AEFF)), const SizedBox(height: 12), Text(picking ? 'Opening gallery…' : 'Tap to choose a photo'), const SizedBox(height: 5), const Text('Select an image from your phone', style: TextStyle(color: Colors.white54, fontSize: 12))])
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
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your photo and prompt are ready. AI processing will be enabled when a free, verified generation service is integrated.'))),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Prepare my creation'),
        ),
        const SizedBox(height: 12),
        const Text('Photo selection and preview work on your phone. AI generation and export are not active in this test build yet.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 11)),
      ]),
    );
  }
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
        color: const Color(0xFF171A29),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF39314F)),
      ),
      child: Row(children: [
        const Icon(Icons.bolt, color: Color(0xFFFFD479), size: 25),
        const SizedBox(width: 10),
        const Expanded(child: Text('Your credits', style: TextStyle(fontWeight: FontWeight.w600))),
        Text(
          snapshot.hasError ? '—' : snapshot.hasData ? '${snapshot.data ?? 0}' : '…',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFC2AEFF)),
        ),
      ]),
    ),
  );
}


