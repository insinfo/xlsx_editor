import 'dart:async';
import 'dart:io';

import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

void main() {
  late Process server;
  late Browser browser;
  late Page page;
  late int port;

  setUpAll(() async {
    final build = await Process.run(
      Platform.resolvedExecutable,
      [
        'run',
        'build_runner',
        'build',
        '-o',
        'web:build',
        '--release',
        '--delete-conflicting-outputs',
      ],
      runInShell: true,
    );
    if (build.exitCode != 0) {
      fail(
          'Falha ao compilar a aplicação web:\n${build.stdout}\n${build.stderr}');
    }

    port = await _availablePort();
    server = await Process.start(
      Platform.resolvedExecutable,
      ['run', 'scripts/serve.dart', 'build', '$port'],
      runInShell: true,
    );
    await _waitForServer(Uri.parse('http://localhost:$port/'));

    browser = await puppeteer.launch(
      headless: true,
      args: [
        '--window-size=1440,900',
        '--force-device-scale-factor=1',
      ],
    );
    page = await browser.newPage();
    await page.setViewport(DeviceViewport(width: 1440, height: 900));
  });

  tearDownAll(() async {
    await browser.close();
    server.kill();
    await server.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () => -1,
    );
  });

  setUp(() async {
    await page.goto('http://localhost:$port/', wait: Until.networkIdle);
    await page.waitForSelector('.xe-embed');
    await page.waitForSelector('.xe-tab');
  });

  test('renderiza a grade em canvas com o tema verde do Excel', () async {
    final state = await page.evaluate<Map<String, dynamic>>('''() => {
      const root = document.querySelector('.xe-embed');
      const canvas = document.querySelector('.xe-canvas');
      const grid = document.querySelector('.xe-grid');
      const style = getComputedStyle(root);
      return {
        canvasWidth: canvas.width,
        canvasHeight: canvas.height,
        gridWidth: grid.getBoundingClientRect().width,
        gridHeight: grid.getBoundingClientRect().height,
        accent: style.getPropertyValue('--xe-accent').trim(),
        tabs: document.querySelectorAll('.xe-tab').length,
      };
    }''');

    expect(state['canvasWidth'], greaterThan(0));
    expect(state['canvasHeight'], greaterThan(0));
    expect(state['gridWidth'], greaterThan(500));
    expect(state['gridHeight'], greaterThan(300));
    expect((state['accent'] as String).toLowerCase(), '#107c41');
    expect(state['tabs'], greaterThanOrEqualTo(2));
  });

  test('navega e edita uma célula pela interface', () async {
    await _goToCell(page, 'D12');
    final before = await _formulaValue(page);
    expect(before, isNotEmpty);

    await page.keyboard.type('100000');
    await page.keyboard.press(Key.enter);
    await _goToCell(page, 'D12');

    expect(await _formulaValue(page), '100000');
  });

  test('modo visualizador bloqueia edição e oculta a toolbar', () async {
    await page.select('#demo-mode', ['viewer']);
    await page.waitForSelector('.xe-embed--viewer');
    await _goToCell(page, 'D12');
    final before = await _formulaValue(page);

    await page.keyboard.type('999999');
    await page.keyboard.press(Key.enter);
    await _goToCell(page, 'D12');

    final display = await page.evaluate<String>(
      "() => getComputedStyle(document.querySelector('.xe-toolbar')).display",
    );
    expect(display, 'none');
    expect(await _formulaValue(page), before);
  });

  test('alterna para aparência compacta sem desmontar a página host', () async {
    await page.select('#demo-appearance', ['compact']);
    await page.waitForSelector('.xe-embed--compact');

    final compactState = await page.evaluate<Map<String, dynamic>>('''() => ({
      hasTitlebar: document.querySelector('.xe-titlebar') !== null,
      hasCompactToolbar: document.querySelector('.xe-toolbar--compact') !== null,
      hasCanvas: document.querySelector('#editor-host .xe-canvas') !== null,
    })''');
    expect(compactState['hasTitlebar'], isFalse);
    expect(compactState['hasCompactToolbar'], isTrue);
    expect(compactState['hasCanvas'], isTrue);
  });
}

Future<void> _goToCell(Page page, String reference) async {
  await page.click('.xe-namebox');
  await page.evaluate(
    "() => document.querySelector('.xe-namebox').value = ''",
  );
  await page.keyboard.type(reference);
  await page.keyboard.press(Key.enter);
  await Future<void>.delayed(const Duration(milliseconds: 100));
}

Future<String> _formulaValue(Page page) => page.evaluate<String>(
      "() => document.querySelector('.xe-formulainput').value",
    );

Future<int> _availablePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> _waitForServer(Uri uri) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode == HttpStatus.ok) return;
    } catch (error) {
      lastError = error;
    } finally {
      client.close(force: true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError('Servidor E2E não iniciou: $lastError');
}
