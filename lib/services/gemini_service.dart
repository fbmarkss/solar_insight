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

      // =======================================================================
      // PROMPT SNIPER: Otimizado para EDP (Grupos A e B) e Santa Maria (Grupo B)
      // =======================================================================
      const promptText = '''
Você é um Engenheiro Eletricista e Auditor especialista em faturamento de energia e regulamentação da ANEEL (Brasil), com foco em Geração Distribuída (Lei 14.300).
Sua tarefa é analisar a fatura de energia elétrica em PDF e extrair os dados reais, ignorando as linhas de compensação financeira.
Retorne EXCLUSIVAMENTE um objeto JSON válido.

REGRAS RÍGIDAS DE EXTRAÇÃO:
1. CLASSIFICAÇÃO DA USINA: 
- Identifique se é Grupo A (Tensão > 2.3kV, ex: A4, Verde) ou Grupo B (Baixa Tensão).

2. CONSUMO REAL (kWh):
- Se SANTA MARIA: Procure o quadro "Grandezas". O consumo real é o "Valor medido" da linha "Energia ativa consumo".
- Se EDP GRUPO A: Some o consumo medido em Ponta, Fora Ponta e Reservado (busque no quadro Detalhes do Faturamento).
- Se EDP GRUPO B: Busque o valor total de kWh da "Energia Ativa Fornecida".

3. ENERGIA INJETADA (kWh) - A REGRA DE OURO PARA NÃO ERRAR:
- 🚨 PROIBIDO: NUNCA pegue valores das linhas de faturamento com palavras como "Inj. mUC", "Consumo SCEE" ou valores negativos (-). Isso é compensação, não injeção.
- Se SANTA MARIA: Procure EXCLUSIVAMENTE no quadro "Grandezas". A injeção é o "Valor medido" da linha "Energia ativa injetada".
- Se EDP GRUPO B: Procure EXCLUSIVAMENTE no quadro "INFORMAÇÕES SOBRE MICRO E MINIGERAÇÃO DISTRIBUÍDA" a linha "Energia Injetada no mês".
- Se EDP GRUPO A: Procure no mesmo quadro "INFORMAÇÕES SOBRE MICRO E MINIGERAÇÃO DISTRIBUÍDA". Separe os valores exatos de "Energia Injetada Ponta", "Energia Injetada Fora Ponta" e "Energia Injetada Reservado".

4. TARIFAS E VALORES (R\$ e R\$/kWh):
- Tarifas Grupo A (EDP): No final do PDF há linhas escritas "Tarifa ANEEL TUSD/TE Ponta" e "Tarifa ANEEL TUSD/TE FPonta". Extraia com todas as casas decimais.
- Tarifas Grupo B: Extraia a tarifa unitária da linha de Consumo. Se a concessionária não separar TE e TUSD (como a Santa Maria), coloque o valor total em 'teUnica' e 0.0 em 'tusdUnica'.
- Custos Adicionais: Demanda (R\$), Multa de Reativo (Procure por ERE ou DRE em R\$), Iluminação Pública (CIP/COSIP em R\$).
- Saldo de Créditos: Procure por "Saldo Atualizado no mês" ou "Saldo atual".

FORMATO DE SAÍDA OBRIGATÓRIO (NÃO USE MARKDOWN ```json, APENAS O TEXTO PURO):
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

      String ultimoErro = '';

      for (String nomeModelo in modelosParaTestar) {
        try {
          debugPrint('🤖 Tentando comunicar com o modelo: $nomeModelo...');

          final model = GenerativeModel(model: nomeModelo, apiKey: apiKey);

          final response = await model.generateContent([
            Content.multi([prompt, pdfPart]),
          ]);

          if (response.text != null && response.text!.isNotEmpty) {
            debugPrint('✅ SUCESSO! O modelo $nomeModelo processou a fatura.');

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
          ultimoErro = e.toString();
        }
      }

      throw Exception(
        'Acesso bloqueado pela API ou falha de conexão.\nDetalhe: $ultimoErro',
      );
    } catch (e) {
      debugPrint('🚨 Erro Fatal no GeminiService: $e');
      rethrow;
    }
  }
}
