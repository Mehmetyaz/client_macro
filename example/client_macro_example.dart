@API("""
  /foo
  /foo/:bar
  /foo/:bar/baz
  /foo/:bar/baz/:qu
  /bar/:foo
  /baz/foo
  /baz/foo/:bar
  /hello
  /hello/:world
""")
library;

import 'package:client_macro/client_macro.dart';

void main() {
  final client = APIClient();
  print(client.hello("turkey").route);
}
