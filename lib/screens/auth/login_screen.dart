import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../services/welcome_email_service.dart';
import 'email_verification_dialog.dart';
import 'mot_de_passe_oublie_screen.dart';
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
    } on RemoteAccountRequiredException catch (required) {
      if (mounted) await _linkRemoteAccount(required);
    } catch (_) {
      if (!mounted) return;
      final message =
          context.read<AuthProvider>().error ?? 'Connexion impossible.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Compte créé avant le serveur partagé : on prouve l'e-mail par code pour
  /// créer le compte serveur, puis la session s'ouvre.
  Future<void> _linkRemoteAccount(RemoteAccountRequiredException required) async {
    final token = await EmailVerificationDialog.sendAndAsk(
      context,
      email: required.email,
      firstName: required.firstName,
      intro: 'Votre compte doit être activé sur le serveur StudentHub pour partager vos annonces.',
    );
    if (token == null || !mounted) return;
    try {
      await context.read<AuthProvider>().linkRemoteAccount(
        email: required.email,
        password: _passwordController.text,
        verificationToken: token,
      );
    } catch (_) {
      if (!mounted) return;
      final message = context.read<AuthProvider>().error ?? 'Activation impossible.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      final message = switch (sent) {
        WelcomeEmailStatus.notConfigured =>
          'URL e-mail absente. Relancez Flutter avec ACCOUNT_API_URL=http://10.0.2.2:6500 et ALLOW_INSECURE_MAIL_API=true.',
        WelcomeEmailStatus.invalidConfiguration =>
          'URL invalide. Utilisez http://10.0.2.2:6500 en debug, ou une URL HTTPS publique.',
        WelcomeEmailStatus.serverUnavailable =>
          'Serveur injoignable. Lancez node backend/welcome_mail_server.mjs et vérifiez le port 6500.',
        WelcomeEmailStatus.serverRejected =>
          'Le serveur ou Resend a refusé le courriel. Consultez le terminal Node pour le détail.',
        _ => 'Le service de vérification est indisponible.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 8)));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('E-mail vérifié et compte activé.')));
    } else {
      final message = switch (result) {
        WelcomeEmailStatus.invalidCode => 'Code incorrect ou expiré. Renvoyez un nouveau code.',
        WelcomeEmailStatus.serverUnavailable => 'Serveur injoignable. Vérifiez que le serveur Node tourne encore.',
        WelcomeEmailStatus.serverRejected => 'Le serveur a refusé la vérification. Consultez le terminal Node.',
        _ => 'Vérification impossible. Vérifiez ACCOUNT_API_URL et réessayez.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 8)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: _AvecEntete(
        // Lu ici : à l'intérieur du Scaffold, la hauteur du clavier vaut 0.
        clavierOuvert: MediaQuery.viewInsetsOf(context).bottom > 0,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                    const SizedBox(height: 18),
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
                    const SizedBox(height: 4),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: _verifyEmail,
                          child: const Text('Vérifier mon e-mail'),
                        ),
                        TextButton(
                          onPressed: _ouvrirMotDePasseOublie,
                          child: const Text('Mot de passe oublié ?'),
                        ),
                      ],
                    ),
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
                    const SizedBox(height: 8),
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('Pas encore de compte ?'),
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _ouvrirMotDePasseOublie() {
    final saisie = _identityController.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MotDePasseOublieScreen(
          email: saisie.contains('@') ? saisie : '',
        ),
      ),
    );
  }
}

/// Bandeau sombre de la marque, au-dessus du formulaire. Il s'efface quand le
/// clavier est ouvert pour laisser la place aux champs.
class _AvecEntete extends StatelessWidget {
  const _AvecEntete({required this.clavierOuvert, required this.child});
  final bool clavierOuvert;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: clavierOuvert ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Column(
        children: [
          if (!clavierOuvert) Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF071B38), Color(0xFF0F3D75)],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: const SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Column(
                  children: [
                    Icon(Icons.home_work_outlined, size: 40, color: Color(0xFFE9B15E)),
                    SizedBox(height: 6),
                    Text(
                      'StudentHub',
                      style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tous vos services du quotidien',
                      style: TextStyle(color: Color(0xFFDCE8F6), fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: SafeArea(top: clavierOuvert, child: child)),
        ],
      ),
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
