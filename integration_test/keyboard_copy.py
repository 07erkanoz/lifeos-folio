# Real X11 keyboard events on the isolated test display: Ctrl+A, then Ctrl+C.
import ctypes, time
x=ctypes.CDLL('libX11.so.6'); t=ctypes.CDLL('libXtst.so.6')
x.XOpenDisplay.argtypes=[ctypes.c_char_p];x.XOpenDisplay.restype=ctypes.c_void_p
d=x.XOpenDisplay(None);assert d
x.XDefaultRootWindow.argtypes=[ctypes.c_void_p];x.XDefaultRootWindow.restype=ctypes.c_ulong
root=x.XDefaultRootWindow(d)
x.XQueryTree.argtypes=[ctypes.c_void_p,ctypes.c_ulong,ctypes.POINTER(ctypes.c_ulong),ctypes.POINTER(ctypes.c_ulong),ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)),ctypes.POINTER(ctypes.c_uint)]
x.XFetchName.argtypes=[ctypes.c_void_p,ctypes.c_ulong,ctypes.POINTER(ctypes.c_char_p)]
x.XFree.argtypes=[ctypes.c_void_p]
r=ctypes.c_ulong();p=ctypes.c_ulong();children=ctypes.POINTER(ctypes.c_ulong)();n=ctypes.c_uint()
x.XQueryTree(d,root,ctypes.byref(r),ctypes.byref(p),ctypes.byref(children),ctypes.byref(n))
window=None
for w in children[:n.value]:
 name=ctypes.c_char_p()
 if x.XFetchName(d,w,ctypes.byref(name)) and name.value:
  title=name.value.decode(errors='replace').lower()
  if 'evrak' in title or 'folio' in title:window=w
  x.XFree(name)
x.XFree(children)
assert window, 'Folio window not found'
x.XSetInputFocus.argtypes=[ctypes.c_void_p,ctypes.c_ulong,ctypes.c_int,ctypes.c_ulong]
x.XSetInputFocus(d,window,2,0)
x.XKeysymToKeycode.argtypes=[ctypes.c_void_p,ctypes.c_ulong];x.XKeysymToKeycode.restype=ctypes.c_uint
x.XFlush.argtypes=[ctypes.c_void_p]
t.XTestFakeKeyEvent.argtypes=[ctypes.c_void_p,ctypes.c_uint,ctypes.c_int,ctypes.c_ulong]
ctrl=x.XKeysymToKeycode(d,0xffe3)
x.XFlush(d);time.sleep(.1)
for letter in 'ac':
 key=x.XKeysymToKeycode(d,ord(letter))
 for code,pressed in [(ctrl,1),(key,1),(key,0),(ctrl,0)]:t.XTestFakeKeyEvent(d,code,pressed,10)
 x.XFlush(d)
 time.sleep(.4)
