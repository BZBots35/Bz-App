// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/lang_service.dart';
import '../services/quote_service.dart';
import '../widgets/lang_selector.dart';
import 'bz_tutorial.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});
  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  static const String _quoteEmail = 'commandes@bzbots.com'; // ← à changer

  final _auth        = AuthService();
  final _cart        = CartService();
  final _lang        = LangService();
  final _tutorialKey = GlobalKey<BzTutorialState>();

  List<TutorialStep> get _tutorialSteps => [
    TutorialStep(title: 'Envoyer le devis', description: 'Ce bouton envoie une demande de devis à votre distributeur. Il pourra commander les pièces dont vous avez besoin et vous recontacter.', targetOffset: const Offset(0.5, 0.90), targetSize: 50),
  ];

  List<CartItem> _items = [];
  bool   _loading           = true;
  String _userId            = '';
  String _userName          = '';
  String _company           = '';
  String _userEmail         = '';
  String _distributeurEmail = '';

  @override
  void initState() {
    super.initState();
    _lang.addListener(() { if (mounted) setState(() {}); });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final user = await _auth.getCurrentUser();
    if (user != null) {
      final company          = await _auth.getUserCompany(user.$id);
      final distributeurEmail = await _auth.getDistributeurEmail(user.$id);
      final items            = await _cart.getCart(user.$id);
      if (mounted) setState(() {
        _userId            = user.$id;
        _userName          = user.name;
        _userEmail         = user.email;
        _company           = company;
        _distributeurEmail = distributeurEmail;
        _items             = items;
        _loading           = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _updateQty(CartItem item, int delta) async {
    final newQty = item.qty + delta;
    await _cart.updateQty(_userId, item.id, item.robotSerial, newQty);
    _load();
  }

  Future<void> _remove(CartItem item) async {
    await _cart.removeItem(_userId, item.id, item.robotSerial);
    _load();
  }

  Future<void> _sendQuote() async {
    if (_items.isEmpty) return;

    final now     = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2,'0')}/'
                    '${now.month.toString().padLeft(2,'0')}/'
                    '${now.year}';

    // Afficher indicateur de chargement
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)),
          const SizedBox(width: 12),
          Text(_lang.t('cartSendingQuote')),
        ]),
        backgroundColor: const Color(0xFFEAB308),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 10),
      ));
    }

    try {
      await QuoteService(_lang).generateAndSend(
        items:             _items,
        userName:          _userName,
        company:           _company,
        dateStr:           dateStr,
        userEmail:         _userEmail,
        distributeurEmail: _distributeurEmail,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_lang.t('cartQuoteSent')),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: Colors.red[900],
          behavior: SnackBarBehavior.floating));
      }
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
        title: Text(_lang.t('cartTitle'),
          style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 14)),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline, color: Colors.white54, size: 20), onPressed: () => _tutorialKey.currentState?.show()),
          if (_items.isNotEmpty)
            TextButton(
              onPressed: () async {
                await _cart.clearCart(_userId);
                _load();
              },
              child: Text(_lang.t('cartClear'),
                style: TextStyle(color: Colors.grey[500], fontSize: 12))),
          const LangSelector(), const SizedBox(width: 8),
        ],
      ),
      body: BzTutorial(key: _tutorialKey, tutorialKey: 'bzlight_cart', steps: _tutorialSteps, child: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFEAB308)))
        : _items.isEmpty
          ? _buildEmpty()
          : Column(children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  itemBuilder: (_, i) => _buildItem(_items[i]),
                ),
              ),
              _buildSummary(),
            ]),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.shopping_cart_outlined, color: Colors.grey[700], size: 56),
      const SizedBox(height: 16),
      Text(_lang.t('cartEmpty'),
        style: const TextStyle(color: Colors.white,
          fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 8),
      Text(_lang.t('cartEmptyHint'),
        style: TextStyle(color: Colors.grey[600], fontSize: 12)),
    ]));
  }

  Widget _buildItem(CartItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.2))),
      child: Row(children: [
        // Image ou icône fallback
        GestureDetector(
          onTap: item.img.isNotEmpty ? () => showDialog(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: Colors.black,
              insetPadding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(
                  minScale: 0.5, maxScale: 6.0,
                  child: Image.asset(item.img, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.memory, color: Color(0xFFEAB308), size: 60)))))) : null,
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEAB308).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEAB308).withOpacity(0.2))),
            child: item.img.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(item.img,
                    width: 44, height: 44, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.memory, color: Color(0xFFEAB308), size: 20)))
              : const Icon(Icons.memory, color: Color(0xFFEAB308), size: 20))),
        const SizedBox(width: 12),
        // Infos
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.name, style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 13, fontFamily: 'monospace')),
          const SizedBox(height: 2),
          Text('${_lang.t('version')} ${item.version}',
            style: TextStyle(color: Colors.grey[500], fontSize: 11)),
          const SizedBox(height: 2),
          Row(children: [
            Icon(Icons.flash_on, color: Colors.grey[600], size: 11),
            const SizedBox(width: 3),
            Text(item.robotSerial,
              style: TextStyle(color: Colors.grey[600],
                fontSize: 10, fontFamily: 'monospace')),
          ]),
        ])),
        // Quantité
        Row(children: [
          _qtyBtn(Icons.remove, () => _updateQty(item, -1)),
          Container(
            width: 32,
            alignment: Alignment.center,
            child: Text('${item.qty}', style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14))),
          _qtyBtn(Icons.add, () => _updateQty(item, 1)),
        ]),
        const SizedBox(width: 8),
        // Supprimer
        GestureDetector(
          onTap: () => _remove(item),
          child: Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.delete_outline, color: Colors.red[400], size: 15))),
      ]),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(7)),
        child: Icon(icon, color: Colors.white, size: 14)),
    );
  }

  Widget _buildSummary() {
    final total = _items.fold(0, (sum, e) => sum + e.qty);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08)))),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_lang.t('cartTotal'),
            style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          Text('$total ${_lang.t('cartArticles')}',
            style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 15)),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton.icon(
            onPressed: _sendQuote,
            icon: const Icon(Icons.send_outlined, size: 18),
            label: Text(_lang.t('cartSendQuote'),
              style: const TextStyle(fontWeight: FontWeight.w900,
                fontSize: 13, letterSpacing: 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEAB308),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
              elevation: 0),
          ),
        ),
        const SizedBox(height: 8),
        Text(_lang.t('cartQuoteNote'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[700], fontSize: 10)),
      ]),
    );
  }
}
