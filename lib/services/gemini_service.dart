// Caminho: lib/services/gemini_service.dart
// Descrição: Serviço de Integração com o Google Gemini (Versão Web-Safe via REST API).

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class GeminiService {
  Future<Map<String, dynamic>?> analisarFaturaPdf(Uint8List pdfBytes) async {
    try {
      final apiKey = dotenv.env['GEMINI_API_KEY']
          ?.replaceAll('"', '')
          .replaceAll("'", '')
          .trim();

      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('Erro: Chave do Gemini não encontrada no .env ou vazia.');
        return null;
      }

      // 1. LISTA DE MODELOS À PROVA DE FALHAS
      final modelosParaTestar = [
        'gemini-2.5-flash',
        'gemini-2.0-flash',
        'gemini-1.5-flash',
        'gemini-1.5-pro',
      ];

      const promptText = '''
Você é um Engenheiro Eletricista especialista em faturamento de energia e regulamentação da ANEEL (Brasil), com foco em Geração Distribuída (Lei 14.300).
Sua tarefa é analisar faturas de energia elétrica em PDF e extrair os dados com precisão cirúrgica, retornando EXCLUSIVAMENTE um objeto JSON válido.

REGRAS DE EXTRAÇÃO:
1. CLASSIFICAÇÃO DA USINA: Identifique se a conta é do Grupo A (Verde/Azul) ou B (Convencional).
2. CONSUMO E INJEÇÃO (kWh): 
- Grupo A: Extraia Ponta, Fora Ponta e Reservado.
- Grupo B: Extraia em 'unico'.
- Injeção: Procure 'Energia Injetada', 'Energia Compensada GD' ou quadros de Microgeração.
3. TARIFAS (R\$/kWh): Separe TE e TUSD. Extraia por posto tarifário se Grupo A.
4. CUSTOS FIXOS E MULTAS (R\$): Demanda, Multa Reativo (ERE+DRE), Iluminação Pública (CIP/COSIP).
5. DADOS FINANCEIROS: Mês/Ano de referência (Ex: "07/2025"), Valor Total, Saldo Acumulado.

FORMATO DE SAÍDA OBRIGATÓRIO:
{
  "dadosGerais": {
    "mesReferencia": "MM/YYYY",
    "grupoTarifario": "A",
    "modalidade": "VERDE",
    "valorTotalFatura": 0.00,
    "saldoCreditosAcumuladosKwh": 0.0
  },
  "energiaKwh": {
    "consumo": { "unico": 0.0, "ponta": 0.0, "foraPonta": 0.0, "reservado": 0.0 },
    "injetada": { "unico": 0.0, "ponta": 0.0, "foraPonta": 0.0, "reservado": 0.0 }
  },
  "tarifasReaisPorKwh": {
    "teUnica": 0.0000, "tusdUnica": 0.0000,
    "tePonta": 0.0000, "tusdPonta": 0.0000,
    "teForaPonta": 0.0000, "tusdForaPonta": 0.0000
  },
  "custosAdicionaisReais": {
    "demanda": 0.00, "iluminacaoPublica": 0.00, "multaReativo": 0.00
  }
}
Se um campo não existir na fatura, retorne 0.0 (números) ou null (textos).
''';

      // Converte o PDF para Base64 (Necessário para a API REST)
      String base64Pdf = base64Encode(pdfBytes);

      // 2. LOOP DE TENTATIVAS VIA HTTP REST
      for (String nomeModelo in modelosParaTestar) {
        try {
          debugPrint(
            '🤖 Tentando comunicar com o modelo: $nomeModelo via HTTP...',
          );

          final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/$nomeModelo:generateContent?key=$apiKey',
          );

          // Monta o corpo da requisição exatamente como o pacote oficial faz por trás dos panos
          final body = jsonEncode({
            "contents": [
              {
                "parts": [
                  {"text": promptText},
                  {
                    "inlineData": {
                      "mimeType": "application/pdf",
                      "data": base64Pdf,
                    },
                  },
                ],
              },
            ],
            // Força a IA a cuspir JSON puro (Garante menos erros no decode)
            "generationConfig": {"responseMimeType": "application/json"},
          });

          final response = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: body,
          );

          if (response.statusCode == 200) {
            debugPrint('✅ SUCESSO! O modelo $nomeModelo processou a fatura.');

            final jsonResponse = jsonDecode(response.body);

            // Navega na estrutura do JSON de resposta da API do Gemini
            String? textoGerado =
                jsonResponse['candidates']?[0]['content']['parts']?[0]['text'];

            if (textoGerado != null && textoGerado.isNotEmpty) {
              // 3. LIMPEZA DE DADOS
              String jsonPuro = textoGerado
                  .replaceAll('```json', '')
                  .replaceAll('```', '')
                  .trim();

              return jsonDecode(jsonPuro);
            }
          } else {
            debugPrint(
              '❌ O modelo $nomeModelo retornou erro HTTP: ${response.statusCode} - ${response.body}',
            );
            // Se o erro for de versão, continua o loop. Se for de API Key, aborta para não perder tempo.
            if (response.statusCode == 400 &&
                response.body.contains("API key not valid")) {
              debugPrint('🚨 ERRO: A chave de API fornecida é inválida.');
              return null;
            }
          }
        } catch (e) {
          debugPrint('❌ Falha ao tentar conectar ao $nomeModelo. Erro: $e');
        }
      }

      debugPrint(
        '🚨 ERRO: Nenhum modelo conseguiu processar o documento via Web.',
      );
      return null;
    } catch (e) {
      debugPrint('🚨 Erro Fatal no GeminiService: $e');
      return null;
    }
  }
}
