// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:appwrite/models.dart' as models;
import 'lang_service.dart';

class PdfService {
  // ── Couleurs ──────────────────────────────────
  static const _cyan   = PdfColor.fromInt(0xFF22D3EE);
  static const _cyanD  = PdfColor.fromInt(0xFF0891B2);
  static const _purple = PdfColor.fromInt(0xFFA855F7);
  static const _green  = PdfColor.fromInt(0xFF22C55E);
  static const _orange = PdfColor.fromInt(0xFFF97316);
  static const _grey   = PdfColor.fromInt(0xFF6B7280);
  static const _greyL  = PdfColor.fromInt(0xFFF3F4F6);
  static const _greyM  = PdfColor.fromInt(0xFFE5E7EB);
  static const _dark   = PdfColor.fromInt(0xFF1F2937);
  static const _white  = PdfColors.white;
  static const _black  = PdfColors.black;

  // ── Traduction ───────────────────────────────────
  String _t(String key) => LangService().t(key);

  // ── Helpers date ──────────────────────────────
  String _dateStr() {
    final n = DateTime.now();
    return '${n.day.toString().padLeft(2,'0')}/${n.month.toString().padLeft(2,'0')}/${n.year}'
           ' à ${n.hour.toString().padLeft(2,'0')}:${n.minute.toString().padLeft(2,'0')}';
  }

  String _dateShort() {
    final n = DateTime.now();
    return '${n.day.toString().padLeft(2,'0')}/${n.month.toString().padLeft(2,'0')}/${n.year}';
  }

  // ── Parse données inspection ──────────────────
  Map<String, dynamic> _parseObservations(String raw) {
    final parts1 = raw.split('__CONDITIONS__');
    final parts2 = parts1[0].split('__CAPTURES__');
    final obsText = parts2[0];

    // Captures : nouvelle structure enrichie OU ancienne (liste de strings)
    List<Map<String, dynamic>> captures = [];
    if (parts2.length > 1) {
      try {
        final decoded = jsonDecode(parts2[1]);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is String) {
              // Ancien format — path seul
              captures.add({'path': item, 'code': '', 'category': '',
                'dist': '—', 'horaire': '', 'obs': '', 'time': ''});
            } else if (item is Map) {
              // Nouveau format enrichi
              captures.add(Map<String, dynamic>.from(item));
            }
          }
        }
      } catch (_) {}
    }

    Map<String, dynamic> conditions = {};
    if (parts1.length > 1) {
      try { conditions = Map<String, dynamic>.from(jsonDecode(parts1[1])); } catch (_) {}
    }
    return {'obsText': obsText, 'captures': captures, 'conditions': conditions};
  }

  // ── Widgets utilitaires ───────────────────────
  pw.Widget _cell(String label, String value, pw.Font font, pw.Font bold,
      {PdfColor? labelColor, PdfColor? valueColor, double fontSize = 8}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(label, style: pw.TextStyle(font: font, fontSize: 6,
          color: labelColor ?? _grey, letterSpacing: 0.5)),
        pw.SizedBox(height: 1),
        pw.Text(value.isEmpty ? '—' : value,
          style: pw.TextStyle(font: bold, fontSize: fontSize,
            color: valueColor ?? _dark)),
      ]));

  pw.Widget _hline({PdfColor? color, double width = 0.5}) =>
    pw.Container(height: width, color: color ?? _greyM,
      margin: const pw.EdgeInsets.symmetric(vertical: 4));

  pw.Widget _codeBadge(String code, pw.Font mono) =>
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: pw.BoxDecoration(
        color: _cyan.shade(0.08),
        borderRadius: pw.BorderRadius.circular(3),
        border: pw.Border.all(color: _cyan, width: 0.8)),
      child: pw.Text(code,
        style: pw.TextStyle(font: mono, fontSize: 7, color: _cyanD)));

  pw.Widget _sectionBar(String text, pw.Font bold) =>
    pw.Container(
      margin: const pw.EdgeInsets.only(top: 10, bottom: 4),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(left: pw.BorderSide(color: _cyan, width: 3))),
      child: pw.Text(text.toUpperCase(),
        style: pw.TextStyle(font: bold, fontSize: 7,
          color: _dark, letterSpacing: 1.5)));

  pw.Widget _statBox(String label, String value,
      PdfColor color, pw.Font font, pw.Font bold) =>
    pw.Expanded(child: pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 3),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: color.shade(0.05),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: color, width: 1.5)),
      child: pw.Column(children: [
        pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 18, color: color),
          textAlign: pw.TextAlign.center),
        pw.SizedBox(height: 2),
        pw.Text(label, style: pw.TextStyle(font: font, fontSize: 6, color: _grey),
          textAlign: pw.TextAlign.center),
      ])));

  // ── Cartouche en-tête (conforme TSM p.54) ────
  pw.Widget _buildCartouche({
    required String organisme,
    required String methode,
    required String dossier,
    required int pageNum,
    required int pageTotal,
    required pw.Font font,
    required pw.Font bold,
  }) =>
    pw.Table(
      border: pw.TableBorder.all(color: _dark, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.2),
        1: const pw.FlexColumnWidth(2.0),
        2: const pw.FlexColumnWidth(0.8),
      },
      children: [
        pw.TableRow(children: [
          pw.Padding(padding: const pw.EdgeInsets.all(4), child:
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(_t('controlOrganismColon'),
                style: pw.TextStyle(font: font, fontSize: 6, color: _grey)),
              pw.Text(organisme,
                style: pw.TextStyle(font: bold, fontSize: 8, color: _dark)),
            ])),
          pw.Padding(padding: const pw.EdgeInsets.all(4), child:
            pw.Column(children: [
              pw.Text(_t('inspectionMethodColon'),
                style: pw.TextStyle(font: font, fontSize: 6, color: _grey),
                textAlign: pw.TextAlign.center),
              pw.Text(methode,
                style: pw.TextStyle(font: bold, fontSize: 8, color: _dark),
                textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 4),
              pw.Text('Dossier : $dossier',
                style: pw.TextStyle(font: bold, fontSize: 7, color: _dark),
                textAlign: pw.TextAlign.center),
            ])),
          pw.Padding(padding: const pw.EdgeInsets.all(4), child:
            pw.Column(children: [
              pw.Text(_t('pageColon'),
                style: pw.TextStyle(font: font, fontSize: 6, color: _grey)),
              pw.Text('$pageNum / $pageTotal',
                style: pw.TextStyle(font: bold, fontSize: 8, color: _dark)),
            ])),
        ]),
      ]);

  // ── Page de garde (conforme TSM p.52) ─────────
  List<pw.Widget> _buildPageGarde({
    required Map<String, dynamic> ch,
    required String dossier,
    required int nbTroncons,
    required double longueurTotale,
    required String dateDebut,
    required String dateFin,
    required String operateur,
    required String dateEdition,
    required pw.Font font,
    required pw.Font bold,
  }) => [
    _buildCartouche(
      organisme: 'BZBots Systems',
      methode: _t('inspectionVideoTitle'),
      dossier: dossier,
      pageNum: 1, pageTotal: 1,
      font: font, bold: bold),
    pw.SizedBox(height: 40),
    pw.Center(child: pw.Column(children: [
      pw.Text('${_t('controlOffice')}  BZBots Systems',
        style: pw.TextStyle(font: bold, fontSize: 16, color: _dark)),
      pw.SizedBox(height: 8),
      pw.Text(_t('videoInspectionReport'),
        style: pw.TextStyle(font: font, fontSize: 12, color: _dark)),
      pw.SizedBox(height: 8),
      pw.Text('N° : $dossier',
        style: pw.TextStyle(font: bold, fontSize: 14, color: _dark)),
    ])),
    pw.SizedBox(height: 32),
    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: '${_t('clientColon')} ',
          style: pw.TextStyle(font: bold, fontSize: 10, color: _dark)),
        pw.TextSpan(text: ch['client'] as String? ?? '—',
          style: pw.TextStyle(font: font, fontSize: 10, color: _dark)),
      ])),
      pw.SizedBox(height: 4),
      pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: '${_t('responsibleAuthority')} : ',
          style: pw.TextStyle(font: bold, fontSize: 10, color: _dark)),
        pw.TextSpan(text: ch['client'] as String? ?? '—',
          style: pw.TextStyle(font: font, fontSize: 10, color: _dark)),
      ])),
      pw.SizedBox(height: 4),
      pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: '${_t('projectManager')} : ',
          style: pw.TextStyle(font: bold, fontSize: 10, color: _dark)),
        pw.TextSpan(text: ch['company'] as String? ?? '—',
          style: pw.TextStyle(font: font, fontSize: 10, color: _dark)),
      ])),
    ]),
    pw.SizedBox(height: 20),
    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: '${_t('municipality')} : ',
          style: pw.TextStyle(font: bold, fontSize: 10, color: _dark)),
        pw.TextSpan(text: ch['adresse'] as String? ?? '—',
          style: pw.TextStyle(font: font, fontSize: 10, color: _dark)),
      ])),
      pw.SizedBox(height: 4),
      pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: '${_t('inspectionObjectiveColon')} ',
          style: pw.TextStyle(font: bold, fontSize: 10, color: _dark)),
        pw.TextSpan(text: _t('finalControl'),
          style: pw.TextStyle(font: font, fontSize: 10, color: _dark)),
      ])),
    ]),
    pw.SizedBox(height: 20),
    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: '${_t('plannedInspectionLength')} ',
          style: pw.TextStyle(font: bold, fontSize: 10, color: _dark)),
        pw.TextSpan(text: '${longueurTotale.toStringAsFixed(0)} mètres',
          style: pw.TextStyle(font: font, fontSize: 10, color: _dark)),
      ])),
      pw.SizedBox(height: 4),
      pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: '${_t('inspectedSectionsCount')} ',
          style: pw.TextStyle(font: bold, fontSize: 10, color: _dark)),
        pw.TextSpan(text: '$nbTroncons',
          style: pw.TextStyle(font: font, fontSize: 10, color: _dark)),
      ])),
      pw.SizedBox(height: 4),
      pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: '${_t('inspectionStartDate')} ',
          style: pw.TextStyle(font: bold, fontSize: 10, color: _dark)),
        pw.TextSpan(text: dateDebut,
          style: pw.TextStyle(font: font, fontSize: 10, color: _dark)),
      ])),
      pw.SizedBox(height: 4),
      pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: '${_t('inspectionEndDate')} ',
          style: pw.TextStyle(font: bold, fontSize: 10, color: _dark)),
        pw.TextSpan(text: dateFin,
          style: pw.TextStyle(font: font, fontSize: 10, color: _dark)),
      ])),
      pw.SizedBox(height: 4),
      pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: '${_t('reportEditionDate')} ',
          style: pw.TextStyle(font: bold, fontSize: 10, color: _dark)),
        pw.TextSpan(text: dateEdition,
          style: pw.TextStyle(font: font, fontSize: 10, color: _dark)),
      ])),
    ]),
    pw.SizedBox(height: 24),
    pw.Row(children: [
      pw.Expanded(child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(_t('inspectionBy'),
          style: pw.TextStyle(font: bold, fontSize: 10, color: _dark)),
        pw.SizedBox(height: 4),
        pw.Text(operateur,
          style: pw.TextStyle(font: font, fontSize: 10, color: _dark)),
      ])),
      pw.Expanded(child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(_t('fileEstablishedBy'),
          style: pw.TextStyle(font: bold, fontSize: 10, color: _dark)),
        pw.SizedBox(height: 4),
        pw.Text('BZBots Systems',
          style: pw.TextStyle(font: font, fontSize: 10, color: _dark)),
      ])),
    ]),
    pw.SizedBox(height: 16),
    pw.Row(children: [
      pw.Expanded(child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(_t('codingStandardRef'),
          style: pw.TextStyle(font: bold, fontSize: 10, color: _dark)),
        pw.SizedBox(height: 4),
        pw.Text('NF EN 13508-2',
          style: pw.TextStyle(font: font, fontSize: 10, color: _cyan)),
      ])),
    ]),
    pw.SizedBox(height: 20),
    pw.Container(height: 0.5, color: _greyM),
    pw.SizedBox(height: 8),
    pw.Center(child: pw.Text(
      _t('reportContains'),
      style: pw.TextStyle(font: font, fontSize: 8, color: _grey),
      textAlign: pw.TextAlign.center)),
  ];

  // ── Cartouche rubrique tronçon (TSM p.54) ─────
  pw.Widget _buildCartoucheTroncon({
    required Map<String, dynamic> canal,
    required Map<String, dynamic> ch,
    required Map<String, dynamic> conditions,
    required models.Document doc,
    required String operateur,
    required String dateInspection,
    required String dossier,
    required pw.Font font,
    required pw.Font bold,
    required pw.Font mono,
  }) {
    final nom       = canal['nom']             as String? ?? '—';
    final dia       = canal['diametre']        as String? ?? '—';
    final lon       = canal['longueur']        as String? ?? '—';
    final mat       = canal['materiau']        as String? ?? '—';
    final forme     = canal['forme']           as String? ?? '—';
    final ecoul     = canal['sensEcoulement']  as String? ?? '—';
    final effluent  = canal['typeEffluent']    as String? ?? '—';
    final amont     = canal['noeudAmont']      as String? ?? '—';
    final aval      = canal['noeudAval']       as String? ?? '—';
    final profAmont = canal['profondeurAmont'] as String? ?? '—';
    final profAval  = canal['profondeurAval']  as String? ?? '—';

    final meteo      = conditions['meteo']           as String? ?? '—';
    final precip     = conditions['precipitations']  as String? ?? '—';
    final temp       = conditions['temperature']     as String? ?? '—';
    final nettoyage  = conditions['nettoyage']       as String? ?? '—';
    final nappe      = conditions['sousNappe']       as String? ?? '—';
    final empl       = conditions['emplacement']     as String? ?? '—';
    final remarque   = conditions['remarque']        as String? ?? '';
    // NF EN 13508-2
    final regDebit   = conditions['regulationDebit'] as String? ?? '—'; // ADC
    final refVideo   = conditions['refVideo']        as String? ?? '—'; // ABO
    final refPhotos  = conditions['refPhotos']       as String? ?? '—'; // ABN
    // Guide Astee
    final etatRemblai= conditions['etatRemblai']     as String? ?? '—';
    final etatVoirie = conditions['etatVoirie']      as String? ?? '—';
    // Non-normatif Astee
    final epose      = conditions['entreprisePose']  as String? ?? '—';
    // Objectifs inspection
    final objectif   = doc.data['objectifInspection'] as String? ?? '—';
    final attentes   = doc.data['attentes']            as String? ?? '—';
    final niveau     = doc.data['niveauDetail']        as String? ?? '1';

    pw.Widget row2(String l1, String v1, String l2, String v2) =>
      pw.Row(children: [
        pw.Expanded(child: _cell(l1, v1, font, bold)),
        pw.Container(width: 0.5, color: _greyM),
        pw.Expanded(child: _cell(l2, v2, font, bold)),
      ]);

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _dark, width: 0.5)),
      child: pw.Column(children: [

        // ── Header cartouche ──
        _buildCartouche(
          organisme: 'BZBots Systems',
          methode: _t('inspectionVideoTitle'),
          dossier: dossier,
          pageNum: 0, pageTotal: 0,
          font: font, bold: bold),

        // ── Inspecteur / Fonction ──
        pw.Container(
          color: _greyL,
          child: row2(
            'Inspecteur', operateur,
            'Fonction de l\'inspecteur', 'Opérateur vidéo')),
        pw.Container(height: 0.5, color: _greyM),

        // ── Identification inspection | Identification tronçon ──
        pw.Container(
          color: _dark,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Row(children: [
            pw.Expanded(child: pw.Text(_t('inspectionIdentification'),
              style: pw.TextStyle(font: bold, fontSize: 7, color: _white))),
            pw.Container(width: 0.5, color: _grey),
            pw.Expanded(child: pw.Text(_t('inspectedSectionIdentification'),
              style: pw.TextStyle(font: bold, fontSize: 7, color: _white))),
          ])),

        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
          pw.Expanded(child: pw.Column(children: [
            row2(_t('inspectionObject'), _t('finalControlCodeH'),
              _t('sectionReference'), '$amont - $aval'),
            pw.Container(height: 0.5, color: _greyM),
            row2('Commune', ch['adresse'] as String? ?? '—',
              _t('startNodeRef'), amont),
            pw.Container(height: 0.5, color: _greyM),
            row2('Adresse', ch['adresse'] as String? ?? '—',
              _t('depthAtStartNode'), profAmont.isNotEmpty && profAmont != '—' ? '$profAmont m' : '—'),
            pw.Container(height: 0.5, color: _greyM),
            row2('Autorité responsable', ch['client'] as String? ?? '—',
              _t('endNodeRef'), aval),
            pw.Container(height: 0.5, color: _greyM),
            row2('Client', ch['client'] as String? ?? '—',
              _t('depthAtEndNode'), profAval.isNotEmpty && profAval != '—' ? '$profAval m' : '—'),
            pw.Container(height: 0.5, color: _greyM),
            row2('Maître d\'œuvre', ch['company'] as String? ?? '—',
              _t('flowDirection'), ecoul),
            pw.Container(height: 0.5, color: _greyM),
            row2('Date de l\'inspection', dateInspection,
              _t('inspectionDirection'), _t('upstreamToDownstreamCodeB')),
            pw.Container(height: 0.5, color: _greyM),
            row2('Heure de l\'inspection', '—',
              _t('collectorType'), _t('gravityCodeA')),
            pw.Container(height: 0.5, color: _greyM),
            row2('Référence norme de codage', 'NF EN 13508-2',
              _t('collectorUsage'), effluent),
            pw.Container(height: 0.5, color: _greyM),
            row2(_t('videoMediaRef'), refVideo,
              _t('photoMediaRef'), refPhotos),
            pw.Container(height: 0.5, color: _greyM),
            row2(_t('installationCompany'), epose,
              _t('longitudinalRefPoint'), _t('startManholeCenter')),
          ])),
        ]),
        pw.Container(height: 0.5, color: _greyM),

        // ── Identification canalisation ──
        pw.Container(
          color: _dark,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text(_t('pipeIdentification'),
            style: pw.TextStyle(font: bold, fontSize: 7, color: _white))),

        row2(_t('pipeShape'), forme, _t('heightDiameter'), 'DN $dia mm'),
        pw.Container(height: 0.5, color: _greyM),
        row2(_t('constitutiveMaterial'), mat, _t('sectionLength'), '$lon m'),
        pw.Container(height: 0.5, color: _greyM),
        row2(_t('unitLength'), '—', _t('pdfUpstreamNode'), amont),
        pw.Container(height: 0.5, color: _greyM),
        row2(_t('commissioningYear'), '—', _t('pdfDownstreamNode'), aval),

        // ── Objectifs et attentes ──
        pw.Container(
          color: _dark,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text(_t('objectivesAndExpectations'),
            style: pw.TextStyle(font: bold, fontSize: 7, color: _white))),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
            pw.Expanded(child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
              pw.Text(_t('inspectionObjective'),
                style: pw.TextStyle(font: font, fontSize: 6,
                  color: _grey, letterSpacing: 0.5)),
              pw.SizedBox(height: 2),
              pw.Text(objectif,
                style: pw.TextStyle(font: bold, fontSize: 8, color: _dark)),
            ])),
            pw.SizedBox(width: 8),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6, vertical: 2),
              decoration: pw.BoxDecoration(
                color: _cyan.shade(0.08),
                borderRadius: pw.BorderRadius.circular(3),
                border: pw.Border.all(color: _cyan, width: 0.8)),
              child: pw.Text('${_t('levelPrefix')}$niveau',
                style: pw.TextStyle(font: bold, fontSize: 7,
                  color: _cyanD))),
          ])),
        pw.Container(height: 0.5, color: _greyM),
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
            pw.Text(_t('specificExpectations'),
              style: pw.TextStyle(font: font, fontSize: 6,
                color: _grey, letterSpacing: 0.5)),
            pw.SizedBox(height: 2),
            pw.Text(attentes,
              style: pw.TextStyle(font: font, fontSize: 8, color: _dark)),
          ])),

        // ── Conditions d\'intervention ──
        pw.Container(
          color: _dark,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text(_t('interventionConditions'),
            style: pw.TextStyle(font: bold, fontSize: 7, color: _white))),

        row2(_t('priorCleaning'), nettoyage,
          _t('meteorology'), meteo),
        pw.Container(height: 0.5, color: _greyM),
        row2(_t('precipitations'), precip,
          'Température extérieure', temp.isNotEmpty ? '$temp °C' : '—'),
        pw.Container(height: 0.5, color: _greyM),
        row2(_t('structureUnderGroundwater'), nappe,
          _t('location'), empl),
        pw.Container(height: 0.5, color: _greyM),
        row2(_t('flowRegulation'), regDebit,
          _t('backfillState'), etatRemblai),
        pw.Container(height: 0.5, color: _greyM),
        row2(_t('roadProgressState'), etatVoirie,
          '—', '—'),

        // ── Observations particulières ──
        if (remarque.isNotEmpty) ...[
          pw.Container(
            color: _dark,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: pw.Text(_t('particularObservations'),
              style: pw.TextStyle(font: bold, fontSize: 7, color: _white))),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(remarque,
              style: pw.TextStyle(font: font, fontSize: 8, color: _dark))),
        ],
      ]));
  }

  // ── Schéma tronçon linéaire (TSM p.58) ────────
  pw.Widget _buildSchemaLineaire({
    required String nomAmont,
    required String nomAval,
    required String profAmont,
    required String profAval,
    required double longueur,
    required List<Map<String, String>> annotations,
    required pw.Font font,
    required pw.Font bold,
    required pw.Font mono,
  }) {
    const double schemaH = 320.0;
    const double lineX   = 30.0;
    const double lineW   = 8.0;
    const double dotR    = 6.0;

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _greyM, width: 0.5)),
      child: pw.Column(children: [
        // Titre
        pw.Container(
          color: _dark,
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: pw.Text(
            'INSPECTION DU TRONÇON : $nomAmont - $nomAval',
            style: pw.TextStyle(font: bold, fontSize: 8,
              color: _white, letterSpacing: 1))),
        // Corps
        pw.Container(
          color: _white,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
            // Schéma SVG
            pw.SizedBox(
              width: 80,
              child: pw.CustomPaint(
                size: PdfPoint(80, schemaH),
                painter: (canvas, size) {
                  // Tube
                  canvas.setFillColor(_cyan.shade(0.3));
                  canvas.drawRect(lineX - lineW/2, 20, lineW, schemaH - 40);
                  canvas.fillPath();
                  canvas.setStrokeColor(_cyanD);
                  canvas.setLineWidth(0.5);
                  canvas.drawRect(lineX - lineW/2, 20, lineW, schemaH - 40);
                  canvas.strokePath();
                  // Regard amont (haut)
                  canvas.setFillColor(_dark);
                  canvas.drawEllipse(lineX, schemaH - 18, dotR, dotR);
                  canvas.fillPath();
                  // Regard aval (bas)
                  canvas.setFillColor(_dark);
                  canvas.drawEllipse(lineX, 18, dotR, dotR);
                  canvas.fillPath();
                  // Annotations
                  if (longueur > 0) {
                    for (int i = 0; i < annotations.length; i++) {
                      final dist = double.tryParse(
                        annotations[i]['dist']?.replaceAll('—','0') ?? '0') ?? 0;
                      final ratio = (dist / longueur).clamp(0.0, 1.0);
                      final y = (schemaH - 18) - ratio * (schemaH - 38);
                      // Ligne tiretée
                      canvas.setStrokeColor(_orange);
                      canvas.setLineWidth(0.4);
                      canvas.moveTo(lineX + lineW/2, y);
                      canvas.lineTo(lineX + 40, y);
                      canvas.strokePath();
                      // Point
                      canvas.setFillColor(_white);
                      canvas.drawEllipse(lineX, y, dotR * 0.7, dotR * 0.7);
                      canvas.fillPath();
                      canvas.setStrokeColor(_orange);
                      canvas.setLineWidth(0.8);
                      canvas.drawEllipse(lineX, y, dotR * 0.7, dotR * 0.7);
                      canvas.strokePath();
                    }
                  }
                },
              )),
            // Tableau observations
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                // En-tête tableau
                pw.Container(
                  color: _greyL,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 4),
                  child: pw.Row(children: [
                    pw.SizedBox(width: 28, child: pw.Text(_t('tableCode'),
                      style: pw.TextStyle(font: bold, fontSize: 6,
                        color: _grey, letterSpacing: 0.5))),
                    pw.SizedBox(width: 55, child: pw.Text(_t('tablePosition'),
                      style: pw.TextStyle(font: bold, fontSize: 6,
                        color: _grey, letterSpacing: 0.5))),
                    pw.Expanded(child: pw.Text(_t('tableObservations'),
                      style: pw.TextStyle(font: bold, fontSize: 6,
                        color: _grey, letterSpacing: 0.5))),
                  ])),
                // Nœud amont
                pw.Container(
                  color: _dark.shade(0.05),
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 3),
                  child: pw.Text(
                    '0,00 m — Nœud de départ : $nomAmont'
                    '${profAmont.isNotEmpty && profAmont != "—" ? " — Prof. $profAmont m" : ""}',
                    style: pw.TextStyle(font: bold, fontSize: 7, color: _dark))),
                // Annotations
                ...annotations.asMap().entries.map((e) {
                  final i    = e.key;
                  final ann  = e.value;
                  final dist = ann['dist'] ?? '—';
                  final obs  = ann['obs']  ?? '';
                  final time = ann['time'] ?? '';
                  final code = ann['code'] ?? '';
                  final distStr = dist == '—' ? '—' : '${dist} m';

                  return pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(
                        color: _greyM, width: 0.5))),
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6, vertical: 4),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                      pw.SizedBox(width: 28,
                        child: code.isNotEmpty
                          ? _codeBadge(code, mono)
                          : pw.SizedBox()),
                      pw.SizedBox(width: 55,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                          pw.Text(distStr,
                            style: pw.TextStyle(font: mono,
                              fontSize: 7, color: _dark)),
                          pw.Text('t=$time',
                            style: pw.TextStyle(font: mono,
                              fontSize: 6, color: _grey)),
                        ])),
                      pw.Expanded(
                        child: pw.Text(obs,
                          style: pw.TextStyle(font: bold,
                            fontSize: 8, color: _cyanD))),
                    ]));
                }),
                // Nœud aval
                pw.Container(
                  color: _dark.shade(0.05),
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 3),
                  child: pw.Text(
                    '${longueur > 0 ? "${longueur.toStringAsFixed(2)} m" : "—"} — Nœud d\'arrivée : $nomAval'
                    '${profAval.isNotEmpty && profAval != "—" ? " — Prof. $profAval m" : ""}',
                    style: pw.TextStyle(font: bold, fontSize: 7, color: _dark))),
              ])),
          ])),
      ]));
  }

  pw.Widget _thumbCapture(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return pw.SizedBox();
      final bytes = file.readAsBytesSync();
      return pw.Container(
        width: 36, height: 28,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _cyan, width: 0.5),
          borderRadius: pw.BorderRadius.circular(2)),
        child: pw.ClipRRect(
          horizontalRadius: 2, verticalRadius: 2,
          child: pw.Image(pw.MemoryImage(bytes),
            fit: pw.BoxFit.cover)));
    } catch (_) { return pw.SizedBox(); }
  }

  // Libellé court d'un code NF EN 13508-2
  String _nfLabel(String code) {
    const labels = {
      'DAF': 'Affaissement de voûte', 'DAJ': 'Déformation générale',
      'DAK': 'Ovalisation',          'DAM': 'Poinçonnement',
      'FAA': 'Fissure longitudinale', 'FAB': 'Fissure transversale',
      'FAC': 'Fissure en spirale',    'FAD': 'Fissures multiples',
      'FAE': 'Fissure long. ouverte', 'FAF': 'Fissure transv. ouverte',
      'BAB': 'Écrasement partiel',    'BAC': 'Effondrement',
      'BAD': 'Éclatement',            'BAE': 'Trou / Perforation',
      'CAA': 'Épaufrure légère',      'CAB': 'Épaufrure grave',
      'CAC': 'Armatures apparentes',  'CAD': 'Corrosion surface',
      'CAE': 'Revêtement cloqué',
      'JAA': 'Décalage latéral',      'JAB': 'Décalage vertical',
      'JAC': 'Déviation angulaire',   'JAD': 'Joint apparent',
      'JAE': 'Joint défectueux',
      'BAA': 'Branchement pénétrant', 'BAF': 'Raccordement défectueux',
      'BAG': 'Raccordement incorrect',
      'OAA': 'Dépôt de sédiments',    'OAB': 'Obstacle solide',
      'OAC': 'Racines',               'OAD': 'Graisse / encrassement',
      'IAA': 'Infiltration active',   'IAB': 'Marque infiltration',
      'IAC': 'Exfiltration',
      'PAA': 'Contre-pente / flache', 'PAB': 'Changement de pente',
      'PAC': 'Changement de section', 'PAD': 'Coude / changement dir.',
    };
    return labels[code] ?? code;
  }

  pw.Widget _fullCapture(String path, int num, String obs, String dist,
      String time, String code, String horaire, String troncon,
      String operateur, pw.Font font, pw.Font bold, pw.Font mono) {
    try {
      final file = File(path);
      if (!file.existsSync()) return pw.SizedBox();
      final bytes = file.readAsBytesSync();
      final img   = pw.MemoryImage(bytes);
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _greyM, width: 0.5)),
        child: pw.Row(children: [
          pw.Container(width: 150, height: 110,
            child: pw.Image(img, fit: pw.BoxFit.cover)),
          pw.Expanded(child: pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
              pw.Row(children: [
                pw.Text('${_t('photoRefPrefix')} $num',
                  style: pw.TextStyle(font: bold, fontSize: 8, color: _dark)),
                if (code.isNotEmpty) ...[
                  pw.SizedBox(width: 8),
                  _codeBadge(code, mono),
                ],
              ]),
              pw.SizedBox(height: 6),
              if (obs.isNotEmpty)
                pw.Text(obs,
                  style: pw.TextStyle(font: font, fontSize: 9, color: _dark)),
              pw.SizedBox(height: 6),
              pw.Text(
                'Distance : ${dist.isNotEmpty && dist != "—" ? "${dist}m" : "—"}'
                '${horaire.isNotEmpty ? "   •   Position : $horaire" : ""}'
                '   •   t=$time',
                style: pw.TextStyle(font: mono, fontSize: 7, color: _grey)),
              pw.SizedBox(height: 2),
              pw.Text('${_t('sectionShortPrefix')} $troncon   •   ${_t('operatorShortPrefix')} $operateur',
                style: pw.TextStyle(font: mono, fontSize: 7, color: _grey)),
            ]))),
        ]));
    } catch (_) { return pw.SizedBox(); }
  }

  // ── Récapitulatif (TSM p.57 bas) ──────────────
  pw.Widget _buildRecap({
    required String nomTroncon,
    required List<Map<String, String>> annotations,
    required pw.Font font,
    required pw.Font bold,
    required pw.Font mono,
  }) {
    // Groupe par catégorie
    final Map<String, List<String>> byCategory = {};
    for (final ann in annotations) {
      final cat = ann['category'] ?? 'Autre';
      final obs = ann['obs'] ?? '';
      final code = ann['code'] ?? '';
      if (obs.isNotEmpty) {
        byCategory.putIfAbsent(cat.isEmpty ? 'Général' : cat, () => []);
        byCategory[cat.isEmpty ? 'Général' : cat]!
          .add(code.isNotEmpty ? '[$code] $obs' : obs);
      }
    }

    if (byCategory.isEmpty) return pw.SizedBox();

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: _greyL,
        border: pw.Border.all(color: _greyM, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
        pw.Text(
          'Exemple de récapitulatif des observations triées par type — TRONÇON $nomTroncon',
          style: pw.TextStyle(font: bold, fontSize: 7,
            color: _dark, letterSpacing: 0.5)),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: byCategory.entries.take(6).map((cat) =>
            pw.Expanded(child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
              pw.Text('• ${cat.value.length} ${cat.key.toLowerCase()}',
                style: pw.TextStyle(font: bold, fontSize: 7, color: _cyanD)),
              ...cat.value.take(3).map((o) => pw.Padding(
                padding: const pw.EdgeInsets.only(left: 8, top: 1),
                child: pw.Text('- $o',
                  style: pw.TextStyle(font: font, fontSize: 6, color: _dark)))),
            ]))).toList()),
      ]));
  }

  // ── Footer/Header pages ───────────────────────
  pw.Widget _buildHeader(Map<String, dynamic> ch, String dossier,
      pw.Font font, pw.Font bold) =>
    pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _grey, width: 0.5))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
        pw.Text('BzVision — ${ch['nom'] ?? ''}',
          style: pw.TextStyle(font: bold, fontSize: 8, color: _dark)),
        pw.Text('${_t('filePrefix')} $dossier — NF EN 13508-2',
          style: pw.TextStyle(font: font, fontSize: 7, color: _grey)),
      ]));

  pw.Widget _buildFooter(pw.Context ctx, pw.Font font) =>
    pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _grey, width: 0.5))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
        pw.Text('BZBots Systems © ${DateTime.now().year} — ${_t('confidential')}',
          style: pw.TextStyle(font: font, fontSize: 7, color: _grey)),
        pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
          style: pw.TextStyle(font: font, fontSize: 7, color: _grey)),
      ]));

  // ══════════════════════════════════════════════
  // RAPPORT PRINCIPAL
  // ══════════════════════════════════════════════
  Future<Uint8List> generateChantierReport({
    required models.Document chantierDoc,
    required List<models.Document> canalisations,
    required List<List<models.Document>> inspectionsParCanalisation,
  }) async {
    final pdf  = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final mono = await PdfGoogleFonts.robotoMonoRegular();
    final ch   = chantierDoc.data;

    // Numéro de dossier
    final now    = DateTime.now();
    final dossier = '${ch['nom']?.toString().replaceAll(' ', '').substring(0, 3).toUpperCase() ?? 'BZV'}'
                    '-${now.year}-${now.month.toString().padLeft(2,'0')}';

    // Métriques globales
    final total      = canalisations.length;
    final inspected  = canalisations
      .where((c) => c.data['statut'] == 'inspecte').length;
    int totalCaptures = 0, totalAnomalies = 0;
    double longueurTotale = 0;
    String dateDebut = '—', dateFin = '—';

    for (int i = 0; i < canalisations.length; i++) {
      longueurTotale += double.tryParse(
        canalisations[i].data['longueur'] as String? ?? '0') ?? 0;
      for (final doc in inspectionsParCanalisation[i]) {
        final parsed = _parseObservations(
          doc.data['observations'] as String? ?? '');
        totalCaptures += (parsed['captures'] as List<Map<String,dynamic>>).length;
        totalAnomalies += (parsed['obsText'] as String)
          .split('\n').where((l) => l.trim().isNotEmpty).length;
        final d = doc.data['date'] as String? ?? '';
        if (d.isNotEmpty) { dateDebut = d; dateFin = d; }
      }
    }

    final operateur = inspectionsParCanalisation
      .expand((l) => l)
      .firstOrNull?.data['operateur'] as String? ?? '—';

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
      header: (ctx) => ctx.pageNumber == 1
        ? pw.SizedBox()
        : _buildHeader(ch, dossier, font, bold),
      footer: (ctx) => _buildFooter(ctx, font),
      build: (ctx) => [

        // ═══ PAGE DE GARDE ═══════════════════════
        ..._buildPageGarde(
          ch: ch, dossier: dossier,
          nbTroncons: total,
          longueurTotale: longueurTotale,
          dateDebut: dateDebut, dateFin: dateFin,
          operateur: operateur,
          dateEdition: _dateShort(),
          font: font, bold: bold),
        pw.SizedBox(height: 20),

        // ═══ STATS GLOBALES ═══════════════════════
        _sectionBar(_t('generalSynthesis'), bold),
        pw.SizedBox(height: 6),
        pw.Row(children: [
          _statBox(_t('sectionsUpper'), '$total', _cyan, font, bold),
          _statBox(_t('inspectedUpper'), '$inspected', _green, font, bold),
          _statBox(_t('anomaliesUpper'), '$totalAnomalies', _orange, font, bold),
          _statBox(_t('capturesUpper'), '$totalCaptures', _purple, font, bold),
        ]),
        pw.SizedBox(height: 12),

        // ═══ TABLEAU RÉCAP ════════════════════════
        _sectionBar(_t('sectionsRecap'), bold),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder(
            horizontalInside: const pw.BorderSide(color: _greyM, width: 0.5),
            bottom: const pw.BorderSide(color: _greyM, width: 0.5)),
          columnWidths: {
            0: const pw.FlexColumnWidth(0.4),
            1: const pw.FlexColumnWidth(1.6),
            2: const pw.FlexColumnWidth(0.6),
            3: const pw.FlexColumnWidth(0.6),
            4: const pw.FlexColumnWidth(0.7),
            5: const pw.FlexColumnWidth(0.6),
            6: const pw.FlexColumnWidth(0.5),
            7: const pw.FlexColumnWidth(0.5),
            8: const pw.FlexColumnWidth(0.5),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _greyL),
              children: ['#',_t('labelCol'),_t('lengthCol'),'DN',_t('materialCol'),
                _t('effluentCol'),_t('anomCol'),_t('capCol'),_t('statusCol')]
              .map((h) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 4, vertical: 5),
                child: pw.Text(h, style: pw.TextStyle(
                  font: bold, fontSize: 6,
                  color: _grey, letterSpacing: 0.8))))
              .toList()),
            ...canalisations.asMap().entries.map((e) {
              final d      = e.value.data;
              final ins    = inspectionsParCanalisation[e.key];
              final statut = d['statut'] as String? ?? '';
              int cc = 0, ac = 0;
              for (final doc in ins) {
                final p = _parseObservations(
                  doc.data['observations'] as String? ?? '');
                cc += (p['captures'] as List<Map<String,dynamic>>).length;
                ac += (p['obsText'] as String)
                  .split('\n').where((l) => l.trim().isNotEmpty).length;
              }
              final stColor = statut == 'inspecte' ? _green
                : statut == 'en_cours' ? _orange : _grey;
              final stLabel = statut == 'inspecte' ? '✓'
                : statut == 'en_cours' ? '●' : '—';
              return pw.TableRow(children: [
                _tcell('#${e.key+1}', font, _grey),
                _tcell(d['nom'] as String? ?? '—', bold, _dark),
                _tcell('${d['longueur']??'—'} m', font, _dark),
                _tcell('${d['diametre']??'—'}', font, _dark),
                _tcell(d['materiau'] as String? ?? '—', font, _dark),
                _tcell(d['typeEffluent'] as String? ?? '—', font, _cyan),
                _tcell('$ac', ac > 0 ? bold : font, ac > 0 ? _orange : _grey),
                _tcell('$cc', cc > 0 ? bold : font, cc > 0 ? _purple : _grey),
                _tcell(stLabel, bold, stColor),
              ]);
            }),
          ]),
        pw.SizedBox(height: 16),

        // ═══ DÉTAIL PAR TRONÇON ═══════════════════
        ...inspectionsParCanalisation.asMap().entries.expand((entry) {
          final idx  = entry.key;
          final ins  = entry.value;
          if (ins.isEmpty) return <pw.Widget>[];

          final canal = canalisations[idx].data;
          final nom   = canal['nom']        as String? ?? '—';
          final lon   = double.tryParse(canal['longueur'] as String? ?? '0') ?? 0;
          final amont = canal['noeudAmont'] as String? ?? 'NŒUD 1';
          final aval  = canal['noeudAval']  as String? ?? 'NŒUD 2';
          final profA = canal['profondeurAmont'] as String? ?? '—';
          final profV = canal['profondeurAval']  as String? ?? '—';

          final widgets = <pw.Widget>[];

          for (final doc in ins) {
            final parsed     = _parseObservations(
              doc.data['observations'] as String? ?? '');
            final obsText    = parsed['obsText']    as String;
            final captures   = parsed['captures']   as List<Map<String, dynamic>>;
            final conditions = parsed['conditions'] as Map<String, dynamic>;
            final operateurI = doc.data['operateur'] as String? ?? '—';
            final dateI      = doc.data['date']      as String? ?? '—';

            final lines = obsText.split('\n')
              .where((l) => l.trim().isNotEmpty).toList();

            final annotationsData = lines.asMap().entries.map((le) {
              final lp   = le.value.split('] ');
              final meta = lp.isNotEmpty ? lp[0].replaceAll('[','') : '';
              final text = lp.length > 1 ? lp[1] : le.value;
              String code = '', obsClean = text;
              final cm = RegExp(r'^\[([A-Z]{3})\]\s*').firstMatch(text);
              if (cm != null) { code = cm.group(1) ?? ''; obsClean = text.substring(cm.end); }
              String dist = '—', time = '—';
              final mp = meta.split(' | ');
              if (mp.length >= 2) { time = mp[0].trim(); dist = mp[1].replaceAll('m','').trim(); }
              return <String,String>{
                'obs': obsClean, 'dist': dist, 'time': time,
                'code': code,
                'category': '',
              };
            }).toList();

            // ── Cartouche rubrique ──
            widgets.add(_buildCartoucheTroncon(
              canal: canal, ch: ch,
              conditions: conditions,
              doc: doc,
              operateur: operateurI,
              dateInspection: dateI,
              dossier: dossier,
              font: font, bold: bold, mono: mono));
            widgets.add(pw.SizedBox(height: 8));

            // ── Schéma linéaire ──
            widgets.add(_buildSchemaLineaire(
              nomAmont: amont, nomAval: aval,
              profAmont: profA, profAval: profV,
              longueur: lon,
              annotations: annotationsData,
              font: font, bold: bold, mono: mono));
            widgets.add(pw.SizedBox(height: 8));

            // ── Captures groupées par code NF EN 13508-2 ──
            if (captures.isNotEmpty) {
              // Groupe par code (captures sans code → groupe 'Sans code')
              final Map<String, List<Map<String,dynamic>>> byCode = {};
              for (final cap in captures) {
                final code = (cap['code'] as String? ?? '').isNotEmpty
                  ? cap['code'] as String
                  : 'Sans code NF';
                byCode.putIfAbsent(code, () => []);
                byCode[code]!.add(cap);
              }

              widgets.add(_sectionBar(
                'Captures photographiques — $nom (${captures.length} photo(s))',
                bold));
              widgets.add(pw.SizedBox(height: 4));

              int photoNum = 1;
              for (final group in byCode.entries) {
                // En-tête groupe
                widgets.add(pw.Container(
                  margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFF0A0A0F),
                    borderRadius: pw.BorderRadius.circular(4),
                    border: pw.Border.all(
                      color: const PdfColor.fromInt(0xFF22D3EE),
                      width: 0.8)),
                  child: pw.Row(children: [
                    if (group.key != 'Sans code NF') ...[
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                        decoration: pw.BoxDecoration(
                          color: const PdfColor.fromInt(0xFF22D3EE).shade(0.1),
                          borderRadius: pw.BorderRadius.circular(3),
                          border: pw.Border.all(
                            color: const PdfColor.fromInt(0xFF22D3EE),
                            width: 0.8)),
                        child: pw.Text(group.key,
                          style: pw.TextStyle(font: mono, fontSize: 8,
                            color: const PdfColor.fromInt(0xFF0891B2)))),
                      pw.SizedBox(width: 8),
                    ],
                    pw.Text(
                      group.key == 'Sans code NF'
                        ? _t('withoutNfCode')
                        : _nfLabel(group.key),
                      style: pw.TextStyle(font: bold, fontSize: 8,
                        color: const PdfColor.fromInt(0xFF1F2937))),
                    pw.Spacer(),
                    pw.Text('${group.value.length} photo(s)',
                      style: pw.TextStyle(font: font, fontSize: 7,
                        color: const PdfColor.fromInt(0xFF6B7280))),
                  ])));

                // Captures du groupe
                for (final cap in group.value) {
                  widgets.add(_fullCapture(
                    cap['path']    as String? ?? '',
                    photoNum++,
                    cap['obs']     as String? ?? '',
                    cap['dist']    as String? ?? '—',
                    cap['time']    as String? ?? '—',
                    cap['code']    as String? ?? '',
                    cap['horaire'] as String? ?? '',
                    nom, operateurI,
                    font, bold, mono));
                }
              }
            }

            // ── Récapitulatif par type ──
            widgets.add(_buildRecap(
              nomTroncon: '$amont - $aval',
              annotations: annotationsData,
              font: font, bold: bold, mono: mono));
            widgets.add(pw.SizedBox(height: 20));
          }
          return widgets;
        }),

        // ═══ PIED DE RAPPORT ══════════════════════
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 16),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: _greyL,
            borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Center(child: pw.Column(children: [
            pw.Text(_t('autoGeneratedReport'),
              style: pw.TextStyle(font: bold, fontSize: 8, color: _grey)),
            pw.Text('BZBots Systems — ${_t('codingNfStandard')} — ${_t('filePrefix')} $dossier',
              style: pw.TextStyle(font: font, fontSize: 7,
                color: _grey, letterSpacing: 1)),
          ]))),
      ],
    ));

    return pdf.save();
  }

  pw.Widget _tcell(String text, pw.Font font, PdfColor color) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(text, style: pw.TextStyle(
        font: font, fontSize: 7, color: color)));

  Future<void> printReport(Uint8List pdfData) async {
    await Printing.layoutPdf(
      onLayout: (_) async => pdfData,
      name: 'Rapport_BzVision_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  Future<void> sharePdf(Uint8List pdfData, String filename) async {
    await Printing.sharePdf(bytes: pdfData, filename: '$filename.pdf');
  }
}
