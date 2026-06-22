import 'dart:convert';
import 'dart:io';

import 'package:dartx/dartx.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:andreyvpn/core/db/db.dart';
import 'package:andreyvpn/core/directories/directories_provider.dart';
import 'package:andreyvpn/core/logger/rotating_file_log.dart';
import 'package:andreyvpn/core/http_client/dio_http_client.dart';
import 'package:andreyvpn/features/profile/data/profile_data_mapper.dart';
import 'package:andreyvpn/features/profile/model/profile_entity.dart';
import 'package:andreyvpn/features/profile/model/profile_failure.dart';
import 'package:andreyvpn/features/settings/data/config_option_repository.dart';
import 'package:andreyvpn/singbox/model/singbox_proxy_type.dart';
import 'package:andreyvpn/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';

/// parse profile subscription url and headers for data
///
/// ***name parser hierarchy:***
/// - UserOverride.name
/// - `profile-title` header
/// - `content-disposition` header
/// - url fragment (example: `https://example.com/config#user`) -> name=`user`
/// - url filename extension (example: `https://example.com/config.json`) -> name=`config`
/// - if none of these methods return a non-blank string, switch(profileType)
/// - remote:  fallback to `Remote Profile`
/// - local: fallback to protocol, extracted from content by protocol()

class ProfileParser {
  static const infiniteTrafficThreshold = 920_233_720_368;
  static const infiniteTimeThreshold = 92_233_720_368;
  static const allowedOverrideConfigs = [
    'connection-test-url',
    'direct-dns-address',
    'remote-dns-address',
    'warp',
    'warp2',
    'tls-tricks',
  ];
  static const allowedProfileHeaders = [
    'profile-title',
    'content-disposition',
    'subscription-userinfo',
    'profile-update-interval',
    'support-url',
    'profile-web-page-url',
    'enable-warp',
    'enable-fragment',
  ];

  final Ref _ref;
  final DioHttpClient _httpClient;

  ProfileParser({required Ref ref, required DioHttpClient httpClient}) : _ref = ref, _httpClient = httpClient;
  TaskEither<ProfileFailure, ProfileEntriesCompanion> addLocal({
    required String id,
    required String content,
    required String tempFilePath,
    required UserOverride? userOverride,
  }) {
    return TaskEither.tryCatch(() async {
          await expandRemoteLinesInParallel(
            tempFilePath: tempFilePath,
            httpClient: _httpClient,
            cancelToken: CancelToken(),
            ref: _ref,
          );
          await normalizeJsonArraySubscriptionIfNeeded(
            tempFilePath: tempFilePath,
            source: 'local',
          );
        }, (_, __) => ProfileFailure.unexpected())
        .flatMap((_) => TaskEither.fromEither(populateHeaders(content: content)))
        .flatMap(
          (populatedHeaders) => TaskEither.fromEither(
            parse(
              tempFilePath: tempFilePath,
              profile: ProfileEntity.local(
                id: id,
                active: true,
                name: '',
                lastUpdate: DateTime.now(),
                userOverride: userOverride,
                populatedHeaders: populatedHeaders,
              ),
            ).flatMap((profEntity) => Either.tryCatch(() => profEntity.toInsertEntry(), ProfileFailure.unexpected)),
          ),
        );
  }

  TaskEither<ProfileFailure, ProfileEntriesCompanion> addRemote({
    required String id,
    required String url,
    required String tempFilePath,
    required UserOverride? userOverride,
    CancelToken? cancelToken,
  }) => _downloadProfile(url, tempFilePath, cancelToken).flatMap(
    (remoteHeaders) =>
        TaskEither.fromEither(
          populateHeaders(content: File(tempFilePath).readAsStringSync(), remoteHeaders: remoteHeaders),
        ).flatMap(
          (populatedHeaders) => TaskEither.fromEither(
            parse(
              tempFilePath: tempFilePath,
              profile: ProfileEntity.remote(
                id: id,
                active: true,
                name: '',
                url: url,
                lastUpdate: DateTime.now(),
                userOverride: userOverride,
                populatedHeaders: populatedHeaders,
              ),
            ).flatMap((profEntity) => Either.tryCatch(() => profEntity.toInsertEntry(), ProfileFailure.unexpected)),
          ),
        ),
  );

  TaskEither<ProfileFailure, ProfileEntriesCompanion> updateRemote({
    required RemoteProfileEntity rp,
    required String tempFilePath,
    CancelToken? cancelToken,
  }) => _downloadProfile(rp.url, tempFilePath, cancelToken).flatMap(
    (remoteHeaders) =>
        TaskEither.fromEither(
          populateHeaders(content: File(tempFilePath).readAsStringSync(), remoteHeaders: remoteHeaders),
        ).flatMap(
          (populatedHeaders) => TaskEither.fromEither(
            parse(
              tempFilePath: tempFilePath,
              profile: rp.copyWith(populatedHeaders: populatedHeaders),
            ).flatMap((profEntity) => Either.tryCatch(() => profEntity.toUpdateEntry(), ProfileFailure.unexpected)),
          ),
        ),
  );

  Either<ProfileFailure, ProfileEntriesCompanion> offlineUpdate({
    required ProfileEntity profile,
    required String tempFilePath,
  }) => profile
      .map(
        remote: (rp) => parse(profile: rp, tempFilePath: tempFilePath),
        local: (lp) => parse(tempFilePath: tempFilePath, profile: lp),
      )
      .flatMap((profEntity) => Either.tryCatch(() => profEntity.toUpdateEntry(), ProfileFailure.unexpected));

  TaskEither<ProfileFailure, Map<String, dynamic>> _downloadProfile(
    String url,
    String tempFilePath,
    CancelToken? cancelToken,
  ) => TaskEither.tryCatch(() async {
    // if (url.startsWith("http://"))
    //   throw const ProfileFailure.invalidUrl('HTTP is not supported. Please use HTTPS for secure connection.');

    final rs = await _httpClient
        .download(
          url.trim(),
          tempFilePath,
          cancelToken: cancelToken,
          userAgent: _ref.read(ConfigOptions.useXrayCoreWhenPossible)
              ? _httpClient.userAgent.replaceAll("HiddifyNext", "HiddifyNextX")
              : null,
        )
        .catchError((err) {
          if (CancelToken.isCancel(err as DioException)) {
            throw const ProfileFailure.cancelByUser('HTTP request for getting profile content canceled by user.');
          }
          throw err;
        });
    await expandRemoteLinesInParallel(
      tempFilePath: tempFilePath,
      httpClient: _httpClient,
      cancelToken: cancelToken ?? CancelToken(),
      ref: _ref,
    );
    await normalizeJsonArraySubscriptionIfNeeded(
      tempFilePath: tempFilePath,
      source: url,
    );
    // fixing headers before return
    return rs.headers.map.map((key, value) {
      if (value.length == 1) return MapEntry(key, value.first);
      return MapEntry(key, value);
    });
  }, (err, st) => err is ProfileFailure ? err : ProfileFailure.unexpected(err, st));
  Future<void> expandRemoteLinesInParallel({
    required String tempFilePath,
    required DioHttpClient httpClient,
    required CancelToken cancelToken,
    required Ref ref,
    int parallelism = 4,
  }) async {
    final content = await File(tempFilePath).readAsString();
    final lines = content.split('\n');

    final results = List<String?>.filled(lines.length, null);

    int index = 0;

    Future<void> worker() async {
      while (true) {
        if (cancelToken.isCancelled) return;

        final currentIndex = index++;
        if (currentIndex >= lines.length) return;

        final line = lines[currentIndex];

        // Non-URL
        if (!line.startsWith('http://') && !line.startsWith('https://')) {
          results[currentIndex] = line.trim();
          continue;
        }

        try {
          final tmpPath = '$tempFilePath.$currentIndex';

          await httpClient.download(
            line,
            tmpPath,
            cancelToken: cancelToken,
            userAgent: ref.read(ConfigOptions.useXrayCoreWhenPossible)
                ? httpClient.userAgent.replaceAll('HiddifyNext', 'HiddifyNextX')
                : null,
          );

          results[currentIndex] = (await File(tmpPath).readAsString()).trim();
        } catch (err) {
          if (err is DioException && CancelToken.isCancel(err)) {
            return;
          }
          results[currentIndex] = '';
        }
      }
    }

    // Start workers
    await Future.wait(List.generate(parallelism, (_) => worker()));

    if (results.any((e) => e != null)) {
      final newContent = results.join("\n");
      await File(tempFilePath).writeAsString(newContent);
    }
  }


  static Future<void> normalizeJsonArraySubscriptionIfNeeded({
    required String tempFilePath,
    required String source,
  }) async {
    final file = File(tempFilePath);
    if (!await file.exists()) return;

    final rawContent = await file.readAsString();
    final content = rawContent.trim();
    if (!content.startsWith('[')) return;

    Future<void> log(String message) async {
      try {
        final logsDir = await AppDirectories.getLogsDirectory();
        final logFile = File('${logsDir.path}${Platform.pathSeparator}andreyvpn_json_subscription.log');
        await RotatingFileLog.append(
          logFile,
          '[${DateTime.now().toIso8601String()}] $message\n',
          detailed: true,
        );
      } catch (_) {
        // JSON subscription diagnostics must never block profile parsing.
      }
    }

    try {
      final decoded = jsonDecode(content);
      if (decoded is! List) return;

      final links = <String>[];
      var skipped = 0;
      for (final item in decoded) {
        if (item is! Map) {
          skipped++;
          continue;
        }
        final converted = _convertJsonSubscriptionEntryToLinks(item.cast<String, dynamic>());
        if (converted.isEmpty) {
          skipped++;
        } else {
          links.addAll(converted);
        }
      }

      if (links.isEmpty) {
        await log('JSON array detected but no supported proxy links were generated; source=$source; items=${decoded.length}');
        return;
      }

      await file.writeAsString(links.join('\n'));
      await log('JSON array subscription converted to proxy links; source=$source; items=${decoded.length}; links=${links.length}; skipped=$skipped');
    } catch (err, st) {
      await log('JSON array subscription conversion failed; source=$source; error=$err; stack=$st');
    }
  }

  static List<String> _convertJsonSubscriptionEntryToLinks(Map<String, dynamic> entry) {
    final remarks = entry['remarks']?.toString().trim();
    final outbounds = entry['outbounds'];
    if (outbounds is! List) return const [];

    final proxyOutbounds = outbounds
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .where((outbound) {
          final protocol = outbound['protocol']?.toString().toLowerCase();
          return protocol == 'vless';
        })
        .toList();

    final links = <String>[];
    for (final outbound in proxyOutbounds) {
      final link = _convertVlessOutboundToUri(
        outbound,
        baseRemark: remarks,
        includeTagInRemark: proxyOutbounds.length > 1,
      );
      if (link != null) links.add(link);
    }
    return links;
  }

  static String? _convertVlessOutboundToUri(
    Map<String, dynamic> outbound, {
    required String? baseRemark,
    required bool includeTagInRemark,
  }) {
    final settings = outbound['settings'];
    if (settings is! Map) return null;
    final vnext = settings['vnext'];
    if (vnext is! List || vnext.isEmpty || vnext.first is! Map) return null;

    final server = (vnext.first as Map).cast<String, dynamic>();
    final users = server['users'];
    if (users is! List || users.isEmpty || users.first is! Map) return null;

    final user = (users.first as Map).cast<String, dynamic>();
    final id = user['id']?.toString();
    final address = server['address']?.toString();
    final port = server['port'];
    if (id == null || id.isEmpty || address == null || address.isEmpty || port == null) return null;

    final streamSettings = (outbound['streamSettings'] is Map)
        ? (outbound['streamSettings'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    final network = streamSettings['network']?.toString();
    final security = streamSettings['security']?.toString();
    final query = <String, String>{
      'encryption': user['encryption']?.toString() ?? 'none',
    };

    if (user['flow'] != null && user['flow'].toString().isNotEmpty) {
      query['flow'] = user['flow'].toString();
    }
    if (network != null && network.isNotEmpty) {
      query['type'] = network;
    }
    if (security != null && security.isNotEmpty) {
      query['security'] = security;
    }

    if (streamSettings['tlsSettings'] is Map) {
      final tls = (streamSettings['tlsSettings'] as Map).cast<String, dynamic>();
      if (tls['serverName'] != null && tls['serverName'].toString().isNotEmpty) {
        query['sni'] = tls['serverName'].toString();
      }
      if (tls['fingerprint'] != null && tls['fingerprint'].toString().isNotEmpty) {
        query['fp'] = tls['fingerprint'].toString();
      }
      if (tls['alpn'] is List && (tls['alpn'] as List).isNotEmpty) {
        query['alpn'] = (tls['alpn'] as List).map((e) => e.toString()).join(',');
      }
      if (tls['allowInsecure'] == true) {
        query['allowInsecure'] = '1';
      }
    }

    if (streamSettings['realitySettings'] is Map) {
      final reality = (streamSettings['realitySettings'] as Map).cast<String, dynamic>();
      if (reality['serverName'] != null && reality['serverName'].toString().isNotEmpty) {
        query['sni'] = reality['serverName'].toString();
      }
      if (reality['fingerprint'] != null && reality['fingerprint'].toString().isNotEmpty) {
        query['fp'] = reality['fingerprint'].toString();
      }
      if (reality['publicKey'] != null && reality['publicKey'].toString().isNotEmpty) {
        query['pbk'] = reality['publicKey'].toString();
      }
      if (reality['shortId'] != null && reality['shortId'].toString().isNotEmpty) {
        query['sid'] = reality['shortId'].toString();
      }
      if (reality['spiderX'] != null && reality['spiderX'].toString().isNotEmpty) {
        query['spx'] = reality['spiderX'].toString();
      }
    }

    final xhttpSettings = streamSettings['xhttpSettings'];
    if (xhttpSettings is Map) {
      final xhttp = xhttpSettings.cast<String, dynamic>();
      if (xhttp['host'] != null && xhttp['host'].toString().isNotEmpty) {
        query['host'] = xhttp['host'].toString();
      }
      if (xhttp['path'] != null && xhttp['path'].toString().isNotEmpty) {
        query['path'] = xhttp['path'].toString();
      }
      if (xhttp['mode'] != null && xhttp['mode'].toString().isNotEmpty) {
        query['mode'] = xhttp['mode'].toString();
      }
    }

    final tag = outbound['tag']?.toString();
    final remarkParts = <String>[
      if (baseRemark != null && baseRemark.isNotEmpty) baseRemark,
      if (includeTagInRemark && tag != null && tag.isNotEmpty) tag,
    ];
    final remark = remarkParts.isEmpty ? 'VLESS' : remarkParts.join(' ');

    return Uri(
      scheme: 'vless',
      userInfo: id,
      host: address,
      port: int.tryParse(port.toString()),
      queryParameters: query,
      fragment: remark,
    ).toString();
  }

  static Either<ProfileFailure, Map<String, dynamic>> populateHeaders({
    required String content,
    Map<String, dynamic>? remoteHeaders,
  }) => Either.tryCatch(() {
    final contentHeaders = _parseHeadersFromContent(content);
    return _mergeAndValidateHeaders(contentHeaders, remoteHeaders ?? {});
  }, ProfileFailure.unexpected);

  static Map<String, dynamic> _mergeAndValidateHeaders(
    Map<String, dynamic> contentHeaders,
    Map<String, dynamic> remoteHeaders,
  ) {
    for (final entry in contentHeaders.entries) {
      if (!remoteHeaders.keys.contains(entry.key)) {
        remoteHeaders[entry.key] = entry.value;
      }
    }
    final headers = <String, dynamic>{};
    for (final entry in remoteHeaders.entries) {
      if (allowedProfileHeaders.contains(entry.key) && entry.value != null && entry.value.toString().isNotEmpty) {
        headers[entry.key] = entry.value;
      }
    }
    return headers;
  }

  static Map<String, dynamic> _parseHeadersFromContent(String content) {
    final headers = <String, dynamic>{};
    final content_ = safeDecodeBase64(content);
    final lines = content_.split("\n");
    final linesToProcess = lines.length < 10 ? lines.length : 10;
    for (int i = 0; i < linesToProcess; i++) {
      final line = lines[i];
      if (line.startsWith("#") || line.startsWith("//")) {
        final index = line.indexOf(':');
        if (index == -1) continue;
        final key = line.substring(0, index).replaceFirst(RegExp("^#|//"), "").trim().toLowerCase();
        final value = line.substring(index + 1).trim();
        headers[key] = value;
      }
    }
    return headers;
  }

  static SubscriptionInfo? _parseSubscriptionInfo(String subInfoStr) {
    final values = subInfoStr.split(';');
    final map = {for (final v in values) v.split('=').first.trim(): num.tryParse(v.split('=').second.trim())?.toInt()};
    if (map case {"upload": final upload?, "download": final download?, "total": final total, "expire": var expire}) {
      final total1 = (total == null || total == 0) ? infiniteTrafficThreshold + 1 : total;
      expire = (expire == null || expire == 0) ? infiniteTimeThreshold : expire;
      return SubscriptionInfo(
        upload: upload,
        download: download,
        total: total1,
        expire: DateTime.fromMillisecondsSinceEpoch(expire * 1000),
      );
    }
    return null;
  }

  @visibleForTesting
  static Either<ProfileFailure, ProfileEntity> parse({required String tempFilePath, required ProfileEntity profile}) =>
      Either.tryCatch(() {
        final headers = Map<String, dynamic>.from(profile.populatedHeaders ?? {});
        var name = '';
        if (profile.userOverride?.name case final String oName when oName.isNotEmpty) {
          name = oName;
        }

        if (headers['profile-title'] case final String titleHeader when name.isEmpty) {
          if (titleHeader.startsWith("base64:")) {
            name = utf8.decode(base64.decode(titleHeader.replaceFirst("base64:", "")));
          } else {
            name = titleHeader.trim();
          }
        }
        if (headers['content-disposition'] case final String contentDispositionHeader when name.isEmpty) {
          final regExp = RegExp('filename="([^"]*)"');
          final match = regExp.firstMatch(contentDispositionHeader);
          if (match != null && match.groupCount >= 1) {
            name = match.group(1) ?? '';
          }
        }
        if (profile case RemoteProfileEntity(:final url)) {
          if (Uri.parse(url).fragment case final fragment when name.isEmpty) {
            name = fragment;
          }
          if (url.split("/").lastOrNull case final part? when name.isEmpty) {
            final pattern = RegExp(r"\.(json|yaml|yml|txt)[\s\S]*");
            name = part.replaceFirst(pattern, "");
          }
        }
        if (name.isBlank) {
          switch (profile) {
            case RemoteProfileEntity():
              name = "Remote Profile";

            case LocalProfileEntity():
              name = protocol(File(tempFilePath).readAsStringSync());
          }
        }

        if (headers['enable-warp'].toString() == 'true' || profile.userOverride?.enableWarp == true) {
          final value = {'enable': true, 'mode': 'warp_over_proxy'};
          headers['warp'] = value;
          headers['warp2'] = value;
        }

        if (headers['enable-fragment'].toString() == 'true' || profile.userOverride?.enableFragment == true) {
          headers['tls-tricks'] = {'enable-fragment': true};
        }

        final isAutoUpdateDisable = profile.userOverride?.isAutoUpdateDisable ?? false;
        ProfileOptions? options;
        if (profile.userOverride?.updateInterval case final int updateInterval
            when updateInterval > 0 && !isAutoUpdateDisable) {
          options = ProfileOptions(updateInterval: Duration(hours: updateInterval));
        }
        if (headers['profile-update-interval'] case final String updateIntervalStr
            when options == null && !isAutoUpdateDisable) {
          final updateInterval = Duration(hours: int.parse(updateIntervalStr));
          options = ProfileOptions(updateInterval: updateInterval);
        }

        SubscriptionInfo? subInfo;
        if (headers['subscription-userinfo'] case final String subInfoStr) {
          subInfo = _parseSubscriptionInfo(subInfoStr);
        }

        if (subInfo != null) {
          if (headers['profile-web-page-url'] case final String profileWebPageUrl when isUrl(profileWebPageUrl)) {
            subInfo = subInfo.copyWith(webPageUrl: profileWebPageUrl);
          }
          if (headers['support-url'] case final String profileSupportUrl when isUrl(profileSupportUrl)) {
            subInfo = subInfo.copyWith(supportUrl: profileSupportUrl);
          }
        }

        headers.removeWhere(
          (key, value) => !allowedOverrideConfigs.contains(key) || value == null || value.toString().isEmpty,
        );

        final profileOverrideStr = jsonEncode({for (final key in headers.keys) key: headers[key]});

        return profile.map(
          remote: (rp) => rp.copyWith(
            name: name,
            lastUpdate: DateTime.now(),
            options: options,
            subInfo: subInfo,
            profileOverride: profileOverrideStr,
          ),
          local: (lp) => lp.copyWith(name: name, lastUpdate: DateTime.now(), profileOverride: profileOverrideStr),
        );
      }, ProfileFailure.unexpected);

  static String protocol(String content) {
    if (content.contains("[Interface]")) {
      return ProxyType.wireguard.label;
    }
    final lines = content.split('\n');
    String? name;
    for (final line in lines) {
      final uri = Uri.tryParse(line);
      if (uri == null) continue;
      final fragment = uri.hasFragment ? Uri.decodeComponent(uri.fragment.split(" -> ")[0]) : null;
      name ??= switch (uri.scheme) {
        'ss' => fragment ?? ProxyType.shadowsocks.label,
        'ssconf' => fragment ?? ProxyType.shadowsocks.label,
        'vmess' => ProxyType.vmess.label,
        'vless' => fragment ?? ProxyType.vless.label,
        'trojan' => fragment ?? ProxyType.trojan.label,
        'tuic' => fragment ?? ProxyType.tuic.label,
        'hy2' || 'hysteria2' => fragment ?? ProxyType.hysteria2.label,
        'hy' || 'hysteria' => fragment ?? ProxyType.hysteria.label,
        'ssh' => fragment ?? ProxyType.ssh.label,
        'wg' => fragment ?? ProxyType.wireguard.label,
        'awg' => fragment ?? ProxyType.awg.label,
        'shadowtls' => fragment ?? ProxyType.shadowtls.label,
        'mieru' => fragment ?? ProxyType.mieru.label,
        'warp' => fragment ?? ProxyType.warp.label,
        _ => null,
      };
    }
    return name ?? ProxyType.unknown.label;
  }

  static Map<String, dynamic> applyProfileOverride(Map<String, dynamic> main, String? profileOverride) {
    if (profileOverride == null) return main;
    if (profileOverride.contains("{")) {
      final profileOverrideMap = jsonDecode(profileOverride) as Map<String, dynamic>;
      return _mergeJson(main, profileOverrideMap);
    } else {
      return main;
    }
  }

  static Map<String, dynamic> _mergeJson(Map<String, dynamic> main, Map<String, dynamic> override) {
    override.forEach((key, value) {
      if (main.containsKey(key)) {
        if (main[key] is Map<String, dynamic> && value is Map<String, dynamic>) {
          main[key] = _mergeJson(main[key] as Map<String, dynamic>, value);
        } else {
          main[key] = value;
        }
      } else {
        main[key] = value;
      }
    });
    return main;
  }
}
