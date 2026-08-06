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
      const promptText = r'''
Você é um Engenheiro Eletricista e Auditor especialista em faturamento de energia e regulamentação da ANEEL (Brasil), com foco em Geração Distribuída (Lei 14.300).
Sua tarefa é analisar a fatura de energia elétrica em PDF e extrair os dados reais.
Retorne EXCLUSIVAMENTE um objeto JSON válido.

REGRAS RÍGIDAS DE EXTRAÇÃO:

1. CLASSIFICAÇÃO DA USINA E CONCESSIONÁRIA:
- Identifique a concessionária (EDP ou Santa Maria).
- Identifique o Grupo Tarifário. ATENÇÃO: Contas com Tensão Nominal igual ou superior a 13.800V ou 13.8kV, ou que possuam as palavras "Subgrupo A4" ou "Grupo A", SÃO OBRIGATORIAMENTE GRUPO A. Todo o resto é Grupo B.

2. CONSUMO REAL (kWh):
- 🚨 NUNCA utilize valores das seções de "Medidor" ou "Detalhes de Leitura" onde houver avisos de "Perdas de Transformação" (ex: 2.5%).
- Se SANTA MARIA: Vá OBRIGATORIAMENTE no quadro "GRANDEZAS MEDIDAS". Olhe apenas a coluna "VALOR MEDIDO". Some EXCLUSIVAMENTE os valores numéricos das linhas que começam com "Energia ativa consumo" e "Energia ativa consumo horário reservado". Lance a soma em "unico". É PROIBIDO ler o "Histórico de Faturamento".
- Se EDP GRUPO A: Busque EXCLUSIVAMENTE no quadro "DETALHES DE FATURAMENTO". Extraia a quantidade (kWh) das linhas "Energia Ativa Fornecida Ponta", "Energia Ativa Fornecida Fora Ponta" e "Energia Ativa Fornecida Reservado".
- Se EDP GRUPO B: Busque no quadro "Detalhes do faturamento". Some as quantidades de todas as linhas que contenham "Energia Ativa Fornecida" e lance em "unico".

3. ENERGIA INJETADA (kWh) - A REGRA DE OURO:
- 🚨 PROIBIDO: NUNCA pegue valores das linhas de faturamento com palavras como "Inj. mUC", "Consumo SCEE" ou valores negativos (-). Isso é compensação financeira, não injeção física.
- Se SANTA MARIA: Procure EXCLUSIVAMENTE no quadro "GRANDEZAS MEDIDAS" na coluna "VALOR MEDIDO". A injeção é o valor da linha "Energia ativa injetada".
- Se EDP GRUPO B: Procure EXCLUSIVAMENTE no quadro "INFORMAÇÕES SOBRE MICRO E MINIGERAÇÃO DISTRIBUÍDA" a linha "Energia Injetada no mês".
- Se EDP GRUPO A: Procure no quadro "INFORMAÇÕES SOBRE MICRO E MINIGERAÇÃO DISTRIBUÍDA". Extraia "Energia Injetada Ponta", "Energia Injetada Fora Ponta" e "Energia Injetada Reservado". Se não houver separação, coloque o valor total em "unico".

4. TARIFAS E VALORES (R$ e R$/kWh):
- Tarifas EDP GRUPO A: Busque no quadro "DETALHES DE FATURAMENTO" as linhas escritas EXATAMENTE "Tarifa ANEEL TUSD/TE Ponta" e "Tarifa ANEEL TUSD/TE FPonta".
- Tarifas GRUPO B (Santa Maria): No quadro "ITENS DA FATURA", pegue o "PREÇO UNIT.(R$)" da linha "Consumo" ou "Consumo SCEE" (o maior preço). Lance em 'teUnica' e 0.0 em 'tusdUnica'.
- Tarifas GRUPO B (EDP): No quadro "Detalhes do faturamento", extraia o preço unitário da linha "TE - Energia Ativa Fornecida" (para 'teUnica') e da linha "TUSD - Energia Ativa Fornecida" (para 'tusdUnica').
- Custos Adicionais e Multas: 
  * Se EDP GRUPO A: É EXPRESSAMENTE PROIBIDO extrair Demanda e Multas do quadro final "DETALHES DE FATURAMENTO". Você DEVE ir ao quadro das primeiras páginas que possui a coluna "Valor Total R$" (que já embute os tributos). Extraia os valores de "Demanda", "Demanda Geração", "ERE..." e "DRE..." EXCLUSIVAMENTE dessa coluna.
  * Se GRUPO B: Procure no quadro de Itens Faturados normais.
  * Some as demandas em "demanda" e as multas em "multaReativo". Se não houver, retorne 0.0.
- Iluminação Pública ("iluminacaoPublica"): Extraia o valor da linha "Iluminação Pública" ou "Contr. Iluminação".
- Saldos de Crédito de Energia: Vá ao quadro de "MENSAGENS" ou "INFORMAÇÕES SOBRE MICRO E MINIGERAÇÃO". Você DEVE extrair DOIS valores distintos em kWh:
  1. Saldo Anterior ("saldoAnteriorFatura"): Localize textos como "Saldo anterior" e extraia o valor numérico (Ex: se estiver escrito "Saldo anterior 1.474,60 kWh", extraia 1474.60).
  2. Saldo Atual ("saldoCreditosAcumuladosKwh"): Localize textos como "Saldo atual", "Saldo Total" ou "Saldo Atualizado". ATENÇÃO: A EDP costuma errar a unidade e digitar "kW" em vez de "kWh". IGNORE O ERRO e extraia o número numérico final do mês.
🚨 PROIBIDO: NUNCA utilize valores de PIS, COFINS, Multa por atraso ou Juros.

FORMATO DE SAÍDA OBRIGATÓRIO (NÃO USE MARKDOWN ```json, APENAS O TEXTO PURO):
{
  "debugLog": "Escreva detalhadamente de qual quadro extraiu os Saldos Anterior e Atual e quais foram os valores encontrados.",
  "dadosGerais": {
    "mesReferencia": "MM/YYYY",
    "grupoTarifario": "A",
    "modalidade": "VERDE",
    "valorTotalFatura": 0.00,
    "saldoAnteriorFatura": 0.0,
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

          // INSTANCIAÇÃO ATUALIZADA COM AS TRAVAS DE SEGURANÇA E FORMATO
          final model = GenerativeModel(
            model: nomeModelo,
            apiKey: apiKey,
            generationConfig: GenerationConfig(
              temperature: 0.0, // Elimina a aleatoriedade/criatividade da IA
              responseMimeType:
                  'application/json', // Força a saída estritamente em JSON
            ),
          );

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
              final jsonFinal = jsonDecode(jsonPuro);

              // AQUI ESTÁ O SEU DEBUG MAGNÍFICO:
              debugPrint('====================================');
              debugPrint('🕵️ O QUE A IA PENSOU:');
              debugPrint(jsonFinal['debugLog']);
              debugPrint('====================================');

              return jsonFinal;
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
