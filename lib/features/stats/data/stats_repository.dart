import 'package:fpdart/fpdart.dart';
import 'package:andreyvpn/core/utils/exception_handler.dart';
import 'package:andreyvpn/features/stats/model/stats_failure.dart';
import 'package:andreyvpn/andreyvpncore/generated/v2/hcore/hcore.pb.dart';
import 'package:andreyvpn/andreyvpncore/andreyvpn_core_service.dart';
import 'package:andreyvpn/utils/custom_loggers.dart';

abstract interface class StatsRepository {
  Stream<Either<StatsFailure, SystemInfo>> watchStats();
}

class StatsRepositoryImpl with ExceptionHandler, InfraLogger implements StatsRepository {
  StatsRepositoryImpl({required this.singbox});

  final AndreyVPNCoreService singbox;

  @override
  Stream<Either<StatsFailure, SystemInfo>> watchStats() {
    return singbox.watchStats().handleExceptions(StatsUnexpectedFailure.new);
  }
}
