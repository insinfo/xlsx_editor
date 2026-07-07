// Teste de edição + recálculo no browser: altera a cotação D12 da aba MÉDIA
// e verifica que as células dependentes (médias/medianas) recalculam.
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
  page.onError.listen((err) => print('PAGEERROR: $err'));

  await page.goto(url, wait: Until.networkIdle);
  await Future<void>.delayed(const Duration(seconds: 3));

  Future<void> goTo(String ref) async {
    await page.click('.xe-namebox');
    await page.evaluate(
        "() => { document.querySelector('.xe-namebox').value = ''; }");
    await page.keyboard.type(ref);
    await page.keyboard.press(Key.enter);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<String> formulaBar() async => await page.evaluate<String>(
      "() => document.querySelector('.xe-formulainput').value");
  Future<String> status() async => await page.evaluate<String>(
      "() => document.querySelector('.xe-status').textContent");

  // Antes: L8 é a média estimada (R$ 303.096,17).
  await goTo('L8');
  print('L8 antes  -> fórmula: ${await formulaBar()}');
  print('status antes: ${await status()}');

  // Edita D12: 318357,75 -> 100000.
  await goTo('D12');
  print('D12 antes -> ${await formulaBar()}');
  await page.keyboard.type('100000');
  await page.keyboard.press(Key.enter);
  await Future<void>.delayed(const Duration(milliseconds: 500));

  await goTo('D12');
  print('D12 depois -> ${await formulaBar()}');
  await goTo('E12');
  print('E12 (média dos demais) -> ${await formulaBar()}');
  await goTo('L8');
  print('status L8 depois: ${await status()}');

  await page.screenshot().then(
      (bytes) => File('build/shot_edit.png').writeAsBytesSync(bytes));
  print('screenshot build/shot_edit.png');
  await browser.close();
}
