library;
import 'package:client_macro/client_macro.dart';

@API("""
  /foo
  /foo/:bar
  /foo/:bar/baz
  /foo/:bar/baz/:quz
  /bar/:foo
  /baz/foo
  /baz/foo/:bar/:quz
  /hello
  /hello/:world
""")
class _A {}

void main() {
  final client = APIClient();
  print(client.hello("turkey").route);
}
