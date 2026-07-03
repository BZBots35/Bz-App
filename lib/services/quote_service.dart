// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:typed_data';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../services/cart_service.dart';
import '../services/lang_service.dart';

class QuoteService {
  static const String _endpoint   = 'https://cloud.appwrite.io/v1';
  static const String _projectId  = '69ccd61d0017c7eaedee';
  static const String _functionId = '6a216473000c2a72df63';
  static const String _quoteEmail = 'tb@bz-bots.com';
  static const List<String> _ccFixed = ['mm@bz-botz.com'];

  final LangService _lang;
  QuoteService(this._lang);

  Future<void> generateAndSend({
    required List<CartItem> items,
    required String userName,
    required String company,
    required String dateStr,
    required String userEmail,
    required String distributeurEmail,
  }) async {
    final pdfBytes = await _generatePdf(items: items, userName: userName, company: company, dateStr: dateStr);
    final txtContent = _generateTxt(items: items, userName: userName, company: company, dateStr: dateStr);
    final safeDate = dateStr.replaceAll('/', '-');

    // CC : utilisateur + distributeur (si renseigné) + adresses fixes
    final ccList = <String>[userEmail, ..._ccFixed];
    if (distributeurEmail.isNotEmpty) ccList.add(distributeurEmail);

    final client = Client()..setEndpoint(_endpoint)..setProject(_projectId);

    final htmlBody = '''
<div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; background: #ffffff;">
  <div style="background: #0A0A0F; padding: 24px; text-align: center;">
    <h1 style="color: #EAB308; margin: 0; font-size: 22px; letter-spacing: 2px;">BZBOTS</h1>
  </div>
  <div style="padding: 32px 24px;">
    <p style="color: #1F2937; font-size: 15px;">${_lang.t('emailHello')}</p>
    <p style="color: #1F2937; font-size: 15px;">
      ${_lang.t('emailBody1')} <strong>$userName</strong> 
      ${_lang.t('emailBody2')} <strong>$company</strong>${_lang.t('emailBody3')}
    </p>
    <p style="color: #1F2937; font-size: 15px;">${_lang.t('emailBody4')}</p>
    <p style="color: #1F2937; font-size: 15px;">${_lang.t('emailRegards')}<br><strong>${_lang.t('emailTeam')}</strong></p>
  </div>
  <div style="background: #F9FAFB; padding: 16px 24px; text-align: center; border-top: 1px solid #E5E7EB;">
    <a href="https://www.bzbots.com" style="color: #EAB308; font-size: 12px; text-decoration: none;">www.bzbots.com</a>
  </div>
</div>''';

    await Functions(client).createExecution(
      functionId: _functionId,
      body: jsonEncode({
        'to':       _quoteEmail,
        'cc':       ccList.join(','),
        'subject':  '[BzBots] ${_lang.t('cartQuoteEmailHeader')} — $company — $dateStr',
        'text':     txtContent,
        'html':     htmlBody,
        'userName': userName,
        'company':  company,
        'attachments': [
          {'filename': 'Devis_BzBots_$safeDate.pdf', 'content': base64Encode(pdfBytes)},
          {'filename': 'Devis_BzBots_$safeDate.txt', 'content': base64Encode(utf8.encode(txtContent))},
        ],
      }),
    );
  }

  Future<Uint8List> _generatePdf({
    required List<CartItem> items,
    required String userName,
    required String company,
    required String dateStr,
  }) async {
    final pdf = pw.Document();

    // Charger logo
    pw.ImageProvider? logoImage;
    try {
      final d = await rootBundle.load('assets/logo.png');
      logoImage = pw.MemoryImage(d.buffer.asUint8List());
    } catch (_) {}

    // Précharger les images des articles
    final Map<String, pw.ImageProvider> itemImages = {};
    for (final item in items) {
      if (item.img.isNotEmpty && !itemImages.containsKey(item.img)) {
        try {
          final d = await rootBundle.load(item.img);
          itemImages[item.img] = pw.MemoryImage(d.buffer.asUint8List());
        } catch (_) {}
      }
    }

    // Charger police de base NotoSans
    final fontRegular = pw.Font.ttf(
      (await rootBundle.load('assets/NotoSans-Regular.ttf')).buffer.asByteData());
    final fontItalic = pw.Font.ttf(
      (await rootBundle.load('assets/NotoSans-Italic.ttf')).buffer.asByteData());

    // Charger police de secours selon la langue
    pw.Font? fallbackFont;
    final lang = _lang.currentLang;
    if (lang == 'ko') {
      fallbackFont = pw.Font.ttf(
        (await rootBundle.load('assets/NotoSansKR-Regular.ttf')).buffer.asByteData());
    } else if (lang == 'ja') {
      fallbackFont = pw.Font.ttf(
        (await rootBundle.load('assets/NotoSansJP-Regular.ttf')).buffer.asByteData());
    } else if (lang == 'zh') {
      fallbackFont = pw.Font.ttf(
        (await rootBundle.load('assets/NotoSansSC-Regular.ttf')).buffer.asByteData());
    } else if (lang == 'ar') {
      fallbackFont = pw.Font.ttf(
        (await rootBundle.load('assets/Rubik-Regular.ttf')).buffer.asByteData());
    } else if (lang == 'hi') {
      fallbackFont = pw.Font.ttf(
        (await rootBundle.load('assets/GoogleSans-Regular.ttf')).buffer.asByteData());
    }

    final fallbackList = fallbackFont != null ? [fallbackFont] : <pw.Font>[];

    final theme = pw.ThemeData.withFont(
      base: fontRegular,
      italic: fontItalic,
      fontFallback: fallbackList,
    );

    final baseStyle   = pw.TextStyle(font: fontRegular, fontFallback: fallbackList);
    final boldStyle   = pw.TextStyle(font: fontRegular, fontWeight: pw.FontWeight.bold, fontFallback: fallbackList);
    final italicStyle = pw.TextStyle(font: fontItalic, fontFallback: fallbackList);

    const yellow  = PdfColor.fromInt(0xFFEAB308);
    const greyTxt = PdfColor.fromInt(0xFF9CA3AF);

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logoImage != null) pw.Image(logoImage, width: 80, height: 80)
            else pw.Text('BzBots', style: boldStyle.copyWith(fontSize: 24, color: yellow)),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text(_lang.t('cartQuoteEmailHeader'), style: boldStyle.copyWith(fontSize: 16)),
              pw.SizedBox(height: 4),
              pw.Text('${_lang.t('cartQuoteDate')} : $dateStr', style: baseStyle.copyWith(fontSize: 10, color: greyTxt)),
            ]),
          ]),
        pw.SizedBox(height: 20),
        pw.Divider(color: yellow, thickness: 2),
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF9FAFB), borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(children: [
              pw.Text('${_lang.t('cartQuoteClient')} : ', style: boldStyle.copyWith(fontSize: 11)),
              pw.Text(userName, style: baseStyle.copyWith(fontSize: 11)),
            ]),
            pw.SizedBox(height: 4),
            pw.Row(children: [
              pw.Text('${_lang.t('cartQuoteCompany')} : ', style: boldStyle.copyWith(fontSize: 11)),
              pw.Text(company, style: baseStyle.copyWith(fontSize: 11)),
            ]),
          ])),
        pw.SizedBox(height: 20),
        pw.Text(_lang.t('cartQuoteItems'), style: boldStyle.copyWith(fontSize: 13)),
        pw.SizedBox(height: 10),

        // Grouper les articles par robot
        ...() {
          final widgets = <pw.Widget>[];
          final robots = items.map((e) => e.robotSerial).toSet().toList();

          for (final serial in robots) {
            final robotItems = items.where((e) => e.robotSerial == serial).toList();

            // En-tête de section robot
            widgets.add(pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 6),
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF1F2937),
                borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Row(children: [
                pw.Text('Robot : ', style: boldStyle.copyWith(fontSize: 10, color: PdfColors.white)),
                pw.Text(serial.isNotEmpty ? serial : '-',
                  style: pw.TextStyle(fontSize: 10, color: yellow,
                    fontWeight: pw.FontWeight.bold, fontFallback: fallbackList)),
              ]),
            ));

            // Tableau des pièces du robot
            widgets.add(pw.Table(
              border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFE5E7EB), width: 0.5),
              columnWidths: {
                0: const pw.FixedColumnWidth(40),  // Image
                1: const pw.FlexColumnWidth(2.0),  // Référence
                2: const pw.FlexColumnWidth(1.2),  // Version
                3: const pw.FlexColumnWidth(2.5),  // Description
                4: const pw.FixedColumnWidth(30),  // Qté
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: yellow),
                  children: [
                    _cell('', isHeader: true),
                    _cell('Réf.', isHeader: true),
                    _cell(_lang.t('version'), isHeader: true),
                    _cell(_lang.t('cartQuoteDesc'), isHeader: true),
                    _cell('Qté', isHeader: true, center: true),
                  ]),
                ...robotItems.asMap().entries.map((e) => pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: e.key.isEven ? PdfColors.white : PdfColor.fromInt(0xFFF9FAFB)),
                  children: [
                    _imgCell(e.value.img, itemImages),
                    _cell(e.value.name),
                    _cell(e.value.version.isNotEmpty ? e.value.version : '-'),
                    _cell(() { final d = _lang.t('bzl_desc_${e.value.name}'); return d.startsWith('bzl_desc_') ? '-' : d; }()),
                    _cell('${e.value.qty}', center: true),
                  ])),
              ]));

            widgets.add(pw.SizedBox(height: 12));
          }
          return widgets;
        }(),
        pw.SizedBox(height: 20),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: pw.BoxDecoration(color: yellow, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Text(
              '${_lang.t('cartTotal')} : ${items.fold(0, (s, e) => s + e.qty)} ${_lang.t('cartArticles')}',
              style: boldStyle.copyWith(fontSize: 12, color: PdfColors.black))),
        ]),
        pw.SizedBox(height: 20),
        pw.Divider(color: PdfColor.fromInt(0xFFE5E7EB)),
        pw.SizedBox(height: 8),
        pw.Text(_lang.t('cartQuoteFooter'), style: italicStyle.copyWith(fontSize: 9, color: greyTxt)),
        pw.SizedBox(height: 4),
        pw.Text('www.bzbots.com', style: baseStyle.copyWith(fontSize: 9, color: yellow)),
      ],
    ));
    return pdf.save();
  }

  String _generateTxt({
    required List<CartItem> items,
    required String userName,
    required String company,
    required String dateStr,
  }) {
    final sb = StringBuffer();
    sb.writeln('================================');
    sb.writeln('  BZBOTS — ${_lang.t('cartQuoteEmailHeader').toUpperCase()}');
    sb.writeln('================================');
    sb.writeln();
    sb.writeln('${_lang.t('cartQuoteDate')} : $dateStr');
    sb.writeln('${_lang.t('cartQuoteClient')} : $userName');
    sb.writeln('${_lang.t('cartQuoteCompany')} : $company');
    sb.writeln();
    sb.writeln('--------------------------------');
    sb.writeln(_lang.t('cartQuoteItems').toUpperCase());
    sb.writeln('--------------------------------');
    for (final item in items) {
      sb.writeln();
      sb.writeln('• ${item.name}');
      if (item.version.isNotEmpty) sb.writeln('  ${_lang.t('version')} : ${item.version}');
      final desc = _lang.t('bzl_desc_${item.name}');
      if (!desc.startsWith('bzl_desc_')) sb.writeln('  ${_lang.t('cartQuoteDesc')} : $desc');
      sb.writeln('  Robot : ${item.robotSerial}');
      sb.writeln('  Qté   : ${item.qty}');
    }
    sb.writeln();
    sb.writeln('--------------------------------');
    sb.writeln('${_lang.t('cartTotal')} : ${items.fold(0, (s, e) => s + e.qty)} ${_lang.t('cartArticles')}');
    sb.writeln('--------------------------------');
    sb.writeln();
    sb.writeln(_lang.t('cartQuoteFooter'));
    sb.writeln();
    sb.writeln('www.bzbots.com');
    return sb.toString();
  }

  pw.Widget _imgCell(String imgPath, Map<String, pw.ImageProvider> images) {
    final img = images[imgPath];
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: img != null
        ? pw.Image(img, width: 32, height: 32, fit: pw.BoxFit.contain)
        : pw.SizedBox(width: 32, height: 32));
  }

  pw.Widget _cell(String text, {bool isHeader = false, bool center = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(text,
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader ? PdfColors.black : PdfColor.fromInt(0xFF1F2937))));
  }
}
