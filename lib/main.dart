import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
        Text('App starter is installed. Supabase publishable key will be configured securely during the build.', textAlign: TextAlign.center),
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
  final email = TextEditingController();
  final password = TextEditingController();
  bool creating = false, busy = false;
  String? error;
  Future<void> submit() async {
    setState(() { busy = true; error = null; });
    try {
      if (creating) {
        await Supabase.instance.client.auth.signUp(email: email.text.trim(), password: password.text);
      } else {
        await Supabase.instance.client.auth.signInWithPassword(email: email.text.trim(), password: password.text);
      }
    } on AuthException catch (e) { setState(() => error = e.message); }
      catch (e) { setState(() => error = 'Something went wrong. Please try again.'); }
    if (mounted) setState(() => busy = false);
  }
  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.auto_awesome, size: 62, color: Color(0xFFB69CFF)),
        const SizedBox(height: 16),
        const Text('PixelMagic AI', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Create something amazing', textAlign: TextAlign.center),
        const SizedBox(height: 32),
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
        const SizedBox(height: 18),
        FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Please wait…' : creating ? 'Create account' : 'Sign in')),
        TextButton(onPressed: () => setState(() { creating = !creating; error = null; }), child: Text(creating ? 'Already registered? Sign in' : 'New here? Create account')),
      ],
    )))));
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  static const features = [
    ('AI Photo', Icons.image, 'image_generate'),
    ('Photo Editing', Icons.edit, 'image_edit'),
    ('Background Remover', Icons.layers_clear, 'background_remove'),
    ('Photo Enhancer', Icons.hd, 'enhance'),
    ('Photo to Video', Icons.movie, 'photo_to_video'),
    ('Text to Video', Icons.video_library, 'text_to_video'),
    ('AI Reels', Icons.smart_display, 'ai_reels'),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('PixelMagic AI'), actions: [IconButton(onPressed: () => Supabase.instance.client.auth.signOut(), icon: const Icon(Icons.logout))]),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Your creative studio', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Choose a tool to get started. AI generation tools are being added in stages.'),
      const SizedBox(height: 22),
      GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.25,
        children: features.map((f) => Card(child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${f.$1} is coming soon.'))), child: Padding(padding: const EdgeInsets.all(14), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(f.$2, size: 30, color: const Color(0xFFB69CFF)), const SizedBox(height: 10), Text(f.$1, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))]))))),
      ),
    ]),
  );
}
