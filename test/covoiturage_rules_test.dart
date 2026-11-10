import 'package:flutter_test/flutter_test.dart';
import 'package:studenthub/models/covoiturage_trajet.dart';
import 'package:studenthub/models/enums_covoiturage.dart';
import 'package:studenthub/models/reservation_trajet.dart';
import 'package:studenthub/services/covoiturage_rules.dart';

CovoiturageTrajet trajet({TypeTrajetEnum type = TypeTrajetEnum.offre, StatutTrajetEnum statut = StatutTrajetEnum.ouvert}) => CovoiturageTrajet(id: 't', auteurId: 'auteur', auteurNom: 'Amina', type: type, depart: 'Tunis', arrivee: 'ESPRIT', zone: 'Tunis', date: '2030-01-01', heure: '08:00', places: 3, statut: statut);
ReservationTrajet reservation(String id, String user, StatutReservationEnum statut, {int places = 1}) => ReservationTrajet(id: id, trajetId: 't', participantId: user, participantNom: user, placesReservees: places, dateCreation: '2029-01-01', statut: statut);

void main() {
  test('RG7 calcule les places restantes et refuse un dépassement', () { final rs = [reservation('r', 'p', StatutReservationEnum.confirmee, places: 2)]; expect(CovoiturageRules.placesRestantes(trajet(), rs), 1); expect(CovoiturageRules.peutReserver(trajet: trajet(), userId: 'x', places: 2, reservations: rs), isFalse); });
  test('RG9 et RG10 verrouillent le type et interdisent sa propre annonce', () { expect(CovoiturageRules.typeModifiable(trajet(), TypeTrajetEnum.offre), isTrue); expect(CovoiturageRules.typeModifiable(trajet(), TypeTrajetEnum.demande), isFalse); expect(CovoiturageRules.peutReserver(trajet: trajet(), userId: 'auteur', places: 1, reservations: []), isFalse); });
  test('RG11 refuse les autres propositions en attente', () { final autres = CovoiturageRules.refusAutomatiqueAutres('a', [reservation('a', 'x', StatutReservationEnum.confirmee), reservation('b', 'y', StatutReservationEnum.enAttente)]); expect(autres.single.statut, StatutReservationEnum.refusee); });
  test('RG12 à RG15 : départ, zone, notification et notation', () { expect(CovoiturageRules.peutAnnuler(trajet(), DateTime(2029)), isTrue); expect(CovoiturageRules.estDansZone('tunis', 'Tunis'), isTrue); expect(CovoiturageRules.peutNotifier(destinataireId: 'a', auteurActionId: 'a'), isFalse); final fini = trajet(statut: StatutTrajetEnum.termine); final rs = [reservation('r', 'passager', StatutReservationEnum.confirmee)]; expect(CovoiturageRules.peutEvaluer(trajet: fini, evaluateurId: 'passager', evalueId: 'auteur', reservations: rs, dejaEvalue: false), isTrue); expect(CovoiturageRules.peutEvaluer(trajet: fini, evaluateurId: 'passager', evalueId: 'auteur', reservations: rs, dejaEvalue: true), isFalse); });
}
