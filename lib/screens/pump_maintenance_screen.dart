// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/lang_service.dart';

/// Écran Maintenance du module Pompe.
class PumpMaintenanceScreen extends StatefulWidget {
  const PumpMaintenanceScreen({super.key});

  @override
  State<PumpMaintenanceScreen> createState() => _PumpMaintenanceScreenState();
}

class _PumpMaintenanceScreenState extends State<PumpMaintenanceScreen> {
  final _lang = LangService();

  // Même IP/port que pump_operation_screen.dart : les pompes ont une IP
  // fixe sur leur propre hotspot (10.42.0.1), port 5000 pour l'API de
  // commande (à ne pas confondre avec le port 5002 de la caméra BzVision).
  static const String _piBase = 'http://10.42.0.1:5000';

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
  }

  Future<void> _confirmAndLaunchMaintenanceCycle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D0D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_lang.t('pumpMaintenanceConfirmTitle'),
          style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 14)),
        content: Text(_lang.t('pumpMaintenanceConfirmMsg'),
          style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_lang.t('pumpOpCancelBtn'),
              style: const TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange, foregroundColor: Colors.black),
            child: Text(_lang.t('pumpMaintenanceLaunchBtn'),
              style: const TextStyle(fontWeight: FontWeight.w900))),
        ],
      ),
    );
    if (confirmed == true) _launchMaintenanceCycle();
  }

  Future<void> _stopPump() async {
    try {
      final response = await http.post(
        Uri.parse('$_piBase/command'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({"cmd": "STOP"}),
      ).timeout(const Duration(seconds: 5));

      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('⏹ ${_lang.t('pumpMaintenanceStoppedMsg')}'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '${_lang.t('pumpMaintenanceErrorMsg')} (${response.statusCode})'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${_lang.t('pumpMaintenanceErrorMsg')} : $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _launchMaintenanceCycle() async {
    setState(() => _sending = true);
    try {
      final response = await http.post(
        Uri.parse('$_piBase/command'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({"cmd": "MAINTENANCE"}),
      ).timeout(const Duration(seconds: 5));

      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✓ ${_lang.t('pumpMaintenanceSentMsg')}'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '${_lang.t('pumpMaintenanceErrorMsg')} (${response.statusCode})'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${_lang.t('pumpMaintenanceErrorMsg')} : $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3))),
            child: const Icon(Icons.build_outlined,
              color: Colors.orange, size: 14)),
          const SizedBox(width: 8),
          Text(_lang.t('pumpMaintenanceScreenTitle'),
            style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 14,
              letterSpacing: 1.5)),
        ]),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.build_outlined, color: Colors.grey[700], size: 48),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _confirmAndLaunchMaintenanceCycle,
                icon: _sending
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.cleaning_services_outlined),
                label: Text(_lang.t('pumpMaintenanceLaunchBtn'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _stopPump,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(_lang.t('pumpMaintenanceStopBtn'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
