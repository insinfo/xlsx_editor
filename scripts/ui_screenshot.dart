// Abre o app compilado no Chrome headless e captura screenshots das duas
// abas para inspeção visual (requer `dart run scripts/serve.dart build 8088`
// já rodando ou passa a URL como argumento).
import 'dart:io';

import 'package:puppeteer/puppeteer.dart';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://localhost:8088/';
  final browser = await puppeteer.launch(
    headless: true,
    args: ['--window-size=1680,1000', '--force-device-scale-factor=1'],
  );
  final page = await browser.newPage();
  await page.setViewport(DeviceViewport(width: 1680, height: 1000));
  page.onConsole.listen((msg) => print('console: ${msg.text}'));
  page.onError.listen((err) => print('PAGEERROR: $err'));

  await page.goto(url, wait: Until.networkIdle);
  await Future<void>.delayed(const Duration(seconds: 3));
  await page.screenshot().then(
      (bytes) => File('build/shot_media.png').writeAsBytesSync(bytes));

  // Troca para a aba Composições.
  final tabs = await page.$$('.xe-tab');
  if (tabs.length > 1) {
    await tabs[1].click();
    await Future<void>.delayed(const Duration(seconds: 2));
    await page.screenshot().then(
        (bytes) => File('build/shot_composicoes.png').writeAsBytesSync(bytes));
  }
  print('screenshots gravados em build/shot_*.png');
  await browser.close();
}
