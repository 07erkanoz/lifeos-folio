# Real X11 keyboard events on the isolated test display, not Dart key injection.
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
class Attributes(ctypes.Structure):
 _fields_=[('x',ctypes.c_int),('y',ctypes.c_int),('width',ctypes.c_int),('height',ctypes.c_int),('border_width',ctypes.c_int),('depth',ctypes.c_int),('visual',ctypes.c_void_p),('root',ctypes.c_ulong),('class_',ctypes.c_int),('bit_gravity',ctypes.c_int),('win_gravity',ctypes.c_int),('backing_store',ctypes.c_int),('backing_planes',ctypes.c_ulong),('backing_pixel',ctypes.c_ulong),('save_under',ctypes.c_int),('colormap',ctypes.c_ulong),('map_installed',ctypes.c_int),('map_state',ctypes.c_int),('all_event_masks',ctypes.c_long),('your_event_mask',ctypes.c_long),('do_not_propagate_mask',ctypes.c_long),('override_redirect',ctypes.c_int),('screen',ctypes.c_void_p)]
x.XGetWindowAttributes.argtypes=[ctypes.c_void_p,ctypes.c_ulong,ctypes.POINTER(Attributes)]
window=None
for w in children[:n.value]:
 name=ctypes.c_char_p()
 if x.XFetchName(d,w,ctypes.byref(name)) and name.value:
  title=name.value.decode(errors='replace').lower()
  if 'evrak' in title or 'folio' in title:
   attrs=Attributes()
   if x.XGetWindowAttributes(d,w,ctypes.byref(attrs)) and attrs.map_state==2:window=w
  x.XFree(name)
x.XFree(children)
assert window, 'Folio window not found'
x.XSetInputFocus.argtypes=[ctypes.c_void_p,ctypes.c_ulong,ctypes.c_int,ctypes.c_ulong]
x.XSetInputFocus(d,window,2,0)
x.XKeysymToKeycode.argtypes=[ctypes.c_void_p,ctypes.c_ulong];x.XKeysymToKeycode.restype=ctypes.c_uint
x.XFlush.argtypes=[ctypes.c_void_p]
t.XTestFakeKeyEvent.argtypes=[ctypes.c_void_p,ctypes.c_uint,ctypes.c_int,ctypes.c_ulong]
ctrl=x.XKeysymToKeycode(d,0xffe3);v=x.XKeysymToKeycode(d,ord('v'))
x.XFlush(d);time.sleep(.1)
for key,pressed in [(ctrl,1),(v,1),(v,0),(ctrl,0)]:t.XTestFakeKeyEvent(d,key,pressed,10)
x.XFlush(d)
time.sleep(.2)
