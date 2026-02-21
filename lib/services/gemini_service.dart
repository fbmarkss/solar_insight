// Caminho: lib/services/gemini_service.dart
// Descrição: Serviço de Integração com o Google Gemini (Código Original Restaurado e Seguro).

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiService {
  Future<Map<String, dynamic>?> analisarFaturaPdf(Uint8List pdfBytes) async {
    try {
      final apiKey = dotenv.env['GEMINI_API_KEY']
          ?.replaceAll('"', '')
          .replaceAll("'", '')
          .replaceAll('[', '')
          .replaceAll(']', '')
          .trim();

      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('Erro: Chave do Gemini não encontrada no env.txt ou vazia.');
        return null;
      }

      // 1. A SUA LISTA DE MODELOS À PROVA DE FALHAS (Restaurada)
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

      // 2. O SEU LOOP DE TENTATIVAS VIA SDK
      for (String nomeModelo in modelosParaTestar) {
        try {
          debugPrint('🤖 Tentando comunicar com o modelo: $nomeModelo...');

          // A SUA ESTRUTURA ORIGINAL (Sem o responseMimeType que causava o bloqueio)
          final model = GenerativeModel(model: nomeModelo, apiKey: apiKey);

          final response = await model.generateContent([
            Content.multi([prompt, pdfPart]),
          ]);

          if (response.text != null && response.text!.isNotEmpty) {
            debugPrint('✅ SUCESSO! O modelo $nomeModelo processou a fatura.');

            // 3. LIMPEZA AVANÇADA DE DADOS
            // Como removemos a trava da API, a IA VAI devolver o texto com marcações Markdown.
            // Este filtro garante que extraímos apenas o JSON puro!
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
              debugPrint(
                '❌ Erro: O texto retornado não contém um JSON válido.',
              );
            }
          }
        } catch (e) {
          debugPrint('❌ O modelo $nomeModelo falhou. Erro: $e');
          // Continua o loop para testar o próximo modelo da lista
        }
      }

      debugPrint('🚨 ERRO: Nenhum modelo foi aceite pela sua conta Google.');
      return null;
    } catch (e) {
      debugPrint('🚨 Erro Fatal no GeminiService: $e');
      return null;
    }
  }
}
