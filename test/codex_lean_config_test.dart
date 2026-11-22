import 'package:evrak_convert/services/voice/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the lawyer’s MCP servers and plugins are off for Folio’s Codex', () {
    const config = '''
model = "gpt-5"
[mcp_servers.blender]
command = "python"
[mcp_servers.blender.env]
A = "1"
[mcp_servers.node_repl]
[plugins."browser@openai-bundled"]
enabled = true
[projects."/home/x"]
''';
    final args = CodexAppServer.leanConfig(config);
    final said = [for (var i = 1; i < args.length; i += 2) args[i]];
    expect(said, [
      'mcp_servers.blender.enabled=false',
      'mcp_servers.node_repl.enabled=false',
      'plugins."browser@openai-bundled".enabled=false',
      'features.plugins=false',
      'features.code_mode=false',
    ]);
    expect({for (var i = 0; i < args.length; i += 2) args[i]}, {'-c'});
  });
}
