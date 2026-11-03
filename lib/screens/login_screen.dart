import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/brand.dart';
import '../core/session.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _usr = TextEditingController();
  final _pwd = TextEditingController();
  bool _busy = false;
  bool _hide = true;

  @override
  void initState() {
    super.initState();
    _url.text = context.read<Session>().serverUrl ?? '';
  }

  @override
  void dispose() {
    _url.dispose();
    _usr.dispose();
    _pwd.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final url = Session.defaultServer.isNotEmpty ? Session.defaultServer : _url.text;
      await context.read<Session>().login(url, _usr.text, _pwd.text);
    } catch (e) {
      if (mounted) await showErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lockedServer = Session.defaultServer.isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Image.asset(Brand.logo, width: 104, height: 104),
                const SizedBox(height: 12),
                ShaderMask(
                  shaderCallback: (r) => Brand.gradient.createShader(r),
                  child: Text(Brand.appName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800, color: Colors.white)),
                ),
                const SizedBox(height: 2),
                Text(Brand.tagline,
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Sign in with your ERP account',
                    textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 32),
                if (!lockedServer) ...[
                  TextFormField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                        labelText: 'Server address', hintText: 'erp.yourcompany.com', prefixIcon: Icon(Icons.dns)),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your ERP address' : null,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _usr,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email or username', prefixIcon: Icon(Icons.person)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _pwd,
                  obscureText: _hide,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Sign in'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Use the same login as your ERP. Your Project Manager assigns the sites you can report on.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
