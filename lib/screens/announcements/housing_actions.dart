import 'package:flutter/material.dart';

import '../../models/annonce.dart';
import '../../services/api_client.dart';
import '../../services/housing_service.dart';
import '../../services/public_holidays_service.dart';
import '../../services/visit_weather_service.dart';

String formatMontant(double value) =>
    '${value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2)} DT';
String formatJour(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';
String formatHeure(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
String _two(int v) => v.toString().padLeft(2, '0');
String _isoJour(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _dateFerie(DateTime d) {
  const mois = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];
  return '${d.day} ${mois[d.month - 1]}';
}

void _message(BuildContext context, String text) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class HousingActions {
  /// Ajoute une plage de disponibilités de visite (valable pour tous les logements du propriétaire).
  static Future<bool> addAvailability(
    BuildContext context, {
    HousingService? service,
  }) async {
    final form = GlobalKey<FormState>();
    DateTime? debut, fin;
    var pays = 'TN';
    var joursFeries = <PublicHoliday>[];
    var chargementFeries = false;
    String? avertissementFeries;
    var heureDebut = const TimeOfDay(hour: 9, minute: 0);
    var heureFin = const TimeOfDay(hour: 12, minute: 0);
    final duree = TextEditingController(text: '30');
    final pause = TextEditingController(text: '0');
    final ferieService = PublicHolidaysService();
    Future<void> chargerFeries(StateSetter refresh) async {
      if (debut == null || fin == null) return;
      final start = debut!;
      final end = fin!;
      final country = pays;
      refresh(() {
        chargementFeries = true;
        avertissementFeries = null;
      });
      try {
        final dates = await ferieService.forRange(start, end, country);
        if (!context.mounted) return;
        refresh(() {
          joursFeries = dates;
          chargementFeries = false;
        });
      } catch (_) {
        if (!context.mounted) return;
        refresh(() {
          joursFeries = [];
          chargementFeries = false;
          avertissementFeries = 'Jours fériés non vérifiés : les créneaux seront générés sans filtre.';
        });
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: const Text('Nouvelle disponibilité'),
          content: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DateField(
                    label: 'Du',
                    value: debut,
                    onChanged: (d) {
                      refresh(() {
                        debut = d;
                        if (fin != null && fin!.isBefore(d)) fin = null;
                        joursFeries = [];
                      });
                      chargerFeries(refresh);
                    },
                  ),
                  _DateField(
                    label: 'Au',
                    value: fin,
                    first: debut,
                    onChanged: (d) {
                      refresh(() => fin = d);
                      chargerFeries(refresh);
                    },
                    validator: (d) =>
                        d != null && debut != null && d.isBefore(debut!)
                        ? 'Doit suivre la date de début'
                        : null,
                  ),
                  if (debut != null && fin != null) ...[
                    DropdownButtonFormField<String>(
                      initialValue: pays,
                      decoration: const InputDecoration(
                        labelText: 'Pays pour les jours fériés',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'TN',
                          child: Text('Tunisie (TN)'),
                        ),
                        DropdownMenuItem(
                          value: 'FR',
                          child: Text('France (FR) · démo'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        refresh(() => pays = value);
                        chargerFeries(refresh);
                      },
                    ),
                    if (chargementFeries)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: LinearProgressIndicator(),
                      ),
                    if (avertissementFeries != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          avertissementFeries!,
                          style: const TextStyle(color: Colors.deepOrange),
                        ),
                      ),
                    if (!chargementFeries &&
                        avertissementFeries == null &&
                        joursFeries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Aucun jour férié trouvé pour ce pays et cette période. Vous pouvez choisir un autre pays.',
                        ),
                      ),
                    ...joursFeries.map(
                      (holiday) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.event_busy,
                          color: Colors.deepOrange,
                        ),
                        title: Text(
                          '${_dateFerie(holiday.date)} : ${holiday.name}, jour exclu',
                        ),
                      ),
                    ),
                  ],
                  _TimeField(
                    label: 'De',
                    value: heureDebut,
                    onChanged: (t) => refresh(() => heureDebut = t),
                  ),
                  _TimeField(
                    label: 'À',
                    value: heureFin,
                    onChanged: (t) => refresh(() => heureFin = t),
                    validator: (t) => _minutes(t) <= _minutes(heureDebut)
                        ? 'Doit suivre l’heure de début'
                        : null,
                  ),
                  _intField(
                    duree,
                    'Durée d’une visite (minutes)',
                    min: 10,
                    max: 240,
                  ),
                  _intField(
                    pause,
                    'Pause entre visites (minutes)',
                    min: 0,
                    max: 120,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return false;
    try {
      await (service ?? HousingService()).ajouterDisponibilite({
        'startDate': _isoJour(debut!),
        'endDate': _isoJour(fin!),
        'startTime': '${_two(heureDebut.hour)}:${_two(heureDebut.minute)}',
        'endTime': '${_two(heureFin.hour)}:${_two(heureFin.minute)}',
        'durationMinutes': int.parse(duree.text),
        'breakMinutes': int.parse(pause.text),
        'excludedDates': joursFeries
            .map((holiday) => _isoJour(holiday.date))
            .toList(),
      });
      if (context.mounted) {
        _message(
          context,
          'Disponibilités enregistrées pour tous vos logements.',
        );
      }
      return true;
    } on ApiException catch (error) {
      if (context.mounted) _message(context, error.message);
      return false;
    }
  }

  static Future<void> bookVisit(BuildContext context, Annonce property) async {
    final service = HousingService();
    List<CreneauVisite> creneaux;
    try {
      creneaux = await service.creneaux(property.id);
    } on ApiException catch (error) {
      if (context.mounted) _message(context, error.message);
      return;
    }
    if (!context.mounted) return;
    if (creneaux.isEmpty) {
      _message(
        context,
        'Aucun créneau disponible pour ce logement pour le moment.',
      );
      return;
    }
    final selected = await showModalBottomSheet<CreneauVisite>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * .75,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Choisir un créneau',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ),
              ...creneaux.map(
                (s) => ListTile(
                  leading: const Icon(Icons.event_available),
                  title: Text(formatJour(s.debut)),
                  subtitle: Text(
                    '${formatHeure(s.debut)} – ${formatHeure(s.fin)}',
                  ),
                  onTap: () => Navigator.pop(ctx, s),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    final confirm = await _confirmVisit(context, property, selected);
    if (confirm != true || !context.mounted) return;
    try {
      await service.reserverVisite(property.id, selected.startAt);
      if (context.mounted) {
        _message(
          context,
          'Visite réservée le ${formatJour(selected.debut)} à ${formatHeure(selected.debut)}. Le propriétaire est prévenu.',
        );
      }
    } on ApiException catch (error) {
      if (context.mounted) _message(context, error.message);
    }
  }

  static Future<bool?> _confirmVisit(
    BuildContext context,
    Annonce property,
    CreneauVisite slot,
  ) {
    final forecast = VisitWeatherService().forecast(property.ville, slot.debut);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer la visite'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${formatJour(slot.debut)} à ${formatHeure(slot.debut)} · ${property.ville}',
            ),
            const SizedBox(height: 12),
            FutureBuilder<VisitWeather?>(
              future: forecast,
              builder: (context, snapshot) {
                final weather = snapshot.data;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: snapshot.connectionState != ConnectionState.done
                        ? const Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('Chargement de la météo…'),
                            ],
                          )
                        : weather == null || snapshot.hasError
                        ? const Text('Météo non disponible pour cette date')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                weather.description,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Température maximale : ${weather.temperatureMax} °C',
                              ),
                              Text(
                                'Probabilité de pluie : ${weather.rainProbability} %',
                              ),
                              if (weather.rainProbability > 50) ...[
                                const SizedBox(height: 8),
                                const Text(
                                  'Pluie probable : pensez à un parapluie',
                                  style: TextStyle(
                                    color: Colors.deepOrange,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  static Future<void> rent(BuildContext context, Annonce property) async {
    final form = GlobalKey<FormState>();
    DateTime? debut, fin;
    final duration = TextEditingController(text: '12');
    final message = TextEditingController();
    String frequency = 'MONTHLY', method = 'BANK_TRANSFER';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: const Text('Demande de location'),
          content: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Loyer : ${formatMontant(property.loyer)} / mois',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${property.typeLocation} · ${property.surface.toStringAsFixed(0)} m² · ${property.ville}',
                  ),
                  _DateField(
                    label: 'Date d’entrée',
                    value: debut,
                    onChanged: (d) => refresh(() => debut = d),
                  ),
                  _DateField(
                    label: 'Date de sortie',
                    value: fin,
                    first: debut,
                    onChanged: (d) => refresh(() => fin = d),
                    validator: (d) =>
                        d != null && debut != null && !d.isAfter(debut!)
                        ? 'Doit suivre la date d’entrée'
                        : null,
                  ),
                  _intField(duration, 'Durée (mois)', min: 1, max: 60),
                  DropdownButtonFormField<String>(
                    initialValue: frequency,
                    decoration: const InputDecoration(
                      labelText: 'Fréquence de paiement',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'MONTHLY',
                        child: Text('Mensuelle'),
                      ),
                      DropdownMenuItem(
                        value: 'QUARTERLY',
                        child: Text('Trimestrielle'),
                      ),
                      DropdownMenuItem(
                        value: 'SEMI_ANNUALLY',
                        child: Text('Semestrielle'),
                      ),
                      DropdownMenuItem(
                        value: 'ANNUALLY',
                        child: Text('Annuelle'),
                      ),
                    ],
                    onChanged: (v) => refresh(() => frequency = v!),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: const InputDecoration(
                      labelText: 'Mode de paiement',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'BANK_TRANSFER',
                        child: Text('Virement bancaire'),
                      ),
                      DropdownMenuItem(value: 'CHEQUE', child: Text('Chèque')),
                      DropdownMenuItem(value: 'CASH', child: Text('Espèces')),
                      DropdownMenuItem(value: 'OTHER', child: Text('Autre')),
                    ],
                    onChanged: (v) => refresh(() => method = v!),
                  ),
                  TextFormField(
                    controller: message,
                    maxLines: 2,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'Message au propriétaire',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Envoyer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await HousingService().demanderLocation({
        'annonceId': property.id,
        'startDate': _isoJour(debut!),
        'endDate': _isoJour(fin!),
        'duration': int.parse(duration.text),
        'paymentFrequency': frequency,
        'paymentMethod': method,
        'additionalMessage': message.text.trim(),
      });
      if (context.mounted) {
        _message(context, 'Demande de location envoyée au propriétaire.');
      }
    } on ApiException catch (error) {
      if (context.mounted) _message(context, error.message);
    }
  }

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  static Widget _intField(
    TextEditingController controller,
    String label, {
    required int min,
    required int max,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (v) {
        final value = int.tryParse(v?.trim() ?? '');
        if (value == null) return 'Nombre entier attendu';
        if (value < min || value > max) return 'Entre $min et $max';
        return null;
      },
    ),
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.first,
    this.validator,
  });
  final String label;
  final DateTime? value;
  final DateTime? first;
  final ValueChanged<DateTime> onChanged;
  final String? Function(DateTime?)? validator;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextFormField(
        key: ValueKey(value),
        readOnly: true,
        initialValue: value == null ? '' : formatJour(value!),
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        validator: (_) =>
            value == null ? 'Choisissez une date' : validator?.call(value),
        onTap: () async {
          final start = first != null && first!.isAfter(today) ? first! : today;
          final picked = await showDatePicker(
            context: context,
            firstDate: start,
            lastDate: today.add(const Duration(days: 365 * 6)),
            initialDate: value != null && !value!.isBefore(start)
                ? value!
                : start,
          );
          if (picked != null) onChanged(picked);
        },
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.validator,
  });
  final String label;
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;
  final String? Function(TimeOfDay)? validator;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextFormField(
      key: ValueKey(value),
      readOnly: true,
      initialValue: '${_two(value.hour)}:${_two(value.minute)}',
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.schedule, size: 18),
      ),
      validator: (_) => validator?.call(value),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: value,
        );
        if (picked != null) onChanged(picked);
      },
    ),
  );
}
