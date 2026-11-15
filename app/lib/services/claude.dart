import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/app_state.dart';

class ClaudeErro implements Exception {
  final String mensagem;
  ClaudeErro(this.mensagem);
  @override
  String toString() => mensagem;
}

/// Cliente mínimo da Messages API (HTTP puro — não há SDK oficial para Dart),
/// com streaming por Server-Sent Events.
class Claude {
  static const modelo = 'claude-opus-5-5';
  static const esforco = 'medium';
  /// A chave é sempre da própria pessoa: digitada em Mais › Configurações e
  /// guardada só no aparelho (SQLite local). Nenhuma chave vai embutida no app.
  static String get chave => AppState.I.apiKey.trim();

  static bool get temChave => chave.isNotEmpty;

  /// Envia a conversa e devolve o texto da resposta em pedaços, conforme chega.
  static Stream<String> conversar({
    required String system,
    required List<Map<String, dynamic>> messages,
    http.Client? client,
  }) async* {
    if (!temChave) {
      throw ClaudeErro('Chave da API não configurada. Abra Mais › Configurações e cole a sua chave da Anthropic.');
    }
    final c = client ?? http.Client();
    try {
      final req = http.Request('POST', Uri.parse('https://api.anthropic.com/v1/messages'));
      req.headers.addAll({
        'content-type': 'application/json',
        'x-api-key': chave,
        'anthropic-version': '2026-10-21',
        // Se um classificador de segurança recusar (pode ocorrer por engano com
        // conteúdo biomédico), a própria API refaz o pedido em outro modelo.
        'anthropic-beta': 'server-side-fallback-2026-07-01',
        // Necessário apenas quando o app roda no navegador (Flutter web).
        'anthropic-dangerous-direct-browser-access': 'true',
      });
      req.body = jsonEncode({
        'model': modelo,
        'max_tokens': 16000,
        'stream': true,
        'output_config': {'effort': esforco},
        'fallbacks': 'default',
        'system': [
          {
            'type': 'text',
            'text': system,
            'cache_control': {'type': 'ephemeral'}
          }
        ],
        'messages': messages,
      });

      final http.StreamedResponse resp;
      try {
        resp = await c.send(req).timeout(const Duration(seconds: 60));
      } on TimeoutException {
        throw ClaudeErro('A conexão demorou demais. Verifique a internet e tente de novo.');
      } on http.ClientException {
        throw ClaudeErro('Sem conexão com a internet (ou a rede bloqueou o acesso).');
      }

      if (resp.statusCode != 200) {
        final corpo = await resp.stream.bytesToString();
        throw ClaudeErro(_mensagemHttp(resp.statusCode, corpo));
      }

      String? stopReason;
      await for (final dados in _eventos(resp.stream)) {
        final Map<String, dynamic> ev;
        try {
          ev = jsonDecode(dados) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        switch (ev['type']) {
          case 'content_block_delta':
            final d = ev['delta'] as Map<String, dynamic>?;
            if (d != null && d['type'] == 'text_delta') yield d['text'] as String;
          case 'message_delta':
            stopReason = (ev['delta'] as Map?)?['stop_reason'] as String? ?? stopReason;
          case 'error':
            final e = ev['error'] as Map?;
            throw ClaudeErro(e?['type'] == 'overloaded_error'
                ? 'O serviço está sobrecarregado agora. Tente de novo em instantes.'
                : 'Erro do serviço: ${e?['message'] ?? 'desconhecido'}');
        }
      }
      if (stopReason == 'refusal') {
        throw ClaudeErro('O modelo não pôde responder a esta pergunta. Tente reformular.');
      }
      if (stopReason == 'max_tokens') {
        yield '\n\n*(resposta interrompida por tamanho — peça para continuar)*';
      }
    } finally {
      if (client == null) c.close();
    }
  }

  /// Quebra o fluxo de bytes em eventos SSE e devolve o conteúdo dos campos `data:`.
  static Stream<String> _eventos(Stream<List<int>> bytes) async* {
    final buf = StringBuffer();
    await for (final linha in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      if (linha.isEmpty) {
        if (buf.isNotEmpty) {
          yield buf.toString();
          buf.clear();
        }
      } else if (linha.startsWith('data:')) {
        if (buf.isNotEmpty) buf.write('\n');
        buf.write(linha.substring(5).trimLeft());
      }
    }
    if (buf.isNotEmpty) yield buf.toString();
  }

  static String _mensagemHttp(int status, String corpo) {
    var detalhe = '';
    try {
      detalhe = '${(jsonDecode(corpo) as Map)['error']?['message'] ?? ''}';
    } catch (_) {}
    return switch (status) {
      401 || 403 => 'A chave da API foi recusada. Confira a chave em Mais › Configurações.',
      429 => 'Limite de uso atingido. Espere um minuto e tente de novo.',
      529 || 503 => 'O serviço está sobrecarregado agora. Tente de novo em instantes.',
      400 => 'O pedido foi rejeitado pela API. $detalhe',
      _ => 'Erro $status ao falar com o copiloto. $detalhe',
    };
  }
}
