// lib/providers/platform_providers.dart
//
// 平台实现注入点。当前仅 Android,直接返回移动端实现。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/platform/keep_alive_service.dart';
import '../services/platform/permission_service.dart';
import '../services/platform/update_applier.dart';
import '../services/platform/impl/keep_alive_mobile.dart';
import '../services/platform/impl/permission_mobile.dart';
import '../services/platform/impl/update_mobile.dart';

final keepAliveProvider = Provider<KeepAliveService>(
    (ref) => MobileKeepAlive());

final permissionProvider = Provider<PermissionService>(
    (ref) => MobilePermission());

final updateApplierProvider = Provider<UpdateApplier>(
    (ref) => MobileUpdateApplier());
