p='lib/app/router.dart'
s=open(p,encoding='utf-8').read()
s=s.replace("      parentNavigatorKey: _rootKey,\n","")
s=s.replace("""
/// Root navigator key so full-screen routes push above the shell.
final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>();
""","")
open(p,'w',encoding='utf-8').write(s)
print("router cleaned")
