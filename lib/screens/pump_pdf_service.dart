import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:appwrite/models.dart' as models;

class PumpPdfService {
  // ── Couleurs BZBots (Palette modernisée & contrastée) ──────────
  static const _cyan    = PdfColor.fromInt(0xFF0891B2); // Plus profond pour le print
  static const _cyanLight = PdfColor.fromInt(0xFFE0F2FE);
  static const _purple  = PdfColor.fromInt(0xFF9333EA);
  static const _green   = PdfColor.fromInt(0xFF16A34A);
  static const _greenLight = PdfColor.fromInt(0xFFDCFCE7);
  static const _orange  = PdfColor.fromInt(0xFFEA580C);
  static const _red     = PdfColor.fromInt(0xFFDC2626);
  static const _grey    = PdfColor.fromInt(0xFF4B5563);
  static const _greyL   = PdfColor.fromInt(0xFFF9FAFB);
  static const _greyBorder = PdfColor.fromInt(0xFFE5E7EB);
  static const _dark    = PdfColor.fromInt(0xFF111827);
  static const _white   = PdfColors.white;

  // ── Helpers de mise en page ──────────────────
  pw.Widget _sectionTitle(String text, PdfColor color, pw.Font bold) =>
    pw.Container(
      margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(text.toUpperCase(),
            style: pw.TextStyle(font: bold, fontSize: 8.5,
              color: _white, letterSpacing: 1.2)),
        ],
      ),
    );

  pw.Widget _badge(String text, PdfColor bg, PdfColor fg, pw.Font bold) =>
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Text(text, style: pw.TextStyle(
        font: bold, fontSize: 8, color: fg)));

  pw.Widget _infoRow(String label, String value, pw.Font font, pw.Font bold, {PdfColor? valueColor}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
      child: pw.Row(children: [
        pw.SizedBox(width: 130,
          child: pw.Text(label, style: pw.TextStyle(
            font: font, fontSize: 8.5, color: _grey))),
        pw.Expanded(child: pw.Text(value, style: pw.TextStyle(
          font: bold, fontSize: 8.5,
          color: valueColor ?? _dark))),
      ]));

  pw.Widget _statBox(String label, String value, PdfColor color, pw.Font font, pw.Font bold) =>
    pw.Expanded(child: pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 3),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: _greyL,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _greyBorder, width: 1)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(
            font: font, fontSize: 7, color: _grey)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(
            font: bold, fontSize: 14, color: color)),
        ],
      ),
    ));

  // ── Courbe épaisseur/métrage ──────────────────
  pw.Widget _thicknessChart(
    String passLabel,
    List<dynamic> rawPoints,
    double targetEpaisseur,
    pw.Font font,
    pw.Font bold,
  ) {
    if (rawPoints.length < 2) return pw.SizedBox();

    final pts = rawPoints
        .map((p) => (p as List)
            .map((e) => (e as num).toDouble())
            .toList())
        .toList();

    final maxX = pts.last[0] <= 0 ? 1.0 : pts.last[0];
    final maxYData = pts.map((p) => p[1]).reduce(math.max);
    final maxY = math.max(maxYData, targetEpaisseur) * 1.25;

    const chartW = 480.0;
    const chartH = 110.0;
    const padTop = 10.0;
    const padLeft = 30.0;
    const padBottom = 16.0;
    const yTickCount = 4;
    const xTickCount = 5;
    final plotW = chartW - padLeft;
    final plotH = chartH;
    const totalH = padTop + chartH + padBottom;

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _greyL,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _greyBorder)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(passLabel,
              style: pw.TextStyle(font: bold, fontSize: 9, color: _dark)),
          pw.SizedBox(height: 6),
          pw.Stack(
            children: [
              pw.SizedBox(
                width: chartW,
                height: totalH,
                child: pw.CustomPaint(
                  size: const PdfPoint(chartW, totalH),
                  painter: (PdfGraphics canvas, PdfPoint size) {
                    canvas.setColor(_greyBorder);
                    canvas.setLineWidth(0.3);
                    for (int i = 0; i <= yTickCount; i++) {
                      final y = padBottom + plotH * i / yTickCount;
                      canvas.drawLine(padLeft, y, chartW, y);
                    }
                    canvas.strokePath();

                    for (int i = 0; i <= xTickCount; i++) {
                      final x = padLeft + plotW * i / xTickCount;
                      canvas.drawLine(x, padBottom, x, padBottom + plotH);
                    }
                    canvas.strokePath();

                    canvas.setColor(_dark);
                    canvas.setLineWidth(0.8);
                    canvas.drawLine(padLeft, padBottom, padLeft, padBottom + plotH);
                    canvas.drawLine(padLeft, padBottom, chartW, padBottom);
                    canvas.strokePath();

                    final yTarget = padBottom + (targetEpaisseur / maxY) * plotH;
                    canvas.setColor(_orange);
                    canvas.setLineWidth(0.8);
                    double dx = padLeft;
                    while (dx < chartW) {
                      canvas.drawLine(dx, yTarget, dx + 4, yTarget);
                      dx += 8;
                    }
                    canvas.strokePath();

                    canvas.setColor(_cyan);
                    canvas.setLineWidth(1.5);
                    for (int i = 0; i < pts.length; i++) {
                      final x = padLeft + (pts[i][0] / maxX) * plotW;
                      final y = padBottom + (pts[i][1] / maxY) * plotH;
                      if (i == 0) {
                        canvas.moveTo(x, y);
                      } else {
                        canvas.lineTo(x, y);
                      }
                    }
                    canvas.strokePath();
                  },
                ),
              ),
              pw.Positioned(
                left: 0,
                top: 0,
                child: pw.Text('Ép. (mm)',
                    style: pw.TextStyle(font: bold, fontSize: 6.5, color: _grey)),
              ),
              for (int i = 0; i <= yTickCount; i++)
                pw.Positioned(
                  left: 0,
                  top: padTop + chartH - (plotH * i / yTickCount) - 4,
                  child: pw.SizedBox(
                    width: padLeft - 4,
                    child: pw.Text(
                      (maxY * i / yTickCount).toStringAsFixed(1),
                      style: pw.TextStyle(font: font, fontSize: 6, color: _grey),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                ),
              for (int i = 0; i <= xTickCount; i++)
                pw.Positioned(
                  left: padLeft + (plotW * i / xTickCount) - 12,
                  top: padTop + chartH + 2,
                  child: pw.SizedBox(
                    width: 24,
                    child: pw.Text(
                      (maxX * i / xTickCount).toStringAsFixed(1),
                      style: pw.TextStyle(font: font, fontSize: 6, color: _grey),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Métrage (m)',
                style: pw.TextStyle(font: bold, fontSize: 6.5, color: _grey)),
          ),
          pw.SizedBox(height: 6),
          pw.Row(children: [
            pw.Container(width: 10, height: 2, color: _cyan),
            pw.SizedBox(width: 4),
            pw.Text('Mesuré', style: pw.TextStyle(font: font, fontSize: 7, color: _grey)),
            pw.SizedBox(width: 12),
            pw.Container(width: 10, height: 2, color: _orange),
            pw.SizedBox(width: 4),
            pw.Text('Cible : ${targetEpaisseur.toStringAsFixed(2)} mm', style: pw.TextStyle(font: font, fontSize: 7, color: _grey)),
          ]),
        ],
      ),
    );
  }

  pw.Widget _thicknessSection(String? passesDataJson, double targetEpaisseur, pw.Font font, pw.Font bold) {
    if (passesDataJson == null || passesDataJson.isEmpty) return pw.SizedBox();
    Map<String, dynamic> passesData;
    try {
      passesData = Map<String, dynamic>.from(jsonDecode(passesDataJson));
    } catch (_) {
      return pw.SizedBox();
    }
    if (passesData.isEmpty) return pw.SizedBox();

    final sortedKeys = passesData.keys.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Épaisseur appliquée mesurée', _cyan, bold),
        ...sortedKeys.map((k) => _thicknessChart(
              'Passe N°$k', passesData[k] as List, targetEpaisseur, font, bold)),
      ],
    );
  }

  String _rapportRef(String nom) {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}-${nom.replaceAll(' ', '').toUpperCase().substring(0, math.min(4, nom.length))}';
  }

  String _dateStr() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2,'0')}/${now.month.toString().padLeft(2,'0')}/${now.year}';
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
    final passesDataJson = d['passesData'] as String?;
    final resinAppliedRaw = d['resinAppliedTotal'];
    final resinApplied = resinAppliedRaw != null ? (resinAppliedRaw as num).toDouble() : null;
    final resin  = calcResin(lon, dia, passes);
    final partA  = resin * (2/3);
    final partB  = resin * (1/3);
    final epaisseurTotale = epaisseur * passes;
    final timeMins = resin > 0 ? resin / 0.5 : 0.0;
    final hrs    = (timeMins / 60).floor();
    final mins   = (timeMins % 60).floor();
    final timeStr = hrs > 0 ? '${hrs}h ${mins}min' : '${mins}min';
    final resinName = resinType == 'spraycoat_plus' ? 'Spraycoat+' : 'Spraycoat Flex';
    final ref    = _rapportRef(ch['nom'] ?? 'CH');
    final date   = _dateStr();
    final tempExt = ch['tempExt'] as String? ?? 'Non renseignée';
    final meteo   = ch['meteo'] as String? ?? 'Non renseignées';

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => ctx.pageNumber == 1
        ? pw.SizedBox()
        : pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('BZBOTS — Rapport d\'inspection (Suite)', style: pw.TextStyle(font: bold, fontSize: 8, color: _grey)),
              pw.Text('Réf. $ref', style: pw.TextStyle(font: font, fontSize: 8, color: _grey)),
            ],
          ),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: pw.TextStyle(font: font, fontSize: 8, color: _grey)),
      ),
      build: (ctx) => [
        // En-tête de page 1 propre et structuré
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: _dark,
            borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('BZBOTS', style: pw.TextStyle(font: bold, fontSize: 18, color: _white, letterSpacing: 2)),
                pw.SizedBox(height: 2),
                pw.Text('Rapport d\'intervention technique', style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.grey400)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('Réf : $ref', style: pw.TextStyle(font: bold, fontSize: 9, color: _white)),
                pw.SizedBox(height: 2),
                pw.Text('Date : $date', style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.grey400)),
              ]),
            ],
          ),
        ),
        pw.SizedBox(height: 14),

        // Titre Canalisation
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: _cyanLight,
            borderRadius: pw.BorderRadius.circular(6),
            border: pw.Border.all(color: _cyan, width: 1)),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('CANALISATION : ${d['label'] ?? 'N/A'}',
                  style: pw.TextStyle(font: bold, fontSize: 12, color: _dark)),
                pw.SizedBox(height: 2),
                pw.Text('DN${dia.toInt()}  •  ${lon}m  •  $passes passes',
                  style: pw.TextStyle(font: font, fontSize: 8.5, color: _grey)),
              ]),
              _badge('TERMINÉE', _green, _white, bold),
            ],
          ),
        ),

        // Infos Chantier & Paramètres
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _sectionTitle('Chantier', _cyan, bold),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(color: _greyL, borderRadius: pw.BorderRadius.circular(6), border: pw.Border.all(color: _greyBorder)),
              child: pw.Column(children: [
                _infoRow('Nom', ch['nom'] ?? '—', font, bold),
                _infoRow('Adresse', '${ch['rue'] ?? ''} ${ch['ville'] ?? ''}', font, bold),
                _infoRow('Opérateur', operateur, font, bold),
                _infoRow('Température ext.', tempExt, font, bold),
                _infoRow('Conditions météo', meteo, font, bold),
              ]),
            ),
          ])),
          pw.SizedBox(width: 10),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _sectionTitle('Paramètres Résinage', _purple, bold),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(color: _greyL, borderRadius: pw.BorderRadius.circular(6), border: pw.Border.all(color: _greyBorder)),
              child: pw.Column(children: [
                _infoRow('Produit', resinName, font, bold, valueColor: _purple),
                _infoRow('Épaisseur', '${epaisseur.toStringAsFixed(2)} mm / passe', font, bold),
                _infoRow('Total', '${epaisseurTotale.toStringAsFixed(2)} mm', font, bold),
              ]),
            ),
          ])),
        ]),

        // Bilan Résine
        _sectionTitle('Bilan Consommation', _orange, bold),
        pw.Row(children: [
          _statBox('Théorique', '${resin.toStringAsFixed(2)} L', _orange, font, bold),
          _statBox('Composant A', '${partA.toStringAsFixed(2)} L', _cyan, font, bold),
          _statBox('Composant B', '${partB.toStringAsFixed(2)} L', _purple, font, bold),
          _statBox('Temps estimé', timeStr, _green, font, bold),
        ]),
        if (resinApplied != null) ...[
          pw.SizedBox(height: 6),
          pw.Row(children: [
            _statBox('Réel mesuré', '${resinApplied.toStringAsFixed(2)} L', _green, font, bold),
            _statBox('Écart', '${(resinApplied - resin) >= 0 ? '+' : ''}${(resinApplied - resin).toStringAsFixed(2)} L', 
              (resinApplied - resin).abs() / (resin == 0 ? 1 : resin) > 0.1 ? _red : _green, font, bold),
            _statBox('Écart %', resin > 0 ? '${((resinApplied - resin) / resin * 100).toStringAsFixed(1)}%' : '—', 
              (resinApplied - resin).abs() / (resin == 0 ? 1 : resin) > 0.1 ? _red : _green, font, bold),
            pw.Expanded(child: pw.SizedBox()), // Spacer
          ]),
        ],

        // Courbes d'épaisseur
        _thicknessSection(passesDataJson, epaisseur, font, bold),

        pw.SizedBox(height: 14),
        // Signatures
        _sectionTitle('Validation', _dark, bold),
        pw.Row(children: [
          pw.Expanded(child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _greyBorder), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(children: [
              pw.Text('Opérateur', style: pw.TextStyle(font: bold, fontSize: 8, color: _grey)),
              pw.SizedBox(height: 24),
              pw.Container(height: 1, color: _greyBorder),
              pw.SizedBox(height: 4),
              pw.Text(operateur, style: pw.TextStyle(font: font, fontSize: 8, color: _dark)),
            ]),
          )),
          pw.SizedBox(width: 10),
          pw.Expanded(child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _greyBorder), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(children: [
              pw.Text('Responsable Chantier', style: pw.TextStyle(font: bold, fontSize: 8, color: _grey)),
              pw.SizedBox(height: 24),
              pw.Container(height: 1, color: _greyBorder),
              pw.SizedBox(height: 4),
              pw.Text('Validation client', style: pw.TextStyle(font: font, fontSize: 8, color: _grey)),
            ]),
          )),
        ]),
      ],
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
    final resinName = resinType == 'spraycoat_plus' ? 'Spraycoat+' : 'Spraycoat Flex';

    double totalLin = 0, totalRes = 0;
    int terminees = 0;
    for (final c in canalisations) {
      final lon = double.tryParse(c.data['longueur'] as String? ?? '0') ?? 0;
      final dia = double.tryParse(c.data['diametre'] as String? ?? '100') ?? 100;
      final pas = c.data['passes'] as int? ?? desiredPasses;
      totalLin += lon * pas;
      totalRes += (lon * math.pi * dia * epaisseur / 1000) * pas;
      if (c.data['statut'] == 'termine') terminees++;
    }
    final partA    = totalRes * (2/3);
    final partB    = totalRes * (1/3);
    final timeMins = totalRes > 0 ? totalRes / 0.5 : 0.0;
    final hrs      = (timeMins / 60).floor();
    final mins     = (timeMins % 60).floor();
    final timeStr  = hrs > 0 ? '${hrs}h ${mins}min' : '${mins}min';
    final pctDone  = canalisations.isEmpty ? 0.0 : (terminees / canalisations.length * 100);
    final tempExt = ch['tempExt'] as String? ?? 'Non renseignée';
    final meteo   = ch['meteo'] as String? ?? 'Non renseignées';
    
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('BZBOTS — Rapport Global Chantier', style: pw.TextStyle(font: bold, fontSize: 8, color: _grey)),
          pw.Text('Réf. $ref', style: pw.TextStyle(font: font, fontSize: 8, color: _grey)),
        ],
      ),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: pw.TextStyle(font: font, fontSize: 8, color: _grey)),
      ),
      build: (ctx) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(color: _dark, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('BZBOTS', style: pw.TextStyle(font: bold, fontSize: 18, color: _white, letterSpacing: 2)),
                pw.SizedBox(height: 2),
                pw.Text('Rapport Synthétique Global', style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.grey400)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text(ch['nom'] ?? '', style: pw.TextStyle(font: bold, fontSize: 10, color: _white)),
                pw.SizedBox(height: 2),
                pw.Text('Réf : $ref  •  $date', style: pw.TextStyle(font: font, fontSize: 8, color: _cyanLight)),
              ]),
            ],
          ),
        ),
        pw.SizedBox(height: 14),

        // Infos et Paramètres globaux
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _sectionTitle('Chantier', _cyan, bold),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(color: _greyL, borderRadius: pw.BorderRadius.circular(6), border: pw.Border.all(color: _greyBorder)),
              child: pw.Column(children: [
                _infoRow('Nom', ch['nom'] ?? '—', font, bold),
                _infoRow('Ville', ch['ville'] ?? '—', font, bold),
                _infoRow('Opérateur', operateur, font, bold),
                _infoRow('Température ext.', tempExt, font, bold),
                _infoRow('Conditions météo', meteo, font, bold),
              ]),
            ),
          ])),
          pw.SizedBox(width: 10),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _sectionTitle('Paramètres', _purple, bold),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(color: _greyL, borderRadius: pw.BorderRadius.circular(6), border: pw.Border.all(color: _greyBorder)),
              child: pw.Column(children: [
                _infoRow('Résine', resinName, font, bold, valueColor: _purple),
                _infoRow('Épaisseur', '${epaisseur.toStringAsFixed(2)} mm', font, bold),
                _infoRow('Passes cibles', '$desiredPasses', font, bold),
              ]),
            ),
          ])),
        ]),

        // Bilan Global chiffré
        _sectionTitle('Bilan Global du Projet', _orange, bold),
        pw.Row(children: [
          _statBox('Canalisations', '${canalisations.length}', _cyan, font, bold),
          _statBox('Linéaire total', '${totalLin.toStringAsFixed(1)} m', _dark, font, bold),
          _statBox('Résine totale', '${totalRes.toStringAsFixed(2)} L', _orange, font, bold),
          _statBox('Avancement', '${pctDone.toStringAsFixed(0)}%', pctDone == 100 ? _green : _orange, font, bold),
        ]),
        pw.SizedBox(height: 6),
        pw.Row(children: [
          _statBox('Composant A', '${partA.toStringAsFixed(2)} L', _cyan, font, bold),
          _statBox('Composant B', '${partB.toStringAsFixed(2)} L', _purple, font, bold),
          _statBox('Temps estimé', timeStr, _green, font, bold),
          _statBox('Terminées', '$terminees / ${canalisations.length}', _green, font, bold),
        ]),

        // Tableau récapitulatif
        _sectionTitle('Détail des Canalisations', _dark, bold),
        pw.Table(
          border: pw.TableBorder.all(color: _greyBorder, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(0.4),
            1: const pw.FlexColumnWidth(2.0),
            2: const pw.FlexColumnWidth(0.8),
            3: const pw.FlexColumnWidth(0.8),
            4: const pw.FlexColumnWidth(0.6),
            5: const pw.FlexColumnWidth(1.1),
            6: const pw.FlexColumnWidth(0.9),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _dark),
              children: ['#', 'Libellé', 'Long.', 'Diam.', 'Passes', 'Résine', 'Statut']
                .map((h) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                  child: pw.Text(h, style: pw.TextStyle(font: bold, fontSize: 7.5, color: _white))))
                .toList()),
            ...canalisations.asMap().entries.map((e) {
              final d   = e.value.data;
              final lon = double.tryParse(d['longueur'] as String? ?? '0') ?? 0;
              final dia = double.tryParse(d['diametre'] as String? ?? '100') ?? 100;
              final pas = d['passes'] as int? ?? desiredPasses;
              final res = (lon * math.pi * dia * epaisseur / 1000) * pas;
              final st  = d['statut'] as String? ?? 'en_attente';
              
              PdfColor stColor = _grey;
              String stLabel = 'Attente';
              if (st == 'termine') { stColor = _green; stLabel = 'Terminé'; }
              else if (st == 'en_cours') { stColor = _orange; stLabel = 'En cours'; }

              return pw.TableRow(
                decoration: pw.BoxDecoration(color: e.key % 2 == 0 ? _white : _greyL),
                children: [
                  _tcell('${e.key+1}', font, _grey),
                  _tcell(d['label'] as String? ?? '—', bold, _dark),
                  _tcell('${lon}m', font, _dark),
                  _tcell('DN${dia.toInt()}', font, _dark),
                  _tcell('$pas', font, _dark),
                  _tcell('${res.toStringAsFixed(2)} L', bold, _orange),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Container(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      decoration: pw.BoxDecoration(color: stColor, borderRadius: pw.BorderRadius.circular(3)),
                      child: pw.Text(stLabel, style: pw.TextStyle(font: bold, fontSize: 6.5, color: _white), textAlign: pw.TextAlign.center),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
        pw.SizedBox(height: 14),

        // Signatures Globales
        _sectionTitle('Validation Finale', _dark, bold),
        pw.Row(children: [
          pw.Expanded(child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _greyBorder), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Opérateur', style: pw.TextStyle(font: bold, fontSize: 8, color: _grey)),
              pw.SizedBox(height: 24),
              pw.Container(height: 1, color: _greyBorder),
              pw.SizedBox(height: 4),
              pw.Text(operateur, style: pw.TextStyle(font: font, fontSize: 8, color: _dark)),
            ]),
          )),
          pw.SizedBox(width: 10),
          pw.Expanded(child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _greyBorder), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Responsable Chantier', style: pw.TextStyle(font: bold, fontSize: 8, color: _grey)),
              pw.SizedBox(height: 24),
              pw.Container(height: 1, color: _greyBorder),
              pw.SizedBox(height: 4),
              pw.Text('Visa & Signature', style: pw.TextStyle(font: font, fontSize: 8, color: _grey)),
            ]),
          )),
        ]),
      ],
    ));
    return pdf.save();
  }

  pw.Widget _tcell(String text, pw.Font font, PdfColor color) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: 7.5, color: color)));

  Future<void> sharePdf(Uint8List bytes, String filename) async {
    await Printing.sharePdf(bytes: bytes, filename: '$filename.pdf');
  }
}