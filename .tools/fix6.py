for p in ['lib/core/services/connectivity_service.dart','lib/core/services/media_service.dart','lib/core/services/file_service.dart']:
    s=open(p,encoding='utf-8').read()
    s=s.replace("      if (!await file.exists()) return 0;\n      return file.length();","      if (!await file.exists()) return 0;\n      return await file.length();")
    open(p,'w',encoding='utf-8').write(s)
print("ok")
