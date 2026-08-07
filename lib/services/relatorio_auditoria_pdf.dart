// Caminho: lib/services/relatorio_auditoria_pdf.dart

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/usina.dart';
import '../models/lancamento.dart';
import '../utils/calculadora_energetica.dart';

class RelatorioAuditoriaPdf {
  static Future<void> gerarEImprimirPdf(
    Usina usina,
    List<LancamentoMensal> lancamentos,
    MetricasGerais metricas,
  ) async {
    final pdf = pw.Document();

    // 1. Carrega a logo
    late pw.ImageProvider logoImage;
    try {
      logoImage = pw.MemoryImage(
        (await rootBundle.load('assets/logoweb.png')).buffer.asUint8List(),
      );
    } catch (e) {
      logoImage = pw.MemoryImage(Uint8List(0));
    }

    // 2. Formatadores de dados
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final numero = NumberFormat.decimalPattern('pt_BR');

    // Ordena os lançamentos cronologicamente
    final lancsOrdenados = List<LancamentoMensal>.from(lancamentos);
    lancsOrdenados.sort((a, b) => a.dataReferencia.compareTo(b.dataReferencia));

    // Descobre o Período
    String periodoTexto = "";
    if (lancsOrdenados.isNotEmpty) {
      final inicio = DateFormat(
        'MM/yyyy',
      ).format(lancsOrdenados.first.dataReferencia);
      final fim = DateFormat(
        'MM/yyyy',
      ).format(lancsOrdenados.last.dataReferencia);
      periodoTexto = " ($inicio A $fim)";
    }

    // ===================================================================
    // PROCESSAMENTO DE DADOS PARA O GRÁFICO PDF (Até 12 Meses)
    // ===================================================================
    Map<String, Map<String, dynamic>> dadosMensais = {};

    for (var l in lancsOrdenados) {
      String key = DateFormat('yyyyMM').format(l.dataReferencia);
      String display = DateFormat(
        'MMM/yy',
        'pt_BR',
      ).format(l.dataReferencia).toUpperCase();

      dadosMensais.putIfAbsent(
        key,
        () => {
          'mes': display,
          'custo': 0.0,
          'custoProjetado': 0.0,
          'date': l.dataReferencia,
        },
      );

      // --- CORREÇÃO 1: TARIFA INTELIGENTE NO PDF ---
      double tarifaReal = l.tarifaKwh;
      if (l.grupoTarifario == 'A' ||
          l.modalidadeTarifaria == 'VERDE' ||
          l.modalidadeTarifaria == 'AZUL') {
        if ((l.tarifaTeForaPonta ?? 0) > 0) {
          tarifaReal = l.tarifaTeForaPonta! + (l.tarifaTusdForaPonta ?? 0);
        }
      } else {
        if ((l.tarifaTeUnica ?? 0) > 0) {
          tarifaReal = l.tarifaTeUnica! + (l.tarifaTusdUnica ?? 0);
        }
      }
      if (tarifaReal <= 0) {
        tarifaReal = l.tarifaKwh;
      }

      // --- CORREÇÃO 2: DADOS REAIS DO FORMULÁRIO (Igual à tela) ---
      double autoconsumo = (l.geracaoTotalKwh - l.energiaInjetadaKwh).clamp(
        0.0,
        double.infinity,
      );
      double creditosTotaisDisponiveis =
          l.energiaInjetadaKwh + (l.creditosRecebidosDeTerceiros ?? 0.0);

      // A energia compensada real é limitada ao que ele consumiu da rede
      double energiaCompensada = creditosTotaisDisponiveis.clamp(
        0.0,
        l.energiaConsumidaRedeKwh,
      );

      double energiaEfetivamentePoupada = autoconsumo + energiaCompensada;

      // Usa a tarifaReal em vez de l.tarifaKwh
      double economiaFinanceira = energiaEfetivamentePoupada * tarifaReal;
      double custoProjetado = l.valorFaturaR + economiaFinanceira;
      // ----------------------------------------------------------------

      dadosMensais[key]!['custo'] =
          (dadosMensais[key]!['custo'] as double) + l.valorFaturaR;
      dadosMensais[key]!['custoProjetado'] =
          (dadosMensais[key]!['custoProjetado'] as double) + custoProjetado;
    }

    List<Map<String, dynamic>> graficoOrdenado = dadosMensais.values.toList();
    if (graficoOrdenado.length > 12) {
      graficoOrdenado = graficoOrdenado.sublist(graficoOrdenado.length - 12);
    }

    // Calcula o maior valor do gráfico para escalar as barras
    double maxValGrafico = 0;
    for (var d in graficoOrdenado) {
      if (d['custoProjetado'] > maxValGrafico) {
        maxValGrafico = d['custoProjetado'];
      }
      if (d['custo'] > maxValGrafico) maxValGrafico = d['custo'];
    }
    if (maxValGrafico == 0) maxValGrafico = 1;

    // 3. Monta a página do PDF
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        // --- CABEÇALHO REPETIDO EM TODAS AS PÁGINAS ---
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    children: [
                      pw.Image(logoImage, width: 45, height: 45),
                      pw.SizedBox(width: 12),
                      pw.Text(
                        'SolarInsight',
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#FF5722'), // DeepOrange
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'RELATÓRIO DE AUDITORIA',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#455A64'), // BlueGrey800
                        ),
                      ),
                      pw.Text(
                        'Gerado em: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(color: PdfColors.grey400),
              pw.SizedBox(height: 16),
            ],
          );
        },
        // --- CORPO DO RELATÓRIO ---
        build: (pw.Context context) {
          return [
            pw.Text(
              'DADOS DA UNIDADE',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#455A64'),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Unidade: ${usina.nome}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text('Código UC: ${usina.id}'),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Tipo: ${usina.isGeradora ? "Geradora" : "Beneficiária (Consumidora)"}',
                      ),
                      pw.Text(
                        'Concessionária: ${usina.concessionaria.isEmpty ? "Não informada" : usina.concessionaria}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            // --- RESUMO FINANCEIRO ---
            pw.Text(
              'RESUMO GLOBAL DO PERÍODO$periodoTexto',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#455A64'),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Volume Compensado: ${numero.format(usina.isGeradora ? metricas.totalGeradoKwh : metricas.totalInjetadoKwh)} kWh',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        'Média Mensal: ${numero.format(usina.isGeradora ? metricas.mediaGeracao3Meses : (metricas.totalInjetadoKwh / (lancamentos.isEmpty ? 1 : lancamentos.length)))} kWh',
                        style: const pw.TextStyle(color: PdfColors.grey800),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Economia Total: ${moeda.format(metricas.valorTotalEconomizadoR)}',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.green700,
                        ),
                      ),
                      pw.Text(
                        'Saldo Atual Acumulado: ${numero.format(metricas.saldoCreditosEstimado)} kWh',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            // --- GRÁFICO DE CUSTO EVITADO ---
            if (graficoOrdenado.isNotEmpty) ...[
              pw.Text(
                'CUSTO EVITADO (ÚLTIMOS 12 MESES)',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#455A64'),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(8),
                  ),
                ),
                child: pw.Column(
                  children: [
                    // Legenda
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Container(
                          width: 8,
                          height: 8,
                          color: PdfColors.grey300,
                        ),
                        pw.SizedBox(width: 4),
                        pw.Text(
                          'Sem Solar (Custo Projetado)',
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(width: 16),
                        pw.Container(
                          width: 8,
                          height: 8,
                          color: PdfColors.green,
                        ),
                        pw.SizedBox(width: 4),
                        pw.Text(
                          'Com Solar (Custo Real)',
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 16),
                    // Gráfico de Barras
                    pw.SizedBox(
                      height: 130,
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: graficoOrdenado.map((d) {
                          double alturaMax = 80;
                          double hFundo =
                              (d['custoProjetado'] / maxValGrafico) * alturaMax;
                          double hFrente =
                              (d['custo'] / maxValGrafico) * alturaMax;

                          // Impede que barras minúsculas sumam
                          if (hFundo < 2 && d['custoProjetado'] > 0) hFundo = 2;
                          if (hFrente < 2 && d['custo'] > 0) hFrente = 2;

                          return pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.end,
                            children: [
                              // Valor do Fundo (Projetado) se for muito maior
                              if (d['custoProjetado'] > (d['custo'] + 10))
                                pw.Text(
                                  NumberFormat.compact().format(
                                    d['custoProjetado'],
                                  ),
                                  style: pw.TextStyle(
                                    fontSize: 7,
                                    color: PdfColors.grey500,
                                  ),
                                ),
                              // Valor Real
                              pw.Text(
                                NumberFormat.compact().format(d['custo']),
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.green,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              // As duas barras sobrepostas
                              pw.SizedBox(
                                width: 16,
                                height: hFundo,
                                child: pw.Stack(
                                  alignment: pw.Alignment.bottomCenter,
                                  children: [
                                    pw.Container(
                                      width: 12,
                                      height: hFundo,
                                      color: PdfColors.grey300,
                                    ),
                                    pw.Container(
                                      width: 6,
                                      height: hFrente,
                                      color: PdfColors.green,
                                    ),
                                  ],
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                d['mes'],
                                style: const pw.TextStyle(fontSize: 7),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),
            ],

            // --- TABELA DETALHADA ---
            pw.Text(
              'DETALHAMENTO MENSAL DE BALANÇO E AUDITORIA',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#455A64'),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: [
                'Mês/Ano',
                'Energia Total\n(kWh)', // Genérico para cobrir todos os 3 cenários
                'Consumiu\n(kWh)',
                'Fatura',
                'Sobrou/Faltou\n(kWh)',
                'Status Auditoria',
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 10,
              ),
              headerDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#455A64'),
              ), // BlueGrey800
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.center,
              oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
              data: lancsOrdenados.reversed.map((l) {
                final resumo = CalculadoraEnergetica.gerarResumoMesOficial(
                  usina,
                  l,
                );
                final idx = lancsOrdenados.indexOf(l);
                final anterior = idx > 0 ? lancsOrdenados[idx - 1] : null;
                final desvio = CalculadoraEnergetica.calcularDesvioDoMes(
                  usina,
                  l,
                  anterior,
                );

                // Lógica de "Energia Total" baseada APENAS no formulário
                double energiaTotal = l.geracaoTotalKwh;
                if (energiaTotal == 0 && l.energiaInjetadaKwh > 0) {
                  energiaTotal = l
                      .energiaInjetadaKwh; // Caso só lance injeção e não a geração bruta
                }
                energiaTotal += (l.creditosRecebidosDeTerceiros ?? 0.0);

                return [
                  DateFormat('MM/yyyy').format(l.dataReferencia),
                  numero.format(energiaTotal),
                  numero.format(resumo.consumoRealLocal),
                  moeda.format(l.valorFaturaR),
                  '${resumo.sobraFisicaDoMes >= 0 ? "+" : ""}${numero.format(resumo.sobraFisicaDoMes)}',
                  desvio > 0
                      ? 'ALERTA DESVIO\n(${numero.format(desvio)} kWh)'
                      : 'OK',
                ];
              }).toList(),
            ),
          ];
        },
      ),
    );

    // 4. Dispara a ação de impressão nativa (Funciona na Web, iOS e Android)
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Auditoria_${usina.nome.replaceAll(" ", "_")}.pdf',
    );
  }
}
