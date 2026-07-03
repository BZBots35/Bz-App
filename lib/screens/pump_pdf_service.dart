import 'dart:typed_data';
import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:appwrite/models.dart' as models;

class PumpPdfService {
  // ── Couleurs BZBots ───────────────────────────
  static const _cyan    = PdfColor.fromInt(0xFF22D3EE);
  static const _cyanD   = PdfColor.fromInt(0xFF0891B2);
  static const _purple  = PdfColor.fromInt(0xFFA855F7);
  static const _green   = PdfColor.fromInt(0xFF22C55E);
  static const _orange  = PdfColor.fromInt(0xFFF97316);
  static const _red     = PdfColor.fromInt(0xFFEF4444);
  static const _grey    = PdfColor.fromInt(0xFF6B7280);
  static const _greyL   = PdfColor.fromInt(0xFFF3F4F6);
  static const _dark    = PdfColor.fromInt(0xFF1F2937);
  static const _white   = PdfColors.white;

  // ── Helpers ───────────────────────────────────
  pw.Widget _divider({PdfColor color = const PdfColor.fromInt(0xFFE5E7EB)}) =>
    pw.Container(height: 1, color: color, margin:
      const pw.EdgeInsets.symmetric(vertical: 6));

  pw.Widget _badge(String text, PdfColor bg, PdfColor fg,
      pw.Font bold) =>
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: pw.BoxDecoration(color: bg,
        borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Text(text, style: pw.TextStyle(
        font: bold, fontSize: 8, color: fg)));

  pw.Widget _sectionTitle(String text, PdfColor color,
      pw.Font bold) =>
    pw.Container(
      margin: const pw.EdgeInsets.only(top: 14, bottom: 6),
      padding: const pw.EdgeInsets.only(left: 10, top: 6, bottom: 6),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Text(text.toUpperCase(),
        style: pw.TextStyle(font: bold, fontSize: 9,
          color: _white, letterSpacing: 1.5)));

  pw.Widget _infoRow(String label, String value,
      pw.Font font, pw.Font bold, {PdfColor? valueColor}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(children: [
        pw.SizedBox(width: 140,
          child: pw.Text(label, style: pw.TextStyle(
            font: font, fontSize: 9, color: _grey))),
        pw.Expanded(child: pw.Text(value, style: pw.TextStyle(
          font: bold, fontSize: 9,
          color: valueColor ?? _dark))),
      ]));

  pw.Widget _statBox(String label, String value,
      PdfColor color, pw.Font font, pw.Font bold) =>
    pw.Expanded(child: pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 4),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _greyL,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: color, width: 1.5)),
      child: pw.Column(children: [
        pw.Text(value, style: pw.TextStyle(
          font: bold, fontSize: 18, color: color)),
        pw.SizedBox(height: 2),
        pw.Text(label, style: pw.TextStyle(
          font: font, fontSize: 7, color: _grey),
          textAlign: pw.TextAlign.center),
      ])));

  String _rapportRef(String nom) {
    final now = DateTime.now();
    final ref = '${now.year}${now.month.toString().padLeft(2,'0')}'
                '${now.day.toString().padLeft(2,'0')}-'
                '${nom.replaceAll(' ', '').toUpperCase().substring(0, math.min(4, nom.length))}';
    return ref;
  }

  String _dateStr() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2,'0')}/'
           '${now.month.toString().padLeft(2,'0')}/${now.year}';
  }

  // ══════════════════════════════════════════════
  // RAPPORT PAR CANALISATION
  // ══════════════════════════════════════════════
  Future<Uint8List> generateRowReport({
    required models.Document chantierDoc,
    required models.Document canalisation,
    required String resinType,
    required double epaisseur,
    required String operateur,
    required double Function(double, double, int) calcResin,
  }) async {
    final pdf   = pw.Document();
    final bold  = await PdfGoogleFonts.robotoBold();
    final font  = await PdfGoogleFonts.robotoRegular();
    final ch    = chantierDoc.data;
    final d     = canalisation.data;
    final lon   = double.tryParse(d['longueur'] as String? ?? '0') ?? 0;
    final dia   = double.tryParse(d['diametre'] as String? ?? '100') ?? 100;
    final passes = d['passes'] as int? ?? 4;
    final resin  = calcResin(lon, dia, passes);
    final partA  = resin * (2/3);
    final partB  = resin * (1/3);
    final epaisseurTotale = epaisseur * passes;
    final Q      = 0.5;
    final timeMins = resin > 0 ? resin / Q : 0.0;
    final hrs    = (timeMins / 60).floor();
    final mins   = (timeMins % 60).floor();
    final secs   = ((timeMins % 1) * 60).round();
    final timeStr = hrs > 0 ? '${hrs}h ${mins}min' : '${mins}min ${secs}s';
    final resinName = resinType == 'spraycoat_plus'
      ? 'Spraycoat+' : 'Spraycoat Flex';
    final ref    = _rapportRef(ch['nom'] ?? 'CH');
    final date   = _dateStr();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(0),
      build: (ctx) => pw.Column(children: [

        // ── Page de garde ──────────────────────
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.fromLTRB(32, 24, 32, 20),
          decoration: pw.BoxDecoration(color: _dark),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
              pw.Text('BZBOTS', style: pw.TextStyle(
                font: bold, fontSize: 22, color: _cyan,
                letterSpacing: 3)),
              pw.Text('Système de résinage par projection',
                style: pw.TextStyle(font: font, fontSize: 9,
                  color: _grey)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
              pw.Text('RAPPORT D\'INSPECTION',
                style: pw.TextStyle(font: bold, fontSize: 11,
                  color: _white, letterSpacing: 1)),
              pw.Text('Réf. $ref',
                style: pw.TextStyle(font: font, fontSize: 9,
                  color: _cyan)),
              pw.Text(date, style: pw.TextStyle(
                font: font, fontSize: 9, color: _grey)),
            ]),
          ])),

        // ── Corps du document ──────────────────
        pw.Expanded(child: pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(32, 20, 32, 0),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [

            // Titre canalisation
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: _cyan.shade(0.1),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: _cyan, width: 1.5)),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                  pw.Text('CANALISATION — ${d['label'] ?? 'N/A'}',
                    style: pw.TextStyle(font: bold, fontSize: 14,
                      color: _dark)),
                  pw.SizedBox(height: 3),
                  pw.Text('DN${dia.toInt()} • ${lon}m • $passes passes',
                    style: pw.TextStyle(font: font, fontSize: 10,
                      color: _grey)),
                ]),
                _badge('✓ TERMINÉE', _green, _white, bold),
              ])),
            pw.SizedBox(height: 14),

            // Infos chantier
            _sectionTitle('Informations Chantier', _cyanD, bold),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: _greyL,
                borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Row(children: [
                pw.Expanded(child: pw.Column(children: [
                  _infoRow('Nom du chantier',
                    ch['nom'] ?? '—', font, bold),
                  _infoRow('Adresse',
                    '${ch['rue'] ?? ''} ${ch['ville'] ?? ''}',
                    font, bold),
                  _infoRow('Bâtiment',
                    ch['batiment'] ?? '—', font, bold),
                ])),
                pw.SizedBox(width: 20),
                pw.Expanded(child: pw.Column(children: [
                  _infoRow('Date', ch['date'] ?? date, font, bold),
                  _infoRow('Opérateur', operateur, font, bold),
                  _infoRow('Société', ch['company'] ?? '—', font, bold),
                ])),
              ])),
            pw.SizedBox(height: 4),

            // Paramètres résinage
            _sectionTitle('Paramètres de Résinage', _purple, bold),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: _greyL,
                borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Row(children: [
                pw.Expanded(child: pw.Column(children: [
                  _infoRow('Type de résine', resinName, font, bold,
                    valueColor: _purple),
                  _infoRow('Épaisseur par passe',
                    '${epaisseur.toStringAsFixed(2)} mm', font, bold),
                  _infoRow('Nombre de passes', '$passes', font, bold),
                ])),
                pw.SizedBox(width: 20),
                pw.Expanded(child: pw.Column(children: [
                  _infoRow('Épaisseur totale',
                    '${epaisseurTotale.toStringAsFixed(2)} mm',
                    font, bold, valueColor: _dark),
                  _infoRow('Diamètre', 'DN${dia.toInt()}', font, bold),
                  _infoRow('Longueur', '${lon}m', font, bold),
                ])),
              ])),
            pw.SizedBox(height: 4),

            // Bilan résine
            _sectionTitle('Bilan Résine', _orange, bold),
            pw.Row(children: [
              _statBox('Volume total', '${resin.toStringAsFixed(2)} L',
                _orange, font, bold),
              _statBox('Composant A (2/3)',
                '${partA.toStringAsFixed(2)} L', _cyan, font, bold),
              _statBox('Composant B (1/3)',
                '${partB.toStringAsFixed(2)} L', _purple, font, bold),
              _statBox("Temps d'injection", timeStr,
                _green, font, bold),
            ]),
            pw.SizedBox(height: 14),

            // Barre progression passes
            _sectionTitle('Séquence d\'Injection', _dark, bold),
            pw.Row(children: List.generate(passes, (i) =>
              pw.Expanded(child: pw.Container(
                margin: const pw.EdgeInsets.symmetric(horizontal: 2),
                height: 24,
                decoration: pw.BoxDecoration(
                  color: _green,
                  borderRadius: pw.BorderRadius.circular(4)),
                child: pw.Center(child: pw.Text('Passe ${i+1}',
                  style: pw.TextStyle(font: bold,
                    fontSize: 7, color: _white))),
              )))),
            pw.SizedBox(height: 4),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: _green.shade(0.1),
                borderRadius: pw.BorderRadius.circular(4),
                border: pw.Border.all(color: _green)),
              child: pw.Center(child: pw.Text(
                '✓ Toutes les passes effectuées avec succès',
                style: pw.TextStyle(font: bold, fontSize: 9,
                  color: _green)))),

            pw.Spacer(),

            // Section signatures
            _sectionTitle('Validation', _dark, bold),
            pw.Row(children: [
              pw.Expanded(child: pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _grey),
                  borderRadius: pw.BorderRadius.circular(6)),
                child: pw.Column(children: [
                  pw.Text('Opérateur', style: pw.TextStyle(
                    font: bold, fontSize: 9, color: _grey)),
                  pw.SizedBox(height: 20),
                  pw.Container(height: 1, color: _grey),
                  pw.SizedBox(height: 4),
                  pw.Text(operateur, style: pw.TextStyle(
                    font: font, fontSize: 9, color: _dark)),
                ]))),
              pw.SizedBox(width: 16),
              pw.Expanded(child: pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _grey),
                  borderRadius: pw.BorderRadius.circular(6)),
                child: pw.Column(children: [
                  pw.Text('Responsable chantier',
                    style: pw.TextStyle(font: bold,
                      fontSize: 9, color: _grey)),
                  pw.SizedBox(height: 20),
                  pw.Container(height: 1, color: _grey),
                  pw.SizedBox(height: 4),
                  pw.Text('Signature', style: pw.TextStyle(
                    font: font, fontSize: 9, color: _grey)),
                ]))),
            ]),
          ]),
        )),

        // ── Pied de page ───────────────────────
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.fromLTRB(32, 8, 32, 8),
          color: _greyL,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
            pw.Text('BZBots Systems © ${DateTime.now().year} — Confidentiel',
              style: pw.TextStyle(font: font, fontSize: 7, color: _grey)),
            pw.Text('Réf. $ref — Page 1/1',
              style: pw.TextStyle(font: font, fontSize: 7, color: _grey)),
          ])),
      ]),
    ));
    return pdf.save();
  }

  // ══════════════════════════════════════════════
  // RAPPORT GLOBAL CHANTIER
  // ══════════════════════════════════════════════
  Future<Uint8List> generateGlobalReport({
    required models.Document chantierDoc,
    required List<models.Document> canalisations,
    required String resinType,
    required double epaisseur,
    required int desiredPasses,
    required String operateur,
  }) async {
    final pdf   = pw.Document();
    final bold  = await PdfGoogleFonts.robotoBold();
    final font  = await PdfGoogleFonts.robotoRegular();
    final ch    = chantierDoc.data;
    final date  = _dateStr();
    final ref   = _rapportRef(ch['nom'] ?? 'CH');
    final resinName = resinType == 'spraycoat_plus'
      ? 'Spraycoat+' : 'Spraycoat Flex';

    // Calculs globaux
    double totalLin = 0, totalRes = 0;
    int terminees = 0, enCours = 0, enAttente = 0;
    for (final c in canalisations) {
      final lon = double.tryParse(c.data['longueur'] as String? ?? '0') ?? 0;
      final dia = double.tryParse(c.data['diametre'] as String? ?? '100') ?? 100;
      final pas = c.data['passes'] as int? ?? desiredPasses;
      final st  = c.data['statut'] as String? ?? 'en_attente';
      totalLin += lon * pas;
      totalRes += (lon * math.pi * dia * epaisseur / 1000) * pas;
      if (st == 'termine')     terminees++;
      else if (st == 'en_cours') enCours++;
      else                       enAttente++;
    }
    final partA    = totalRes * (2/3);
    final partB    = totalRes * (1/3);
    final Q        = 0.5;
    final timeMins = totalRes > 0 ? totalRes / Q : 0.0;
    final hrs      = (timeMins / 60).floor();
    final mins     = (timeMins % 60).floor();
    final timeStr  = hrs > 0 ? '${hrs}h ${mins}min' : '${mins}min';
    final pctDone  = canalisations.isEmpty ? 0.0
      : (terminees / canalisations.length * 100);

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(0),
      header: (_) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.fromLTRB(32, 16, 32, 14),
        color: _dark,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
            pw.Text('BZBOTS', style: pw.TextStyle(
              font: bold, fontSize: 18, color: _cyan, letterSpacing: 3)),
            pw.Text('Rapport Global de Chantier',
              style: pw.TextStyle(font: font, fontSize: 9, color: _grey)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
            pw.Text(ch['nom'] ?? '', style: pw.TextStyle(
              font: bold, fontSize: 11, color: _white)),
            pw.Text('Réf. $ref — $date',
              style: pw.TextStyle(font: font, fontSize: 8, color: _cyan)),
          ]),
        ])),
      footer: (ctx) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.fromLTRB(32, 6, 32, 6),
        color: _greyL,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
          pw.Text('BZBots Systems © ${DateTime.now().year} — Document confidentiel',
            style: pw.TextStyle(font: font, fontSize: 7, color: _grey)),
          pw.Text('Page ${ctx.pageNumber}/${ctx.pagesCount}',
            style: pw.TextStyle(font: font, fontSize: 7, color: _grey)),
        ])),
      build: (ctx) => [
        pw.SizedBox(height: 20),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 32),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [

          // Infos chantier
          _sectionTitle('Informations Chantier', _cyanD, bold),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _greyL,
              borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Row(children: [
              pw.Expanded(child: pw.Column(children: [
                _infoRow('Nom', ch['nom'] ?? '—', font, bold),
                _infoRow('Ville', ch['ville'] ?? '—', font, bold),
                _infoRow('Rue', ch['rue'] ?? '—', font, bold),
              ])),
              pw.SizedBox(width: 20),
              pw.Expanded(child: pw.Column(children: [
                _infoRow('Bâtiment', ch['batiment'] ?? '—', font, bold),
                _infoRow('Date', ch['date'] ?? date, font, bold),
                _infoRow('Opérateur', operateur, font, bold),
              ])),
            ])),

          // Paramètres
          _sectionTitle('Paramètres de Résinage', _purple, bold),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _greyL,
              borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Row(children: [
              pw.Expanded(child: pw.Column(children: [
                _infoRow('Type résine', resinName, font, bold,
                  valueColor: _purple),
                _infoRow('Épaisseur/passe',
                  '${epaisseur.toStringAsFixed(2)} mm', font, bold),
              ])),
              pw.SizedBox(width: 20),
              pw.Expanded(child: pw.Column(children: [
                _infoRow('Passes souhaitées',
                  '$desiredPasses', font, bold),
                _infoRow('Épaisseur totale',
                  '${(epaisseur * desiredPasses).toStringAsFixed(2)} mm',
                  font, bold),
              ])),
            ])),

          // Bilan global
          _sectionTitle('Bilan Global', _orange, bold),
          pw.Row(children: [
            _statBox('Canalisations',
              '${canalisations.length}', _cyan, font, bold),
            _statBox('Linéaire total',
              '${totalLin.toStringAsFixed(1)} m', _dark, font, bold),
            _statBox('Résine totale',
              '${totalRes.toStringAsFixed(2)} L', _orange, font, bold),
            _statBox('Temps estimé', timeStr, _green, font, bold),
          ]),
          pw.SizedBox(height: 8),
          pw.Row(children: [
            _statBox('Comp. A (2/3)',
              '${partA.toStringAsFixed(2)} L', _cyan, font, bold),
            _statBox('Comp. B (1/3)',
              '${partB.toStringAsFixed(2)} L', _purple, font, bold),
            _statBox('Terminées', '$terminees', _green, font, bold),
            _statBox('Avancement',
              '${pctDone.toStringAsFixed(0)}%',
              pctDone == 100 ? _green : _orange, font, bold),
          ]),
          pw.SizedBox(height: 8),

          // Barre progression globale
          pw.Container(
            width: double.infinity, height: 20,
            decoration: pw.BoxDecoration(
              color: _greyL,
              borderRadius: pw.BorderRadius.circular(10)),
            child: pw.Stack(children: [
              pw.Container(
                width: (pctDone / 100) *
                  (PdfPageFormat.a4.availableWidth - 64),
                decoration: pw.BoxDecoration(
                  color: pctDone == 100 ? _green : _cyan,
                  borderRadius: pw.BorderRadius.circular(10)),
              ),
              pw.Center(child: pw.Text(
                '${pctDone.toStringAsFixed(0)}% complété',
                style: pw.TextStyle(font: bold,
                  fontSize: 8, color: _white))),
            ])),

          // Tableau canalisations
          _sectionTitle('Détail des Canalisations', _dark, bold),
          pw.Table(
            border: pw.TableBorder.all(
              color: const PdfColor.fromInt(0xFFE5E7EB), width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(0.4),
              1: const pw.FlexColumnWidth(1.8),
              2: const pw.FlexColumnWidth(0.8),
              3: const pw.FlexColumnWidth(0.8),
              4: const pw.FlexColumnWidth(0.6),
              5: const pw.FlexColumnWidth(1.0),
              6: const pw.FlexColumnWidth(0.8),
            },
            children: [
              // Header
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _dark),
                children: ['#','Libellé','Long.','Diam.',
                  'Passes','Résine (L)','Statut']
                  .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 5, vertical: 5),
                    child: pw.Text(h, style: pw.TextStyle(
                      font: bold, fontSize: 7, color: _white))))
                  .toList()),
              // Lignes
              ...canalisations.asMap().entries.map((e) {
                final d   = e.value.data;
                final lon = double.tryParse(
                  d['longueur'] as String? ?? '0') ?? 0;
                final dia = double.tryParse(
                  d['diametre'] as String? ?? '100') ?? 100;
                final pas = d['passes'] as int? ?? desiredPasses;
                final res = (lon * math.pi * dia * epaisseur / 1000) * pas;
                final st  = d['statut'] as String? ?? 'en_attente';
                PdfColor stColor;
                String   stLabel;
                switch (st) {
                  case 'termine':
                    stColor = _green; stLabel = '✓ Terminé'; break;
                  case 'en_cours':
                    stColor = _orange; stLabel = '● En cours'; break;
                  default:
                    stColor = _grey; stLabel = '○ Attente'; break;
                }
                final rowBg = e.key % 2 == 0
                  ? _white : _greyL;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: rowBg),
                  children: [
                    _tcell('${e.key+1}', font, _grey),
                    _tcell(d['label'] as String? ?? '—', bold, _dark),
                    _tcell('${lon}m', font, _dark),
                    _tcell('DN${dia.toInt()}', font, _dark),
                    _tcell('$pas', font, _dark),
                    _tcell(res.toStringAsFixed(2), bold, _orange),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                      child: pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 4, vertical: 3),
                        decoration: pw.BoxDecoration(
                          color: stColor,
                          borderRadius: pw.BorderRadius.circular(3)),
                        child: pw.Text(stLabel,
                          style: pw.TextStyle(font: bold,
                            fontSize: 6, color: _white),
                          textAlign: pw.TextAlign.center))),
                  ]);
              }),
            ]),
          pw.SizedBox(height: 16),

          // Signatures
          _sectionTitle('Validation & Signatures', _dark, bold),
          pw.Row(children: [
            pw.Expanded(child: pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _grey),
                borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                pw.Text('Opérateur',
                  style: pw.TextStyle(font: bold,
                    fontSize: 9, color: _grey)),
                pw.SizedBox(height: 30),
                pw.Container(height: 1, color: _grey),
                pw.SizedBox(height: 4),
                pw.Text(operateur, style: pw.TextStyle(
                  font: font, fontSize: 9, color: _dark)),
                pw.Text(date, style: pw.TextStyle(
                  font: font, fontSize: 8, color: _grey)),
              ]))),
            pw.SizedBox(width: 16),
            pw.Expanded(child: pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _grey),
                borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                pw.Text('Responsable chantier',
                  style: pw.TextStyle(font: bold,
                    fontSize: 9, color: _grey)),
                pw.SizedBox(height: 30),
                pw.Container(height: 1, color: _grey),
                pw.SizedBox(height: 4),
                pw.Text('Nom & Signature',
                  style: pw.TextStyle(font: font,
                    fontSize: 9, color: _grey)),
              ]))),
            pw.SizedBox(width: 16),
            pw.Expanded(child: pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: pctDone == 100
                  ? _green.shade(0.1) : _orange.shade(0.1),
                border: pw.Border.all(
                  color: pctDone == 100 ? _green : _orange),
                borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                pw.Text(pctDone == 100
                  ? '✓ CHANTIER TERMINÉ'
                  : '● EN COURS',
                  style: pw.TextStyle(font: bold, fontSize: 10,
                    color: pctDone == 100 ? _green : _orange)),
                pw.SizedBox(height: 8),
                pw.Text(
                  '$terminees/${canalisations.length} canalisations',
                  style: pw.TextStyle(font: font,
                    fontSize: 9, color: _grey)),
              ]))),
          ]),
        ])),
      ],
    ));
    return pdf.save();
  }

  pw.Widget _tcell(String text, pw.Font font, PdfColor color) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 5, vertical: 5),
      child: pw.Text(text, style: pw.TextStyle(
        font: font, fontSize: 8, color: color)));

  Future<void> sharePdf(Uint8List bytes, String filename) async {
    await Printing.sharePdf(bytes: bytes, filename: '$filename.pdf');
  }
}