import 'package:material_ui/material_ui.dart';

import '../widgets/md.dart';

/// Visualizador em tela cheia de uma figura/foto do material: pinça para zoom,
/// toque duplo para ampliar, toque simples para mostrar/esconder a legenda.
class FigureViewer extends StatefulWidget {
  final String asset;
  final String? titulo;
  final String? legenda;
  final String? credito;

  /// Ilustrações são desenhadas sobre fundo branco (inclusive no tema escuro).
  final bool fundoBranco;
  const FigureViewer({
    super.key,
    required this.asset,
    this.titulo,
    this.legenda,
    this.credito,
    this.fundoBranco = false,
  });

  @override
  State<FigureViewer> createState() => _FigureViewerState();
}

class _FigureViewerState extends State<FigureViewer> with SingleTickerProviderStateMixin {
  final _ctl = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Matrix4>? _zoom;
  Offset _toque = Offset.zero;
  bool _legenda = true;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      if (_zoom != null) _ctl.value = _zoom!.value;
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _ctl.dispose();
    super.dispose();
  }

  void _duploToque() {
    final ampliado = _ctl.value.getMaxScaleOnAxis() > 1.05;
    final Matrix4 fim;
    if (ampliado) {
      fim = Matrix4.identity();
    } else {
      const s = 2.6;
      fim = Matrix4.identity()
        ..translateByDouble(-_toque.dx * (s - 1), -_toque.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
    _zoom = Matrix4Tween(begin: _ctl.value, end: fim).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final temTexto = (widget.legenda ?? '').isNotEmpty || (widget.titulo ?? '').isNotEmpty;
    final img = Image.asset(
      widget.asset,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Imagem indisponível.', style: TextStyle(color: Colors.white70)),
      ),
    );
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: const Color(0x66000000),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.titulo ?? (widget.fundoBranco ? 'Figura' : 'Foto'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Tamanho original',
            icon: const Icon(Icons.fit_screen_outlined),
            onPressed: () => _ctl.value = Matrix4.identity(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: temTexto ? () => setState(() => _legenda = !_legenda) : null,
              onDoubleTapDown: (d) => _toque = d.localPosition,
              onDoubleTap: _duploToque,
              child: InteractiveViewer(
                transformationController: _ctl,
                minScale: 1,
                maxScale: 6,
                child: SafeArea(
                  child: Center(
                    child: widget.fundoBranco
                        ? Container(color: Colors.white, padding: const EdgeInsets.all(12), child: img)
                        : img,
                  ),
                ),
              ),
            ),
          ),
          if (temTexto)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_legenda,
                child: AnimatedOpacity(
                  opacity: _legenda ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xD9000000)],
                      ),
                    ),
                    padding: EdgeInsets.fromLTRB(18, 36, 18, 18 + MediaQuery.paddingOf(context).bottom),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .35),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((widget.legenda ?? '').isNotEmpty)
                              MdText(
                                widget.legenda!,
                                style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.45),
                              ),
                            if ((widget.credito ?? '').isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Imagem: ${widget.credito}',
                                style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                              ),
                            ],
                            const SizedBox(height: 6),
                            const Text(
                              'Pinça ou toque duplo para ampliar',
                              style: TextStyle(color: Colors.white54, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
