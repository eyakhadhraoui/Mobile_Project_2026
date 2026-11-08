import 'package:flutter/material.dart';

import '../../services/welcome_email_service.dart';

/// Saisie du code envoyé par e-mail. Retourne (via `Navigator.pop`) le jeton
/// de vérification délivré par le serveur, ou null si l'utilisateur abandonne.
class EmailVerificationDialog extends StatefulWidget {
  const EmailVerificationDialog({
    super.key,
    required this.email,
    required this.firstName,
    this.service = const WelcomeEmailService(),
    this.intro,
  });

  final String email;
  final String firstName;
  final WelcomeEmailService service;
  final String? intro;

  /// Envoie le code puis ouvre la boîte de dialogue. Retourne le jeton ou null,
  /// en affichant un message si l'envoi échoue.
  static Future<String?> sendAndAsk(
    BuildContext context, {
    required String email,
    required String firstName,
    String? intro,
  }) async {
    const service = WelcomeEmailService();
    final status = await service.sendWelcome(email: email, firstName: firstName);
    if (!context.mounted) return null;
    if (status != WelcomeEmailStatus.sent) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeSendFailure(status))));
      return null;
    }
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EmailVerificationDialog(email: email, firstName: firstName, intro: intro),
    );
  }

  static String describeSendFailure(WelcomeEmailStatus status) => switch (status) {
    WelcomeEmailStatus.notConfigured => 'URL e-mail absente. Configurez ACCOUNT_API_URL.',
    WelcomeEmailStatus.invalidConfiguration => 'URL invalide. En debug, utilisez http://10.0.2.2:6500.',
    WelcomeEmailStatus.serverUnavailable => 'Serveur injoignable. Lancez le serveur Node sur le port 6500.',
    WelcomeEmailStatus.serverRejected => 'Le serveur a refusé le courriel. Consultez le terminal Node.',
    _ => 'Erreur du service e-mail.',
  };

  @override
  State<EmailVerificationDialog> createState() => _EmailVerificationDialogState();
}

class _EmailVerificationDialogState extends State<EmailVerificationDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Saisissez le code à 6 chiffres.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.service.verifyCodeForToken(email: widget.email, code: _code.text);
    if (!mounted) return;
    if (result.status == WelcomeEmailStatus.verified && result.token != null) {
      Navigator.of(context).pop(result.token);
      return;
    }
    setState(() {
      _busy = false;
      _error = switch (result.status) {
        WelcomeEmailStatus.invalidCode => 'Code incorrect ou expiré.',
        WelcomeEmailStatus.verified => 'Serveur trop ancien : redémarrez le serveur Node.',
        _ => 'Vérification indisponible. Réessayez.',
      };
    });
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.service.sendWelcome(email: widget.email, firstName: widget.firstName);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result == WelcomeEmailStatus.sent ? 'Nouveau code envoyé.' : 'Impossible de renvoyer le code.';
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Vérifiez votre e-mail'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.intro != null) ...[Text(widget.intro!), const SizedBox(height: 8)],
        Text('Saisissez le code envoyé à ${widget.email}.'),
        const SizedBox(height: 12),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: 'Code à 6 chiffres'),
        ),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextButton(onPressed: _busy ? null : _resend, child: const Text('Renvoyer le code')),
      ],
    ),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Plus tard')),
      FilledButton(
        onPressed: _busy ? null : _verify,
        child: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Vérifier'),
      ),
    ],
  );
}
