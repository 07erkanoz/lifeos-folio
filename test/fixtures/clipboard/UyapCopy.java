import java.awt.*;
import java.awt.datatransfer.*;
import java.io.*;
import java.util.*;
import javax.swing.*;
import javax.swing.text.*;

/**
 * Opens a UDF in UYAP's own editor, selects all of it (or the range given as
 * "start:end"), copies it to the system clipboard as UYAP's Ctrl+C does, and
 * keeps owning the clipboard until the file named last appears, so that
 * xclip can read what UYAP put there. Run it through capture_uyap.sh.
 */
public class UyapCopy {
  public static void main(String[] args) throws Exception {
    final String udf = args[0];
    final String ready = args[1];
    final String done = args[2];
    final String mode = args.length > 3 ? args[3] : "all";
    Thread t = new Thread(() -> {
      try {
        Class.forName("tr.com.havelsan.uyap.system.editor.common.WPAppManager")
            .getMethod("main", String[].class)
            .invoke(null, (Object) new String[] {"getNewWPInstance", "EDITOR_TYPE_DOCUMENT", udf});
      } catch (Throwable e) {
        e.printStackTrace();
      }
    });
    t.setDaemon(true);
    t.start();
    long deadline = System.currentTimeMillis() + 90000;
    JTextComponent found = null;
    while (System.currentTimeMillis() < deadline) {
      Thread.sleep(500);
      final JTextComponent[] box = new JTextComponent[1];
      SwingUtilities.invokeAndWait(() -> box[0] = find());
      if (box[0] != null) {
        found = box[0];
        Thread.sleep(2500);
        break;
      }
    }
    if (found == null) {
      System.err.println("NOT FOUND");
      System.exit(2);
    }
    final JTextComponent tc = found;
    final String[] info = new String[1];
    // On its first run UYAP is still building parts of its window after the
    // document shows, and a selection made then throws from its listeners.
    for (int attempt = 0; attempt < 10 && info[0] == null; attempt++) {
      SwingUtilities.invokeAndWait(() -> {
        try {
          tc.requestFocusInWindow();
          int len = tc.getDocument().getLength();
          if (mode.equals("all")) {
            tc.selectAll();
          } else {
            String[] p = mode.split(":");
            tc.select(Integer.parseInt(p[0]), Integer.parseInt(p[1]));
          }
          tc.copy();
          info[0] = "len=" + len + " sel=" + tc.getSelectionStart() + "-" + tc.getSelectionEnd();
        } catch (Exception e) {
          e.printStackTrace();
        }
      });
      if (info[0] == null) Thread.sleep(2000);
    }
    if (info[0] == null) System.exit(3);
    Thread.sleep(500);
    Clipboard cb = Toolkit.getDefaultToolkit().getSystemClipboard();
    StringBuilder sb = new StringBuilder(info[0]).append('\n');
    try {
      for (DataFlavor f : cb.getAvailableDataFlavors()) sb.append("flavor\t").append(f.getMimeType()).append('\n');
    } catch (Exception e) {
      sb.append("flavors failed ").append(e).append('\n');
    }
    try (Writer w = new OutputStreamWriter(new FileOutputStream(ready), "UTF-8")) {
      w.write(sb.toString());
    }
    long stop = System.currentTimeMillis() + 60000;
    while (System.currentTimeMillis() < stop && !new File(done).exists()) Thread.sleep(100);
    System.exit(0);
  }

  static JTextComponent find() {
    JTextComponent best = null;
    for (Window w : Window.getWindows()) {
      if (!w.isShowing()) continue;
      best = pick(w, best);
    }
    return best;
  }

  static JTextComponent pick(Component c, JTextComponent best) {
    if (c instanceof JTextComponent) {
      JTextComponent tc = (JTextComponent) c;
      int len = tc.getDocument().getLength();
      boolean udf = tc.getDocument().getClass().getName().endsWith("DocumentEx");
      if (udf && len > 1 && (best == null || len > best.getDocument().getLength())) best = tc;
    }
    if (c instanceof Container) {
      for (Component ch : ((Container) c).getComponents()) best = pick(ch, best);
    }
    return best;
  }
}
