// Caminho: lib/services/clima_service.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';

class ClimaService {
  // Padrão Singleton: Garante que apenas uma instância deste serviço exista na memória
  static final ClimaService _instancia = ClimaService._interno();
  factory ClimaService() => _instancia;
  ClimaService._interno();

  // Variáveis de Controle e Cache
  bool _buscandoClima = false;
  DateTime? _ultimoSucesso;
  List<String> _todasCidadesCache = [];

  Map<String, dynamic> _climaAtualCache = {
    'condicao': 'Carregando...',
    'temperatura': '--',
    'icone': Icons.cloud_outlined,
    'cor': Colors.grey,
    'cidade': 'Detectando local...',
    'umidade': '--',
    'sol': '--',
    'previsao_amanha': '',
  };

  // Configurações de Rede
  static const int _timeoutPadrao = 8;
  final Map<String, String> _headers = {
    'User-Agent': 'SolarInsightApp/1.0',
    'Accept': 'application/json',
  };

  // --- BUSCA CIDADES IBGE ---
  Future<Iterable<String>> getSugestoesIBGE(String query) async {
    if (query.isEmpty) return const Iterable<String>.empty();

    if (_todasCidadesCache.isEmpty) {
      try {
        final response = await http.get(
          Uri.parse(
            'https://servicodados.ibge.gov.br/api/v1/localidades/municipios',
          ),
        );
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body);
          _todasCidadesCache = data.map((city) {
            final nome = city['nome'] ?? '';
            final uf =
                city['microrregiao']?['mesorregiao']?['UF']?['sigla'] ?? '';
            return uf.isNotEmpty ? '$nome - $uf' : nome.toString();
          }).toList();
        }
      } catch (e) {
        debugPrint('Erro ao buscar IBGE: $e');
      }
    }

    final normalizedQuery = _removerAcentosEChars(query.toLowerCase());
    return _todasCidadesCache
        .where((cidade) {
          return _removerAcentosEChars(
            cidade.toLowerCase(),
          ).contains(normalizedQuery);
        })
        .take(8)
        .toList();
  }

  String _removerAcentosEChars(String text) {
    var comAcento = 'áàãâäéèêëíìîïóòõôöúùûüçñ';
    var semAcento = 'aaaaaeeeeiiiiooooouuuucn';
    for (int i = 0; i < comAcento.length; i++) {
      text = text.replaceAll(comAcento[i], semAcento[i]);
    }
    return text;
  }

  // --- BUSCA CLIMA REAL ---
  Future<Map<String, dynamic>> buscarClimaReal({String? cidadeManual}) async {
    // Bloqueio Anti-Spam com Sala de Espera
    if (_buscandoClima) {
      debugPrint('🌩️ [SERVIÇO] Busca em andamento. Aguardando...');
      while (_buscandoClima) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      return _climaAtualCache;
    }

    // Cache de 15 minutos (ignorado se o usuário pesquizar uma nova cidade manualmente)
    if (cidadeManual == null && _ultimoSucesso != null) {
      if (DateTime.now().difference(_ultimoSucesso!).inMinutes < 15) {
        debugPrint('🌩️ [SERVIÇO] Usando cache recente da memória.');
        return _climaAtualCache;
      }
    }

    _buscandoClima = true; // Tranca a porta

    try {
      final box = Hive.box('sync_metadata');

      if (cidadeManual != null) {
        if (cidadeManual.trim().isEmpty) {
          box.delete('cidade_clima');
        } else {
          box.put('cidade_clima', cidadeManual);
        }
      }

      String? cidadeSalva = box.get('cidade_clima');
      double? lat;
      double? lon;
      String nomeLocal = "Local desconhecido";

      // 1. Busca coordenadas via Geocoding
      if (cidadeSalva != null && cidadeSalva.isNotEmpty) {
        String nomePesquisa = cidadeSalva.split('-')[0].trim();
        final geoUrl = Uri.parse(
          'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(nomePesquisa)}&count=1&language=pt',
        );
        final geoRes = await http
            .get(geoUrl, headers: _headers)
            .timeout(const Duration(seconds: _timeoutPadrao));

        if (geoRes.statusCode == 200) {
          final geoData = json.decode(geoRes.body);
          if (geoData['results'] != null && geoData['results'].isNotEmpty) {
            lat = geoData['results'][0]['latitude'];
            lon = geoData['results'][0]['longitude'];
            nomeLocal = cidadeSalva;
          }
        }
      }

      // 2. Busca via IP Automático
      if (lat == null || lon == null) {
        try {
          final ipUrl = Uri.parse('https://freeipapi.com/api/json');
          final ipRes = await http
              .get(ipUrl, headers: _headers)
              .timeout(const Duration(seconds: _timeoutPadrao));

          if (ipRes.statusCode == 200) {
            final ipData = json.decode(ipRes.body);
            lat = (ipData['latitude'] as num?)?.toDouble();
            lon = (ipData['longitude'] as num?)?.toDouble();
            nomeLocal = ipData['cityName'] ?? 'Local Atual';
          }
        } catch (_) {}

        if (lat == null || lon == null) {
          try {
            final ipUrl2 = Uri.parse('https://ipinfo.io/json');
            final ipRes2 = await http
                .get(ipUrl2, headers: _headers)
                .timeout(const Duration(seconds: _timeoutPadrao));

            if (ipRes2.statusCode == 200) {
              final ipData = json.decode(ipRes2.body);
              final loc = ipData['loc']?.toString().split(',');
              if (loc != null && loc.length == 2) {
                lat = double.tryParse(loc[0]);
                lon = double.tryParse(loc[1]);
                nomeLocal = ipData['city'] ?? 'Local Atual';
              }
            }
          } catch (_) {}
        }
      }

      // 3. Busca Clima no Open-Meteo
      if (lat != null && lon != null) {
        final climaUrl = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,is_day,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset&timezone=auto',
        );

        final climaRes = await http
            .get(climaUrl, headers: _headers)
            .timeout(const Duration(seconds: _timeoutPadrao));

        if (climaRes.statusCode == 200) {
          _processarRespostaOpenMeteo(climaRes.body, nomeLocal);
          _ultimoSucesso = DateTime.now();
          return _climaAtualCache;
        }
      }

      _definirClimaIndisponivel();
    } catch (e) {
      debugPrint('❌ Erro no Serviço de Clima: $e');
      _definirClimaIndisponivel();
    } finally {
      _buscandoClima =
          false; // Destranca a porta independentemente do resultado
    }

    return _climaAtualCache;
  }

  void _processarRespostaOpenMeteo(String responseBody, String nomeLocal) {
    final data = json.decode(responseBody);
    final current = data['current'] ?? {};
    final daily = data['daily'] ?? {};

    int weatherCode = current['weather_code'] ?? 0;
    int isDay = current['is_day'] ?? 1;
    final infoClima = _traduzirWmo(weatherCode, isDay == 1);

    String previsaoAmanha = '';
    if (daily['temperature_2m_max'] != null &&
        daily['temperature_2m_max'].length > 1) {
      var tMax = daily['temperature_2m_max'][1];
      var tMin = daily['temperature_2m_min'][1];
      var wCode = daily['weather_code'][1];

      if (tMax != null && tMin != null && wCode != null) {
        String tempMax = tMax.round().toString();
        String tempMin = tMin.round().toString();
        final infoAmanha = _traduzirWmo(wCode, true);
        previsaoAmanha =
            'Amanhã: $tempMax° / $tempMin° (${infoAmanha['condicao']})';
      }
    }

    String sol = '--';
    if (daily['sunrise'] != null && daily['sunrise'].isNotEmpty) {
      String sunriseStr = daily['sunrise'][0] ?? '';
      String sunsetStr = (daily['sunset'] != null && daily['sunset'].isNotEmpty)
          ? daily['sunset'][0] ?? ''
          : '';
      String nascer = sunriseStr.length >= 16
          ? sunriseStr.substring(11, 16)
          : '--';
      String por = sunsetStr.length >= 16 ? sunsetStr.substring(11, 16) : '--';
      sol = '$nascer às $por';
    }

    var currTemp = current['temperature_2m'];
    var currHum = current['relative_humidity_2m'];

    _climaAtualCache = {
      'condicao': infoClima['condicao'],
      'temperatura': currTemp != null ? currTemp.round().toString() : '--',
      'icone': infoClima['icone'],
      'cor': infoClima['cor'],
      'cidade': nomeLocal,
      'umidade': currHum != null ? '${currHum.round()}%' : '--',
      'sol': sol,
      'previsao_amanha': previsaoAmanha,
    };
  }

  void _definirClimaIndisponivel() {
    _climaAtualCache = {
      'condicao': 'Indisponível',
      'temperatura': '--',
      'icone': Icons.cloud_off,
      'cor': Colors.grey,
      'cidade': 'Local não detectado',
      'umidade': '--',
      'sol': '--',
      'previsao_amanha': '',
    };
  }

  Map<String, dynamic> _traduzirWmo(int code, bool isDay) {
    String condicao = "Desconhecido";
    IconData icone = Icons.cloud_outlined;
    Color cor = Colors.blueGrey;

    if (code == 0) {
      condicao = "Céu Limpo";
      icone = isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round;
      cor = isDay ? Colors.orange : Colors.blueGrey;
    } else if (code >= 1 && code <= 3) {
      condicao = code == 1
          ? "Principalmente Limpo"
          : code == 2
          ? "Parcialmente Nublado"
          : "Nublado";
      icone = code == 3
          ? Icons.cloud_rounded
          : (isDay ? Icons.wb_cloudy_rounded : Icons.nightlight_round);
      cor = code == 3
          ? Colors.grey
          : (isDay ? Colors.orangeAccent : Colors.blueGrey);
    } else if (code == 45 || code == 48) {
      condicao = "Nevoeiro";
      icone = Icons.foggy;
      cor = Colors.grey;
    } else if (code >= 51 && code <= 55) {
      condicao = "Chuvisco";
      icone = Icons.grain;
      cor = Colors.lightBlue;
    } else if (code >= 61 && code <= 67) {
      condicao = "Chuva";
      icone = Icons.water_drop_rounded;
      cor = Colors.blue;
    } else if (code >= 71 && code <= 77) {
      condicao = "Neve";
      icone = Icons.ac_unit_rounded;
      cor = Colors.lightBlueAccent;
    } else if (code >= 80 && code <= 82) {
      condicao = "Pancadas de Chuva";
      icone = Icons.water_drop_rounded;
      cor = Colors.blueAccent;
    } else if (code >= 95 && code <= 99) {
      condicao = "Tempestade";
      icone = Icons.thunderstorm_rounded;
      cor = Colors.deepPurple;
    }

    return {'condicao': condicao, 'icone': icone, 'cor': cor};
  }
}
