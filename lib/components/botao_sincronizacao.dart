// Caminho: lib/components/botao_sincronizacao.dart
// Descrição: Botão animado para acionar a sincronização manual na AppBar.
// Correção: Chamada do método atualizado 'sincronizarTudo'.

import 'package:flutter/material.dart';
import '../services/sincronizacao_service.dart';

class BotaoSincronizacao extends StatefulWidget {
  final Color? color;

  const BotaoSincronizacao({super.key, this.color});

  @override
  State<BotaoSincronizacao> createState() => _BotaoSincronizacaoState();
}

class _BotaoSincronizacaoState extends State<BotaoSincronizacao>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final SincronizacaoService _service = SincronizacaoService();
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sincronizar() async {
    if (_isSyncing) return;

    setState(() {
      _isSyncing = true;
      _controller.repeat(); // Inicia a animação de rotação
    });

    try {
      // CORREÇÃO: Método renomeado para refletir a sincronização completa
      await _service.sincronizarTudo();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sincronização concluída!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao sincronizar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _controller.stop();
          _controller.reset(); // Para e reseta a animação
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _sincronizar,
      icon: RotationTransition(
        turns: Tween(begin: 0.0, end: 1.0).animate(_controller),
        child: Icon(Icons.sync, color: widget.color ?? Colors.white),
      ),
      tooltip: 'Sincronizar Dados',
    );
  }
}
