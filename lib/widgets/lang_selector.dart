// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../services/lang_service.dart';

class LangSelector extends StatefulWidget {
  const LangSelector({super.key});

  @override
  State<LangSelector> createState() => _LangSelectorState();
}

class _LangSelectorState extends State<LangSelector> {
  final _lang = LangService();

  @override
  void initState() {
    super.initState();
    _lang.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  void _showLangPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text('LANGUE / LANGUAGE',
                style: TextStyle(color: Colors.grey[400], fontSize: 11,
                  fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, childAspectRatio: 2.5,
                  crossAxisSpacing: 8, mainAxisSpacing: 8),
                itemCount: LangService.languages.length,
                itemBuilder: (_, i) {
                  final code     = LangService.languages.keys.elementAt(i);
                  final label    = LangService.languages[code]!;
                  final selected = code == _lang.currentLang;
                  return GestureDetector(
                    onTap: () {
                      _lang.setLang(code);
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected
                          ? const Color(0xFF22D3EE).withOpacity(0.15)
                          : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                            ? const Color(0xFF22D3EE).withOpacity(0.5)
                            : Colors.white.withOpacity(0.08)),
                      ),
                      child: Center(
                        child: Text(label,
                          style: TextStyle(
                            color: selected ? const Color(0xFF22D3EE) : Colors.white,
                            fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
