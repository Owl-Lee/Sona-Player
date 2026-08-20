import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CloudConfig {
  const CloudConfig({required this.url, required this.publishableKey});

  factory CloudConfig.fromEnvironment() {
    return const CloudConfig(
      url: String.fromEnvironment(
        'SONA_SUPABASE_URL',
        defaultValue: 'https://mtikxsgwhzommksflewe.supabase.co',
      ),
      // Supabase 的 publishable key 本来就是给客户端使用的公开标识；
      // service-role key 与数据库密码绝不能放进应用。
      publishableKey: String.fromEnvironment(
        'SONA_SUPABASE_PUBLISHABLE_KEY',
        defaultValue: 'sb_publishable_Rp1Cm1gUk3cRLZZVCMcLkg_jhRHnHAc',
      ),
    );
  }

  final String url;
  final String publishableKey;

  bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}

final cloudClientProvider = Provider<SupabaseClient?>((ref) => null);
