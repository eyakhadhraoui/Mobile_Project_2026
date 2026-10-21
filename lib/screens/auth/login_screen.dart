import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../services/welcome_email_service.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identityController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _identityController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      await context.read<AuthProvider>().signIn(
        _identityController.text,
        _passwordController.text,
      );
    } catch (_) {
      if (!mounted) return;
      final message =
          context.read<AuthProvider>().error ?? 'Connexion impossible.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _verifyEmail() async {
    final email = _identityController.text.trim();
    if (Validators.email(email) != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saisissez votre adresse e-mail dans le premier champ.')));
      return;
    }
    final auth = context.read<AuthProvider>();
    final user = await auth.getUserByEmail(email);
    if (!mounted) return;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun compte trouvé avec cette adresse e-mail.')));
      return;
    }
    if (user.emailVerified) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cette adresse e-mail est déjà vérifiée.')));
      return;
    }
    const mail = WelcomeEmailService();
    final sent = await mail.sendWelcome(email: user.email, firstName: user.prenom);
    if (!mounted) return;
    if (sent != WelcomeEmailStatus.sent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Le service de vérification est indisponible.')));
      return;
    }
    final codeController = TextEditingController();
    final code = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Vérifier votre e-mail'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [Text('Code envoyé à ${user.email}.'), TextField(controller: codeController, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Code à 6 chiffres'))]),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(dialogContext, codeController.text.trim()), child: const Text('Vérifier'))],
    ));
    codeController.dispose();
    if (code == null || code.isEmpty || !mounted) return;
    final result = await mail.verifyCode(email: user.email, code: code);
    if (!mounted) return;
    if (result == WelcomeEmailStatus.verified) {
      await auth.markEmailVerified(user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('E-mail vérifié. Le compte attend la validation de l’administrateur.')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code incorrect ou expiré. Renvoyez un nouveau code.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _BrandMark(),
                    const SizedBox(height: 34),
                    Icon(
                      Icons.apartment_rounded,
                      size: 82,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Bon retour !',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Connectez-vous pour retrouver vos services.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 30),
                    const _FieldLabel('Adresse e-mail ou téléphone'),
                    TextFormField(
                      controller: _identityController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.mail_outline),
                        hintText: 'exemple@email.com',
                      ),
                      validator: (value) => Validators.required(
                        value,
                        label: 'L\'adresse e-mail ou le téléphone',
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _FieldLabel('Mot de passe'),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _signIn(),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_outline),
                        hintText: 'Votre mot de passe',
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) =>
                          Validators.required(value, label: 'Le mot de passe'),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _showResetInfo,
                        child: const Text('Mot de passe oublié ?'),
                      ),
                    ),
                    Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _verifyEmail, child: const Text('Vérifier mon adresse e-mail'))),
                    const SizedBox(height: 8),
                    Consumer<AuthProvider>(
                      builder: (context, auth, _) => FilledButton(
                        onPressed: auth.isLoading ? null : _signIn,
                        child: auth.isLoading
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Se connecter'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('Vous n’avez pas encore de compte ? '),
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const RegisterScreen(),
                              ),
                            ),
                            child: const Text('Créer un compte'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Les comptes et les données restent sur cet appareil.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showResetInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Réinitialiser le mot de passe'),
        content: const Text(
          'Les comptes SQLite sont enregistrés uniquement sur cet appareil. '
          'La réinitialisation par e-mail nécessite un serveur ou un service en ligne.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.home_work_outlined, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Student'),
              TextSpan(
                text: 'Hub',
                style: TextStyle(color: primary),
              ),
            ],
          ),
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: Theme.of(context).textTheme.labelLarge),
  );
}
