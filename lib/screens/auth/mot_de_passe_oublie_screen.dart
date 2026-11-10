import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../providers/mot_de_passe_provider.dart';
import '../../services/welcome_email_service.dart';
import '../../widgets/indicateur_mot_de_passe.dart';
import 'email_verification_dialog.dart';

/// Réinitialisation en deux temps : envoi d'un code par e-mail, puis saisie du
/// code et du nouveau mot de passe.
class MotDePasseOublieScreen extends StatefulWidget {
  const MotDePasseOublieScreen({
    super.key,
    this.email = '',
    this.mail = const WelcomeEmailService(),
  });

  final String email;
  final WelcomeEmailService mail;

  @override
  State<MotDePasseOublieScreen> createState() => _MotDePasseOublieScreenState();
}

class _MotDePasseOublieScreenState extends State<MotDePasseOublieScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _nouveau = TextEditingController();
  final _confirmation = TextEditingController();
  final _verification = MotDePasseProvider();
  bool _codeEnvoye = false;
  bool _occupe = false;
  bool _masque = true;

  /// Conservé après un code valide : le serveur peut échouer ensuite, et un
  /// code ne s'utilise qu'une fois.
  String? _jeton;

  @override
  void dispose() {
    _verification.dispose();
    _email.dispose();
    _code.dispose();
    _nouveau.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  /// Remplace le message affiché : une erreur ne doit pas attendre son tour.
  void _message(String texte) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texte)));

  Future<void> _envoyerCode() async {
    if (Validators.email(_email.text.trim()) != null) {
      _message('Saisissez une adresse e-mail valide.');
      return;
    }
    setState(() => _occupe = true);
    final statut = await widget.mail.sendPasswordResetCode(email: _email.text);
    if (!mounted) return;
    setState(() {
      _occupe = false;
      if (statut == WelcomeEmailStatus.sent) {
        _codeEnvoye = true;
        _jeton = null;
      }
    });
    _message(
      statut == WelcomeEmailStatus.sent
          ? 'Code envoyé à ${_email.text.trim()}.'
          : EmailVerificationDialog.describeSendFailure(statut),
    );
  }

  Future<void> _reinitialiser() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    setState(() => _occupe = true);
    try {
      if (!await autoriserMotDePasse(context, _verification, _nouveau.text)) {
        return;
      }
      var jeton = _jeton;
      if (jeton == null) {
        final resultat = await widget.mail.verifyCodeForToken(
          email: _email.text,
          code: _code.text,
        );
        if (!mounted) return;
        jeton = resultat.token;
        if (resultat.status != WelcomeEmailStatus.verified || jeton == null) {
          _message(
            resultat.status == WelcomeEmailStatus.invalidCode
                ? 'Code incorrect ou expiré.'
                : 'Vérification indisponible. Réessayez.',
          );
          return;
        }
        _jeton = jeton;
      }
      await auth.reinitialiserMotDePasse(
        email: _email.text.trim(),
        nouveau: _nouveau.text,
        verificationToken: jeton,
      );
      if (!mounted) return;
      _message('Mot de passe modifié. Connectez-vous.');
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) _message(auth.error ?? 'Réinitialisation impossible.');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bouton = _occupe
        ? const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(_codeEnvoye ? 'Changer le mot de passe' : 'Recevoir un code');
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublié')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                _codeEnvoye
                    ? 'Saisissez le code reçu par e-mail et votre nouveau mot de passe.'
                    : 'Nous vous envoyons un code à 6 chiffres, valable 10 minutes.',
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _email,
                enabled: !_codeEnvoye,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Adresse e-mail',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                validator: Validators.email,
              ),
              if (_codeEnvoye) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Code à 6 chiffres',
                    prefixIcon: Icon(Icons.pin_outlined),
                    counterText: '',
                  ),
                  validator: (value) => (value ?? '').trim().length == 6
                      ? null
                      : 'Saisissez le code à 6 chiffres.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nouveau,
                  obscureText: _masque,
                  decoration: InputDecoration(
                    labelText: 'Nouveau mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _masque = !_masque),
                      icon: Icon(
                        _masque
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  onChanged: _verification.surSaisie,
                  validator: Validators.nouveauMotDePasse,
                ),
                ChangeNotifierProvider.value(
                  value: _verification,
                  child: const IndicateurMotDePasse(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmation,
                  obscureText: _masque,
                  decoration: const InputDecoration(
                    labelText: 'Confirmer le mot de passe',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (value) => value != _nouveau.text
                      ? 'Les mots de passe ne correspondent pas.'
                      : null,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _occupe
                    ? null
                    : (_codeEnvoye ? _reinitialiser : _envoyerCode),
                child: bouton,
              ),
              if (_codeEnvoye)
                TextButton(
                  onPressed: _occupe ? null : _envoyerCode,
                  child: const Text('Renvoyer le code'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
