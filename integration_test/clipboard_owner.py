# Own only the isolated integration-test display's clipboard.
import pathlib, sys, gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk
payload = pathlib.Path(sys.argv[1]).read_bytes()
mime = sys.argv[2]
# PyGObject does not expose gtk_clipboard_set_with_data on all versions.
import ctypes
lib = ctypes.CDLL('libgtk-3.so.0')
gdk = ctypes.CDLL('libgdk-3.so.0')
gdk.gdk_atom_intern.argtypes = [ctypes.c_char_p,ctypes.c_int]
gdk.gdk_atom_intern.restype = ctypes.c_void_p
lib.gtk_clipboard_get.argtypes=[ctypes.c_void_p]
lib.gtk_clipboard_get.restype=ctypes.c_void_p
class Target(ctypes.Structure):
 _fields_=[('target',ctypes.c_char_p),('flags',ctypes.c_uint),('info',ctypes.c_uint)]
CB=ctypes.CFUNCTYPE(None,ctypes.c_void_p,ctypes.c_void_p,ctypes.c_uint,ctypes.c_void_p)
lib.gtk_selection_data_set.argtypes=[ctypes.c_void_p,ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p,ctypes.c_int]
@CB
def supply(clipboard, data, info, user):
 blob=payload if info==0 else b'Bold heading plain body'
 atom=gdk.gdk_atom_intern((mime if info==0 else 'UTF8_STRING').encode(),0)
 lib.gtk_selection_data_set(data,atom,8,ctypes.c_char_p(blob),len(blob))
lib.gtk_clipboard_set_with_data.argtypes=[ctypes.c_void_p,ctypes.POINTER(Target),ctypes.c_uint,CB,ctypes.c_void_p,ctypes.c_void_p]
clipboard=lib.gtk_clipboard_get(gdk.gdk_atom_intern(b'CLIPBOARD',0))
targets=(Target*2)(Target(mime.encode(),0,0),Target(b'UTF8_STRING',0,1))
assert lib.gtk_clipboard_set_with_data(clipboard,targets,2,supply,None,None)
print('READY',flush=True)
Gtk.main()
