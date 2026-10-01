// Use an isolated Wine/Xvfb desktop on Linux; this test owns the clipboard.
#include "../../windows/runner/rich_clipboard_data.h"

#include <cassert>
#include <cstring>
#include <iostream>

void Publish(const wchar_t* name, const std::vector<uint8_t>& bytes) {
  const HGLOBAL handle = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
  assert(handle);
  void* memory = GlobalLock(handle);
  assert(memory);
  std::memcpy(memory, bytes.data(), bytes.size());
  GlobalUnlock(handle);
  assert(SetClipboardData(RegisterClipboardFormatW(name), handle));
}

int main() {
  HWND window = CreateWindowExW(0, L"STATIC", L"Folio clipboard test", 0,
                                0, 0, 1, 1, nullptr, nullptr, nullptr, nullptr);
  assert(window);
  assert(OpenClipboard(window));
  assert(EmptyClipboard());
  const std::string html = "<p><b>Word HTML</b></p>";
  const std::string rtf = "{\\rtf1\\ansi\\b Word RTF}";
  Publish(L"HTML Format", {html.begin(), html.end()});
  Publish(L"Rich Text Format", {rtf.begin(), rtf.end()});
  // Publish in the reverse order to prove selection is not enumeration order.
  const std::vector<uint8_t> binary{0xac, 0xed, 0, 5, 0xff, 0, 0x73};
  Publish(L"JAVA_DATAFLAVOR:application/x-java-serialized-object; class=tr.com.havelsan.uyap.system.editor.common.text.EditorDataFlavor", binary);
  CloseClipboard();
  assert(OpenClipboard(window));
  const auto list = folio::ReadRichClipboardData();
  CloseClipboard();
  assert(list.size() == 3);
  const char* formats[] = {"uyap", "html", "rtf"};
  const std::vector<uint8_t> expected[] = {
      binary, {html.begin(), html.end()}, {rtf.begin(), rtf.end()}};
  for (size_t i = 0; i < list.size(); ++i) {
    assert(list[i].format == formats[i]);
    assert(list[i].data == expected[i]);
  }

  // Folio's own copy: text, CF_HTML and RTF, read back as another program
  // would read them.
  const std::string text = "Folio \xc4\xb0\xc5\x9f metni";
  const std::string cf_html = "Version:0.9\r\n<html><body>Folio</body></html>";
  const std::string folio_rtf = "{\\rtf1\\ansi Folio}";
  assert(OpenClipboard(window));
  assert(folio::WriteRichClipboardData(
      text, {cf_html.begin(), cf_html.end()},
      {folio_rtf.begin(), folio_rtf.end()}));
  CloseClipboard();
  assert(OpenClipboard(window));
  const auto written = folio::ReadRichClipboardData();
  const HANDLE unicode = GetClipboardData(CF_UNICODETEXT);
  assert(unicode);
  const std::wstring read(static_cast<const wchar_t*>(GlobalLock(unicode)));
  GlobalUnlock(unicode);
  CloseClipboard();
  assert(read == folio::WideFromUtf8(text));
  assert(written.size() == 2);
  assert(written[0].format == "html");
  assert(written[1].format == "rtf");
  // Readers get the bytes back with the NUL terminator the writer added.
  assert(std::string(written[0].data.begin(), written[0].data.end() - 1) ==
         cf_html);
  assert(std::string(written[1].data.begin(), written[1].data.end() - 1) ==
         folio_rtf);
  DestroyWindow(window);
  std::cout << "Win32 clipboard: HTML, RTF and UYAP bytes and priority preserved.\n";
  std::cout << "Win32 clipboard: Folio's text, CF_HTML and RTF written.\n";
}
