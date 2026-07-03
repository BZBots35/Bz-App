// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import 'cart_screen.dart';

class CartBadge extends StatefulWidget {
  const CartBadge({super.key});
  @override
  State<CartBadge> createState() => _CartBadgeState();
}

class _CartBadgeState extends State<CartBadge> {
  final _auth = AuthService();
  final _cart = CartService();
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final user = await _auth.getCurrentUser();
    if (user == null) return;
    final count = await _cart.getCartCount(user.$id);
    if (mounted) setState(() => _count = count);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(context,
          MaterialPageRoute(builder: (_) => const CartScreen()));
        _loadCount();
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Stack(children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.shopping_cart_outlined,
              color: Colors.white, size: 22)),
          if (_count > 0)
            Positioned(
              right: 2, top: 2,
              child: Container(
                width: 16, height: 16,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAB308),
                  shape: BoxShape.circle),
                child: Center(
                  child: Text('$_count',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.w900))))),
        ]),
      ),
    );
  }
}
