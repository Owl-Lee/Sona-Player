import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/cloud/cloud_config.dart';

class AccountState {
  const AccountState({
    required this.configured,
    this.user,
    this.loading = false,
    this.message = '',
    this.error = '',
    this.displayName = '',
    this.username = '',
    this.avatarUrl,
  });

  final bool configured;
  final User? user;
  final bool loading;
  final String message;
  final String error;
  final String displayName;
  final String username;
  final String? avatarUrl;

  AccountState copyWith({
    User? user,
    bool clearUser = false,
    bool? loading,
    String? message,
    String? error,
    String? displayName,
    String? username,
    String? avatarUrl,
    bool clearAvatar = false,
  }) {
    return AccountState(
      configured: configured,
      user: clearUser ? null : (user ?? this.user),
      loading: loading ?? this.loading,
      message: message ?? this.message,
      error: error ?? this.error,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      avatarUrl: clearAvatar ? null : avatarUrl ?? this.avatarUrl,
    );
  }
}

final accountControllerProvider =
    StateNotifierProvider<AccountController, AccountState>((ref) {
      final controller = AccountController(ref.read(cloudClientProvider));
      ref.onDispose(controller.dispose);
      return controller;
    });

class AccountController extends StateNotifier<AccountState> {
  AccountController(this._client)
    : super(
        AccountState(
          configured: _client != null,
          user: _client?.auth.currentUser,
          username: _client?.auth.currentUser == null
              ? ''
              : _visibleUsername(_client!.auth.currentUser!),
          displayName: _metadataDisplayName(_client?.auth.currentUser),
        ),
      ) {
    if (state.user != null) unawaited(_loadProfile());
    _authSubscription = _client?.auth.onAuthStateChange.listen((event) {
      final user = event.session?.user;
      if (user == null) {
        state = state.copyWith(
          clearUser: true,
          loading: false,
          error: '',
          displayName: '',
          username: '',
          clearAvatar: true,
        );
        return;
      }

      // Authentication and profile loading are deliberately independent.
      // A temporary profile/storage failure must never turn a valid session
      // into a visible login failure.
      state = state.copyWith(
        user: user,
        loading: false,
        error: '',
        username: _visibleUsername(user),
        displayName: _metadataDisplayName(user),
      );
      unawaited(_loadProfile());
    });
  }

  final SupabaseClient? _client;
  StreamSubscription<AuthState>? _authSubscription;

  Future<bool> signIn({required String identifier, required String password}) {
    return _run(() async {
      final username = _normalizeUsername(identifier);
      if (!_isValidUsername(username)) {
        throw StateError('请输入有效账号名。');
      }
      final client = _client!;
      final response = await client.auth.signInWithPassword(
        email: _usernameToInternalEmail(username),
        password: password,
      );
      final user = response.user;
      if (user == null) throw StateError('登录没有完成，请重试。');
      state = state.copyWith(
        user: user,
        username: username,
        displayName: _metadataDisplayName(user),
        error: '',
        message: '登录成功，正在检查云端数据。',
      );
      unawaited(_loadProfile());
    });
  }

  Future<bool> signUp({
    required String username,
    required String password,
    required String displayName,
  }) {
    return _run(() async {
      final normalizedUsername = _normalizeUsername(username);
      if (!_isValidUsername(normalizedUsername)) {
        throw StateError('账号名格式不正确。');
      }
      final client = _client!;
      final response = await client.auth.signUp(
        email: _usernameToInternalEmail(normalizedUsername),
        password: password,
        data: {
          'display_name': displayName.trim(),
          'username': normalizedUsername,
        },
      );
      final user = response.user;
      if (user == null || response.session == null) {
        throw StateError('账号创建没有完成，请确认云端已关闭邮箱验证后重试。');
      }
      state = state.copyWith(
        user: user,
        username: normalizedUsername,
        displayName: displayName.trim(),
        error: '',
        message: '账号创建成功，已经登录。',
      );
      // Authentication is already complete here. A delayed/mismatched profile
      // schema must not make a successfully-created account look like a
      // failed registration.
      try {
        await _saveProfile(client, user, displayName: displayName.trim());
      } catch (_) {
        // Auth metadata is the fallback until the profile row is repaired by
        // a later profile update or sync.
      }
    });
  }

  Future<void> signOut() async {
    final client = _client;
    if (client == null) return;
    state = state.copyWith(loading: true, error: '', message: '');
    try {
      await client.auth.signOut();
      state = state.copyWith(
        clearUser: true,
        loading: false,
        displayName: '',
        username: '',
        clearAvatar: true,
        message: '已退出云账号，本地音乐不会受到影响。',
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: _friendlyError(error));
    }
  }

  Future<void> updateDisplayName(String value) async {
    final client = _client;
    final user = client?.auth.currentUser;
    final name = value.trim();
    if (client == null || user == null || name.isEmpty) return;
    state = state.copyWith(loading: true, error: '', message: '');
    try {
      await client.auth.updateUser(
        UserAttributes(
          data: {
            ...(user.userMetadata ?? <String, dynamic>{}),
            'display_name': name,
            'username': _visibleUsername(user),
          },
        ),
      );
      try {
        await _saveProfile(client, user, displayName: name);
      } catch (_) {
        // The name is already stored in Auth metadata. Keep the account usable
        // if the optional public profile mirror is temporarily unavailable.
      }
      state = state.copyWith(
        displayName: name,
        loading: false,
        message: '显示名称已同步。',
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: _friendlyError(error));
    }
  }

  Future<void> uploadAvatar(Uint8List imageBytes) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    state = state.copyWith(loading: true, error: '', message: '正在上传头像…');
    try {
      String? oldPath = _metadataAvatarPath(user);
      try {
        final oldProfile = await client
            .from('profiles')
            .select('avatar_path')
            .eq('id', user.id)
            .maybeSingle();
        oldPath = oldProfile?['avatar_path'] as String? ?? oldPath;
      } catch (_) {
        // Auth metadata remains a valid fallback if profiles is unavailable.
      }
      final objectPath =
          '${user.id}/avatar_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await client.storage
          .from('sona-avatars')
          .uploadBinary(
            objectPath,
            imageBytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
      await client.auth.updateUser(
        UserAttributes(
          data: {
            ...(user.userMetadata ?? <String, dynamic>{}),
            'username': _visibleUsername(user),
            'display_name': state.displayName,
            'avatar_path': objectPath,
          },
        ),
      );
      Map<String, dynamic>? profile;
      try {
        profile = await _saveProfile(client, user, avatarPath: objectPath);
      } catch (_) {
        // The avatar path is also in Auth metadata, so profile mirroring is
        // helpful but not required for the avatar to survive another login.
      }
      final avatarUrl = await _signedAvatarUrl(client, objectPath);
      if (avatarUrl == null) {
        throw const StorageException('Could not create avatar URL');
      }
      if (oldPath != null && oldPath.isNotEmpty && oldPath != objectPath) {
        unawaited(client.storage.from('sona-avatars').remove([oldPath]));
      }
      state = state.copyWith(
        loading: false,
        displayName: profile?['display_name'] as String? ?? state.displayName,
        username: _visibleUsername(user),
        avatarUrl: avatarUrl,
        error: '',
        message: '头像更新成功，登录其他设备后会自动恢复。',
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: _friendlyError(error));
    }
  }

  Future<void> _loadProfile() async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    Map<String, dynamic>? profile;
    try {
      final result = await client
          .from('profiles')
          .select('display_name,avatar_path')
          .eq('id', user.id)
          .maybeSingle();
      if (result != null) profile = Map<String, dynamic>.from(result);
      if (result == null) {
        unawaited(
          _saveProfile(
            client,
            user,
            displayName: _metadataDisplayName(user),
          ).catchError((_) => <String, dynamic>{}),
        );
      }
    } catch (_) {
      // A profile failure is non-fatal. Auth metadata still identifies the
      // account and stores the last successful avatar path.
    }

    final avatarPath =
        profile?['avatar_path'] as String? ?? _metadataAvatarPath(user);
    final avatarUrl = await _signedAvatarUrl(client, avatarPath);
    state = state.copyWith(
      displayName:
          profile?['display_name'] as String? ?? _metadataDisplayName(user),
      username: _visibleUsername(user),
      avatarUrl: avatarUrl,
      clearAvatar: avatarUrl == null,
    );
  }

  Future<Map<String, dynamic>> _saveProfile(
    SupabaseClient client,
    User user, {
    String? displayName,
    String? avatarPath,
  }) async {
    final result = await client
        .from('profiles')
        .upsert({
          'id': user.id,
          'display_name': displayName ?? state.displayName,
          'avatar_path': ?avatarPath,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'id')
        .select('display_name,avatar_path')
        .single();
    return Map<String, dynamic>.from(result);
  }

  Future<bool> _run(Future<void> Function() operation) async {
    if (_client == null) {
      state = state.copyWith(error: '云端尚未配置。');
      return false;
    }
    state = state.copyWith(loading: true, error: '', message: '');
    try {
      await operation();
      state = state.copyWith(loading: false);
      return true;
    } catch (error) {
      state = state.copyWith(loading: false, error: _friendlyError(error));
      return false;
    }
  }

  String _friendlyError(Object error) {
    if (error is AuthException) {
      final code = error.code ?? '';
      final message = error.message.toLowerCase();
      if (code == 'email_provider_disabled' ||
          message.contains('email signups are disabled')) {
        return '云端注册入口尚未开启，请稍后重试。';
      }
      if (code == 'invalid_credentials') {
        return '账号名或密码不正确。';
      }
      if (code == 'user_already_exists' || code == 'email_exists') {
        return '这个账号名已被使用，请换一个账号名。';
      }
      return '账号服务暂时无法完成操作，请稍后重试。';
    }
    if (error is StorageException) {
      return '头像暂时无法保存到云端，请稍后重试。';
    }
    if (error is PostgrestException) {
      return '云端资料暂时无法更新，账号仍保持登录，请稍后重试。';
    }
    if (error is StateError) return error.message;
    return '操作没有完成，请稍后重试。';
  }

  static bool _isValidUsername(String value) =>
      RegExp(r'^[a-z][a-z0-9_]{2,23}$').hasMatch(value);

  static String _normalizeUsername(String value) => value.trim().toLowerCase();

  static String _visibleUsername(User user) {
    final metadataUsername = user.userMetadata?['username']?.toString().trim();
    if (metadataUsername != null && metadataUsername.isNotEmpty) {
      return metadataUsername;
    }
    final email = user.email ?? '';
    const internalSuffix = '@accounts.sona.local';
    if (email.endsWith(internalSuffix)) {
      return email.substring(0, email.length - internalSuffix.length);
    }
    return 'Sona 用户';
  }

  static String _metadataDisplayName(User? user) =>
      user?.userMetadata?['display_name']?.toString().trim() ?? '';

  static String? _metadataAvatarPath(User? user) {
    final value = user?.userMetadata?['avatar_path']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<String?> _signedAvatarUrl(
    SupabaseClient client,
    String? objectPath,
  ) async {
    if (objectPath == null || objectPath.isEmpty) return null;
    try {
      return await client.storage
          .from('sona-avatars')
          .createSignedUrl(objectPath, 60 * 60 * 24 * 7);
    } catch (_) {
      return null;
    }
  }

  // Supabase password auth requires an email-like identity. During Sona's
  // username-only phase this private, non-delivery address is only an auth
  // implementation detail and is never shown in the interface.
  static String _usernameToInternalEmail(String username) =>
      '$username@accounts.sona.local';

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }
}
