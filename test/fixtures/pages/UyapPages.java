import java.awt.*;
import java.io.*;
import java.util.*;
import javax.swing.*;
import javax.swing.text.*;

/**
 * Opens a UDF in UYAP's own editor and writes where UYAP put every line:
 * for each line of the document, its first character offset and the
 * rectangle UYAP drew it in, plus the page rectangles of the view tree.
 * Run it through capture_pages.sh.
 */
public class UyapPages {
  public static void main(String[] args) throws Exception {
    final String udf = args[0];
    final String out = args[1];
    final boolean probe = args.length > 2 && args[2].equals("probe");
    final boolean shot = args.length > 2 && args[2].equals("shot");
    final boolean elements = args.length > 2 && args[2].equals("elements");
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
        Thread.sleep(3000);
        break;
      }
    }
    if (found == null) {
      System.err.println("NOT FOUND");
      System.exit(2);
    }
    final JTextComponent tc = found;
    final StringBuilder sb = new StringBuilder();
    SwingUtilities.invokeAndWait(() -> {
      try {
        View root = tc.getUI().getRootView(tc);
        Rectangle bounds = new Rectangle(0, 0, tc.getWidth(), tc.getHeight());
        if (shot) {
          // The component as UYAP paints it, unzoomed pages and all.
          java.awt.image.BufferedImage image = new java.awt.image.BufferedImage(
              tc.getWidth(), Math.min(tc.getHeight(), 1800), java.awt.image.BufferedImage.TYPE_INT_RGB);
          Graphics2D g = image.createGraphics();
          tc.paint(g);
          g.dispose();
          javax.imageio.ImageIO.write(image, "png", new File(out));
          return;
        }
        if (elements) {
          // What UYAP read the file into: every element, with its
          // attributes as UYAP holds them.
          javax.swing.text.Document doc = tc.getDocument();
          for (Element e : doc.getRootElements()) tree(e, 0, sb);
          sb.append("text\t").append(doc.getText(0, doc.getLength()).replace("\n", "\\n")).append('\n');
        } else if (probe) {
          dump(root, bounds, 0, sb);
        } else {
          rows(root, bounds, 0, sb);
          sb.append("length\t").append(tc.getDocument().getLength()).append('\n');
          // UYAP's own text, header and footer included, in its own order:
          // the offsets above count in it, not in the file's CDATA.
          String text = tc.getDocument().getText(0, tc.getDocument().getLength());
          sb.append("text\t").append(java.util.Base64.getEncoder().encodeToString(text.getBytes("UTF-8"))).append('\n');
        }
      } catch (Exception e) {
        StringWriter w = new StringWriter();
        e.printStackTrace(new PrintWriter(w));
        sb.append("error\t").append(w);
      }
    });
    if (!shot) {
      try (Writer w = new OutputStreamWriter(new FileOutputStream(out), "UTF-8")) {
        w.write(sb.toString());
      }
    }
    System.exit(0);
  }

  /** An element and what it holds, one line each, image data by size only. */
  static void tree(Element e, int depth, StringBuilder sb) {
    for (int i = 0; i < depth; i++) sb.append("  ");
    sb.append(e.getName()).append(" [").append(e.getStartOffset()).append(',').append(e.getEndOffset()).append(')');
    AttributeSet a = e.getAttributes();
    java.util.List<String> parts = new java.util.ArrayList<>();
    for (Enumeration<?> names = a.getAttributeNames(); names.hasMoreElements();) {
      Object name = names.nextElement();
      if (name == AttributeSet.NameAttribute || name == AttributeSet.ResolveAttribute) continue;
      Object value = a.getAttribute(name);
      String text = String.valueOf(value);
      if (text.length() > 60) text = "<" + text.length() + " karakter>";
      parts.add(name + "=" + text);
    }
    Collections.sort(parts);
    for (String p : parts) sb.append(' ').append(p);
    sb.append('\n');
    if (depth >= 8) return;
    for (int i = 0; i < e.getElementCount(); i++) tree(e.getElement(i), depth + 1, sb);
  }

  /** The view tree to depth 5: class, element range, allocation. */
  static void dump(View v, Shape a, int depth, StringBuilder sb) {
    Rectangle r = a == null ? null : a.getBounds();
    for (int i = 0; i < depth; i++) sb.append("  ");
    sb.append(v.getClass().getName()).append(" [").append(v.getStartOffset()).append(",")
        .append(v.getEndOffset()).append(") ").append(r).append(" children=").append(v.getViewCount()).append('\n');
    if (depth >= 5) return;
    int n = Math.min(v.getViewCount(), depth < 2 ? 40 : 6);
    for (int i = 0; i < n; i++) {
      dump(v.getView(i), a == null ? null : v.getChildAllocation(i, a), depth + 1, sb);
    }
  }

  /**
   * Every row UYAP laid out, in points, unzoomed: the view tree's leaves
   * above the glyph runs. A paragraph ("para") holds rows ("row"); a table
   * shows as its own views. Written depth-first with each view's range and
   * allocation.
   */
  static void rows(View v, Shape a, int depth, StringBuilder sb) {
    if (a == null) return;
    Rectangle r = a.getBounds();
    String kind = v.getClass().getName();
    kind = kind.substring(kind.lastIndexOf('.') + 1);
    sb.append("view\t").append(depth).append('\t').append(kind).append('\t').append(v.getStartOffset()).append('\t')
        .append(v.getEndOffset()).append('\t').append(r.x).append('\t').append(r.y).append('\t').append(r.width)
        .append('\t').append(r.height).append('\n');
    // Glyph runs below a row say nothing about pages.
    if (depth >= 10) return;
    for (int i = 0; i < v.getViewCount(); i++) {
      View c = v.getView(i);
      if (c.getViewCount() == 0 && depth >= 2) continue;
      rows(c, v.getChildAllocation(i, a), depth + 1, sb);
    }
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
