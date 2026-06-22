import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:andreyvpn/core/db/db.dart';

import 'package:andreyvpn/core/utils/exception_handler.dart';
import 'package:andreyvpn/features/profile/data/profile_data_mapper.dart';
import 'package:andreyvpn/features/profile/data/profile_data_source.dart';
import 'package:andreyvpn/features/profile/data/profile_parser.dart';
import 'package:andreyvpn/features/profile/data/profile_path_resolver.dart';
import 'package:andreyvpn/features/profile/data/profile_server_exclusion_store.dart';
import 'package:andreyvpn/features/profile/model/profile_entity.dart';
import 'package:andreyvpn/features/profile/model/profile_failure.dart';
import 'package:andreyvpn/features/profile/model/profile_sort_enum.dart';
import 'package:andreyvpn/features/settings/data/config_option_repository.dart';
import 'package:andreyvpn/hiddifycore/hiddify_core_service.dart';
import 'package:andreyvpn/utils/custom_loggers.dart';
import 'package:uuid/uuid.dart';

abstract interface class ProfileRepository {
  TaskEither<ProfileFailure, Unit> init();
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id);
  TaskEither<ProfileFailure, Unit> setAsActive(String id);
  TaskEither<ProfileFailure, Unit> deleteById(String id, bool isActive);
  Stream<Either<ProfileFailure, ProfileEntity?>> watchActiveProfile();
  Stream<Either<ProfileFailure, bool>> watchHasAnyProfile();
  Stream<Either<ProfileFailure, List<ProfileEntity>>> watchAll({
    ProfilesSort sort = ProfilesSort.lastUpdate,
    SortMode sortMode = SortMode.ascending,
  });
  TaskEither<ProfileFailure, Unit> upsertRemote(String url, {UserOverride? userOverride, CancelToken? cancelToken});
  TaskEither<ProfileFailure, Unit> addLocal(String content, {UserOverride? userOverride});
  TaskEither<ProfileFailure, Unit> offlineUpdate(ProfileEntity nProfile, String nContent);
  TaskEither<ProfileFailure, Unit> validateConfig(String path, String tempPath, String? profileOverride, bool debug);
  TaskEither<ProfileFailure, String> generateConfig(String id);
  TaskEither<ProfileFailure, String> getRawConfig(String id);
  List<HiddenServer> getHiddenServers(String profileId);
  TaskEither<ProfileFailure, Unit> excludeServers(ProfileEntity profile, Iterable<HiddenServer> servers);
  TaskEither<ProfileFailure, Unit> restoreServers(RemoteProfileEntity profile, Set<String> serverTags);
}

class ProfileRepositoryImpl with ExceptionHandler, InfraLogger implements ProfileRepository {
  ProfileRepositoryImpl({
    required ProfileDataSource profileDataSource,
    required ProfilePathResolver profilePathResolver,
    required HiddifyCoreService singbox,
    required ConfigOptionRepository configOptionRepository,
    required ProfileParser profileParser,
    required ProfileServerExclusionStore serverExclusionStore,
  }) : _profileParser = profileParser,
       _configOptionRepo = configOptionRepository,
       _singbox = singbox,
       _profilePathResolver = profilePathResolver,
       _serverExclusionStore = serverExclusionStore,
       _profileDataSource = profileDataSource;

  final ProfileDataSource _profileDataSource;
  final ProfilePathResolver _profilePathResolver;
  final HiddifyCoreService _singbox;
  final ConfigOptionRepository _configOptionRepo;
  final ProfileParser _profileParser;
  final ProfileServerExclusionStore _serverExclusionStore;

  @override
  TaskEither<ProfileFailure, Unit> init() {
    return exceptionHandler(() async {
      if (!kIsWeb) {
        if (!await _profilePathResolver.directory.exists()) {
          await _profilePathResolver.directory.create(recursive: true);
        }
      }

      return right(unit);
    }, ProfileUnexpectedFailure.new);
  }

  @override
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id) {
    return TaskEither.tryCatch(
      () => _profileDataSource.getById(id).then((value) => value?.toEntity()),
      ProfileUnexpectedFailure.new,
    );
  }

  @override
  TaskEither<ProfileFailure, Unit> setAsActive(String id) {
    return TaskEither.tryCatch(() async {
      await _profileDataSource.edit(id, const ProfileEntriesCompanion(active: Value(true)));
      return unit;
    }, ProfileUnexpectedFailure.new);
  }

  @override
  TaskEither<ProfileFailure, Unit> deleteById(String id, bool isActive) {
    return TaskEither.tryCatch(() async {
      await _profileDataSource.deleteById(id, isActive);
      await _profilePathResolver.file(id).delete();
      await _serverExclusionStore.clear(id);
      return unit;
    }, ProfileUnexpectedFailure.new);
  }

  @override
  Stream<Either<ProfileFailure, ProfileEntity?>> watchActiveProfile() {
    return _profileDataSource.watchActiveProfile().map((event) => event?.toEntity()).handleExceptions((
      error,
      stackTrace,
    ) {
      loggy.error("error watching active profile", error, stackTrace);
      return ProfileUnexpectedFailure(error, stackTrace);
    });
  }

  @override
  Stream<Either<ProfileFailure, bool>> watchHasAnyProfile() {
    return _profileDataSource
        .watchProfilesCount()
        .map((event) => event != 0)
        .handleExceptions(ProfileUnexpectedFailure.new);
  }

  @override
  Stream<Either<ProfileFailure, List<ProfileEntity>>> watchAll({
    ProfilesSort sort = ProfilesSort.lastUpdate,
    SortMode sortMode = SortMode.ascending,
  }) {
    return _profileDataSource
        .watchAll(sort: sort, sortMode: sortMode)
        .map((event) => event.map((e) => e.toEntity()).toList())
        .handleExceptions(ProfileUnexpectedFailure.new);
  }

  @override
  TaskEither<ProfileFailure, Unit> upsertRemote(String url, {UserOverride? userOverride, CancelToken? cancelToken}) =>
      TaskEither.tryCatch(
        () async => await _profileDataSource.getByUrl(url).then((profEntry) => profEntry?.toEntity()),
        ProfileFailure.unexpected,
      ).flatMap((profEntity) {
        // if profile is null, generate id
        final id = profEntity?.id ?? const Uuid().v4();
        final file = _profilePathResolver.file(id);
        final tempFile = _profilePathResolver.tempFile(id);
        try {
          if (profEntity != null && profEntity is RemoteProfileEntity) {
            // Update
            if (userOverride != null) {
              profEntity = profEntity.copyWith(userOverride: userOverride);
            }
            return _profileParser
                .updateRemote(rp: profEntity, tempFilePath: tempFile.path, cancelToken: cancelToken)
                .flatMap(
                  (profEntity) =>
                      validateConfig(file.path, tempFile.path, profEntity.profileOverride.value, false)
                          .flatMap((_) => _applyStoredServerExclusions(id, profEntity.profileOverride.value))
                          .flatMap(
                            (unit) => TaskEither.tryCatch(() async {
                              await _profileDataSource.edit(id, profEntity);
                              return unit;
                            }, ProfileFailure.unexpected),
                          ),
                );
          } else {
            // Add
            return _profileParser
                .addRemote(
                  id: id,
                  url: url,
                  tempFilePath: tempFile.path,
                  userOverride: userOverride,
                  cancelToken: cancelToken,
                )
                .flatMap(
                  (profEntity) =>
                      validateConfig(file.path, tempFile.path, profEntity.profileOverride.value, false)
                          .flatMap((_) => _applyStoredServerExclusions(id, profEntity.profileOverride.value))
                          .flatMap(
                            (unit) => TaskEither.tryCatch(() async {
                              await _profileDataSource.insert(profEntity);
                              return unit;
                            }, ProfileFailure.unexpected),
                          ),
                );
          }
        } finally {
          if (tempFile.existsSync()) tempFile.deleteSync();
        }
      });

  @override
  TaskEither<ProfileFailure, Unit> addLocal(String content, {UserOverride? userOverride}) =>
      TaskEither.tryCatch(() async {
        final id = const Uuid().v4();
        final file = _profilePathResolver.file(id);
        final tempFile = _profilePathResolver.tempFile(id);
        try {
          await tempFile.writeAsString(content);
          final task = _profileParser
              .addLocal(id: id, content: content, tempFilePath: tempFile.path, userOverride: userOverride)
              .flatMap(
                (profEntity) =>
                    validateConfig(file.path, tempFile.path, profEntity.profileOverride.value, false).flatMap(
                      (unit) => TaskEither.tryCatch(() async {
                        await _profileDataSource.insert(profEntity);
                        return unit;
                      }, ProfileFailure.unexpected),
                    ),
              );
          return (await task.run()).getOrElse((l) => throw l);
        } finally {
          if (tempFile.existsSync()) tempFile.deleteSync();
        }
      }, ProfileFailure.unexpected);

  @override
  TaskEither<ProfileFailure, Unit> offlineUpdate(ProfileEntity profile, String nContent) =>
      TaskEither.tryCatch(
        () async => await _profileDataSource.getById(profile.id).then((profEntry) => profEntry?.toEntity()),
        ProfileFailure.unexpected,
      ).flatMap((oProfile) {
        if (oProfile == null || oProfile.runtimeType != profile.runtimeType) throw const ProfileFailure.notFound();
        if (profile.userOverride == null) loggy.warning('Updaing profile content with "userOverride" == null');
        final id = oProfile.id;
        final file = _profilePathResolver.file(id);
        final tempFile = _profilePathResolver.tempFile(id);
        try {
          return TaskEither.tryCatch(
            () async => await tempFile.writeAsString(nContent),
            ProfileFailure.unexpected,
          ).flatMap(
            (_) =>
                TaskEither.fromEither(
                  _profileParser.offlineUpdate(
                    profile: oProfile.copyWith(userOverride: profile.userOverride),
                    tempFilePath: tempFile.path,
                  ),
                ).flatMap(
                  (profEntity) =>
                      validateConfig(file.path, tempFile.path, profEntity.profileOverride.value, false).flatMap(
                        (unit) => TaskEither.tryCatch(() async {
                          await _profileDataSource.edit(id, profEntity);
                          return unit;
                        }, ProfileFailure.unexpected),
                      ),
                ),
          );
        } finally {
          if (tempFile.existsSync()) tempFile.deleteSync();
        }
      });

  @override
  TaskEither<ProfileFailure, Unit> validateConfig(String path, String tempPath, String? profileOverride, bool debug) =>
      TaskEither.fromEither(_configOptionRepo.fullOptionsOverrided(profileOverride))
          .mapLeft((configOptionFailure) => ProfileFailure.invalidConfig(null, configOptionFailure))
          .flatMap(
            (overridedOptions) => _singbox
                .changeOptions(overridedOptions)
                .mapLeft(ProfileFailure.invalidConfig)
                .flatMap(
                  (_) => _singbox.validateConfigByPath(path, tempPath, debug).mapLeft(ProfileFailure.invalidConfig),
                ),
          );

  @override
  TaskEither<ProfileFailure, String> generateConfig(String id) => TaskEither.fromEither(
    Either.tryCatch(() => _profilePathResolver.file(id), ProfileFailure.unexpected),
  ).flatMap((configFile) => _singbox.generateFullConfigByPath(configFile.path).mapLeft(ProfileFailure.unexpected));

  @override
  TaskEither<ProfileFailure, String> getRawConfig(String id) {
    return TaskEither.fromEither(
      Either.tryCatch(() => _profilePathResolver.file(id), ProfileFailure.unexpected),
    ).flatMap((configFile) => TaskEither.tryCatch(() => configFile.readAsString(), ProfileFailure.unexpected));
  }

  @override
  List<HiddenServer> getHiddenServers(String profileId) => _serverExclusionStore.read(profileId);

  @override
  TaskEither<ProfileFailure, Unit> excludeServers(ProfileEntity profile, Iterable<HiddenServer> servers) {
    final newServers = servers.toList();
    if (newServers.isEmpty) return TaskEither.of(unit);

    final exclusions = {
      for (final server in _serverExclusionStore.read(profile.id)) server.tag: server,
      for (final server in newServers) server.tag: server,
    };
    return _rewriteValidatedConfig(
      profile.id,
      profile.profileOverride,
      exclusions.keys.toSet(),
      requireRemoval: true,
    ).flatMap(
      (_) => TaskEither.tryCatch(() async {
        await _serverExclusionStore.write(profile.id, exclusions.values);
        return unit;
      }, ProfileFailure.unexpected),
    );
  }

  @override
  TaskEither<ProfileFailure, Unit> restoreServers(RemoteProfileEntity profile, Set<String> serverTags) {
    if (serverTags.isEmpty) return TaskEither.of(unit);
    return TaskEither.tryCatch(() async {
      final previous = _serverExclusionStore.read(profile.id);
      final remaining = previous.where((server) => !serverTags.contains(server.tag)).toList();
      if (remaining.length == previous.length) return unit;

      await _serverExclusionStore.write(profile.id, remaining);
      final updateResult = await upsertRemote(profile.url).run();
      return await updateResult.match(
        (failure) async {
          await _serverExclusionStore.write(profile.id, previous);
          throw failure;
        },
        (_) async => unit,
      );
    }, (error, stackTrace) => error is ProfileFailure ? error : ProfileFailure.unexpected(error, stackTrace));
  }

  TaskEither<ProfileFailure, Unit> _applyStoredServerExclusions(String profileId, String? profileOverride) {
    final exclusions = _serverExclusionStore.read(profileId).map((server) => server.tag).toSet();
    if (exclusions.isEmpty) return TaskEither.of(unit);
    return _rewriteValidatedConfig(profileId, profileOverride, exclusions);
  }

  TaskEither<ProfileFailure, Unit> _rewriteValidatedConfig(
    String profileId,
    String? profileOverride,
    Set<String> exclusions, {
    bool requireRemoval = false,
  }) {
    return TaskEither.tryCatch(() async {
      final file = _profilePathResolver.file(profileId);
      final result = ProfileServerConfigEditor.removeServers(await file.readAsString(), exclusions);
      if (requireRemoval && result.removedTags.isEmpty) {
        throw StateError('Selected servers were not found in the saved subscription config');
      }
      if (result.removedTags.isEmpty) return unit;

      final tempFile = _profilePathResolver.tempFile('$profileId.exclusions');
      try {
        await tempFile.writeAsString(result.content, flush: true);
        return (await validateConfig(file.path, tempFile.path, profileOverride, false).run()).match(
          (failure) => throw failure,
          (_) => unit,
        );
      } finally {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    }, (error, stackTrace) => error is ProfileFailure ? error : ProfileFailure.unexpected(error, stackTrace));
  }
}
