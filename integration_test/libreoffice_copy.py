# Copy a synthetic styled Writer selection through LibreOffice's real clipboard.
import uno, subprocess, pathlib, tempfile, time, signal
profile=tempfile.TemporaryDirectory(prefix='folio-writer-')
pipe='folio_clipboard_'+str(__import__('os').getpid())
proc=subprocess.Popen(['libreoffice','-env:UserInstallation='+pathlib.Path(profile.name).as_uri(),
 '--accept=pipe,name='+pipe+';urp;StarOffice.ComponentContext','--norestore','--nodefault','--nolockcheck'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(SystemExit(0)))
local=uno.getComponentContext();resolver=local.ServiceManager.createInstanceWithContext('com.sun.star.bridge.UnoUrlResolver',local)
try:
 for _ in range(100):
  try:ctx=resolver.resolve('uno:pipe,name='+pipe+';urp;StarOffice.ComponentContext');break
  except Exception:time.sleep(.1)
 desktop=ctx.ServiceManager.createInstanceWithContext('com.sun.star.frame.Desktop',ctx)
 doc=desktop.loadComponentFromURL('private:factory/swriter','_blank',0,())
 text=doc.Text;c=text.createTextCursor()
 c.CharFontName='Arial';c.CharHeight=18;c.CharWeight=150;c.CharColor=0xc00000
 c.ParaAdjust=3
 text.insertString(c,'Bold heading',False)
 text.insertControlCharacter(c,0,False)
 c.CharWeight=100;c.CharFontName='Times New Roman';c.CharHeight=12;c.ParaAdjust=0
 text.insertString(c,'plain body',False)
 cursor=doc.CurrentController.ViewCursor;cursor.gotoStart(False);cursor.gotoEnd(True)
 dispatcher=ctx.ServiceManager.createInstanceWithContext('com.sun.star.frame.DispatchHelper',ctx)
 dispatcher.executeDispatch(doc.CurrentController.Frame,'.uno:Copy','',0,())
 print('READY',flush=True)
 for _ in range(1200):time.sleep(.1)
finally:
 try:doc.close(True);desktop.terminate()
 except Exception:pass
 proc.terminate();profile.cleanup()
