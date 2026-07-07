// Servidor estático para testar o build web (build/ ou web/ compilado).
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

Future<void> main(List<String> args) async {
  final dir = args.isNotEmpty ? args[0] : 'build';
  final port = args.length > 1 ? int.parse(args[1]) : 8088;
  final handler = createStaticHandler(dir, defaultDocument: 'index.html');
  final server = await shelf_io.serve(handler, 'localhost', port);
  print('Servindo $dir em http://localhost:${server.port}');
}
