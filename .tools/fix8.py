import re, shutil, os

# Move repository interfaces to a proper domain file and update the providers import.
src='lib/features/chats/domain/repositories.dart'
shutil.make_archive('.tools/repositories_backup','zip','lib/features/chats/domain')

p='lib/features/chats/presentation/providers.dart'
s=open(p,encoding='utf-8').read()

# 1) fix the import of repositories.dart
s=s.replace("import 'repositories.dart';", "import '../domain/repositories.dart';")

# 2) rename every `update(` override on AsyncNotifier subclasses -> `apply(`
#    (AsyncNotifier already declares update(); overriding with a different
#     signature is invalid.)
s=s.replace("  Future<void> update(AppearanceSettings Function(AppearanceSettings) change) async {",
            "  Future<void> apply(AppearanceSettings Function(AppearanceSettings) change) async {")
s=s.replace("  Future<void> update(NotificationSettings Function(NotificationSettings) change) async {",
            "  Future<void> apply(NotificationSettings Function(NotificationSettings) change) async {")
s=s.replace("  Future<void> update(PrivacySettings Function(PrivacySettings) change) async {",
            "  Future<void> apply(PrivacySettings Function(PrivacySettings) change) async {")
s=s.replace("  Future<void> update(ChatSettings Function(ChatSettings) change) async {",
            "  Future<void> apply(ChatSettings Function(ChatSettings) change) async {")
s=s.replace("  Future<void> update(Contact contact) async {",
            "  Future<void> persist(Contact contact) async {")

# fix internal callers
s=s.replace("  Future<void> setThemeMode(AppThemeMode mode) =>\n      update((AppearanceSettings s) => s.copyWith(themeMode: mode));",
            "  Future<void> setThemeMode(AppThemeMode mode) =>\n      apply((AppearanceSettings s) => s.copyWith(themeMode: mode));")
s=s.replace("  Future<void> setAccent(int color) =>\n      update((AppearanceSettings s) => s.copyWith(accentColor: color));",
            "  Future<void> setAccent(int color) =>\n      apply((AppearanceSettings s) => s.copyWith(accentColor: color));")
s=s.replace("  Future<void> setFontScale(double scale) =>\n      update((AppearanceSettings s) => s.copyWith(fontScale: scale));",
            "  Future<void> setFontScale(double scale) =>\n      apply((AppearanceSettings s) => s.copyWith(fontScale: scale));")
s=s.replace("  Future<void> setChatTheme(String theme) =>\n      update((AppearanceSettings s) => s.copyWith(chatTheme: theme));",
            "  Future<void> setChatTheme(String theme) =>\n      apply((AppearanceSettings s) => s.copyWith(chatTheme: theme));")
s=s.replace("  Future<void> setAppIcon(String icon) =>\n      update((AppearanceSettings s) => s.copyWith(appIcon: icon));",
            "  Future<void> setAppIcon(String icon) =>\n      apply((AppearanceSettings s) => s.copyWith(appIcon: icon));")

# 3) remaining Provider.family annotation
s=s.replace("final Provider.family<AsyncValue<Contact?>, String> contactByIdProvider =\n    Provider.family<AsyncValue<Contact?>, String>(",
            "final contactByIdProvider = Provider.family<AsyncValue<Contact?>, String>(")

open(p,'w',encoding='utf-8').write(s)
print("patched providers")
