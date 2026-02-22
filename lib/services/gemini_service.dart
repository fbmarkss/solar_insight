// Caminho: lib/services/gemini_service.dart
// Descrição: Serviço de Integração com o Google Gemini (Seguro, com Chaves Separadas Web/Mobile e Tratamento Claro de Erros).

import 'dart:convert';
import 'package:flutter/foundation.dart'; // <--- Necessário para o kIsWeb
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiService {
  Future<Map<String, dynamic>?> analisarFaturaPdf(Uint8List pdfBytes) async {
    try {
      // 1. O Flutter decide na hora qual chave puxar do arquivo de variáveis
      String? chaveBruta = kIsWeb
          ? dotenv.env['GEMINI_API_KEY_WEB']
          : dotenv.env['GEMINI_API_KEY_ANDROID'];

      // 2. Limpeza de segurança (remove aspas e colchetes residuais)
      final apiKey = chaveBruta
          ?.replaceAll('"', '')
          .replaceAll("'", '')
          .replaceAll('[', '')
          .replaceAll(']', '')
          .trim();

      if (apiKey == null || apiKey.isEmpty) {
        // 🚨 NOVO: Dispara o erro claro em vez de retornar null
        throw Exception(
          'Chave da IA não encontrada para este dispositivo. Verifique o arquivo de configuração.',
        );
      }

      // 3. LISTA DE MODELOS À PROVA DE FALHAS
      final modelosParaTestar = [
        'gemini-2.5-flash',
        'gemini-2.0-flash',
        'gemini-1.5-flash',
        'gemini-1.5-flash-001',
        'gemini-1.5-flash-002',
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

      final prompt = TextPart(promptText);
      final pdfPart = DataPart('application/pdf', pdfBytes);

      // 🚨 NOVO: Variável para guardar o último erro do Google Cloud
      String ultimoErro = '';

      // 4. O SEU LOOP DE TENTATIVAS VIA SDK
      for (String nomeModelo in modelosParaTestar) {
        try {
          debugPrint('🤖 Tentando comunicar com o modelo: $nomeModelo...');

          final model = GenerativeModel(model: nomeModelo, apiKey: apiKey);

          final response = await model.generateContent([
            Content.multi([prompt, pdfPart]),
          ]);

          if (response.text != null && response.text!.isNotEmpty) {
            debugPrint('✅ SUCESSO! O modelo $nomeModelo processou a fatura.');

            // 5. LIMPEZA AVANÇADA DE DADOS
            String jsonPuro = response.text!
                .replaceAll('```json', '')
                .replaceAll('```', '')
                .trim();

            int startIndex = jsonPuro.indexOf('{');
            int endIndex = jsonPuro.lastIndexOf('}');

            if (startIndex != -1 && endIndex != -1) {
              jsonPuro = jsonPuro.substring(startIndex, endIndex + 1);
              return jsonDecode(jsonPuro);
            } else {
              throw Exception(
                'O texto retornado pela IA não contém um JSON válido.',
              );
            }
          }
        } catch (e) {
          debugPrint('❌ O modelo $nomeModelo falhou. Erro: $e');
          // 🚨 NOVO: Guarda o motivo da falha para mostrar na tela depois
          ultimoErro = e.toString();
        }
      }

      // 🚨 NOVO: Se o loop terminou e não retornou o JSON, dispara o erro consolidado
      throw Exception(
        'Acesso bloqueado pela API ou falha de conexão.\nDetalhe: $ultimoErro',
      );
    } catch (e) {
      debugPrint('🚨 Erro Fatal no GeminiService: $e');
      // 🚨 NOVO: O 'rethrow' pega a Exception gerada aqui dentro e joga para a Tela do App
      rethrow;
    }
  }
}
