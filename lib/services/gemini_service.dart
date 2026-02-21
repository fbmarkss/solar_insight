// Caminho: lib/services/gemini_service.dart
// Descrição: Serviço de Integração com o Google Gemini (Versão com Busca Inteligente de Modelos).

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
          .trim();

      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('Erro: Chave do Gemini não encontrada no .env ou vazia.');
        return null;
      }

      // 1. LISTA DE MODELOS À PROVA DE FALHAS
      // O aplicativo vai tentar do mais moderno para o mais antigo até o servidor do Google aceitar.
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

      // 2. LOOP DE TENTATIVAS
      for (String nomeModelo in modelosParaTestar) {
        try {
          debugPrint('🤖 Tentando comunicar com o modelo: $nomeModelo...');

          final model = GenerativeModel(
            model: nomeModelo,
            apiKey: apiKey,
            // Removido o responseMimeType para evitar bloqueio de API Version
          );

          final response = await model.generateContent([
            Content.multi([prompt, pdfPart]),
          ]);

          if (response.text != null && response.text!.isNotEmpty) {
            debugPrint('✅ SUCESSO! O modelo $nomeModelo processou a fatura.');

            // 3. LIMPEZA DE DADOS
            // Como removemos a trava da API, a IA pode devolver o texto com marcações Markdown.
            String jsonPuro = response.text!;
            jsonPuro = jsonPuro
                .replaceAll('```json', '')
                .replaceAll('```', '')
                .trim();

            return jsonDecode(jsonPuro);
          }
        } catch (e) {
          debugPrint('❌ O modelo $nomeModelo foi rejeitado. Erro: $e');
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
