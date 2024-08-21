import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:macros/macros.dart';
import "package:http/http.dart" as http;


macro class API implements LibraryTypesMacro {

  const API(this.endpoints);

  final String endpoints;

  String get classPrefix => "";

  RouteItem _buildRoot() {
    final root = RouteItem("${classPrefix ?? ""}APIClient", null, [], "");

    final endpoints = this.endpoints.split("\n").where((element) =>
    element
        .trim()
        .isNotEmpty).toList();

    for (final endpoint in endpoints) {
      root.add(endpoint);
    }

    return root;
  }


  @override
  FutureOr<void> buildTypesForLibrary(Library library, TypeBuilder builder) {
    final root = _buildRoot();

    root.buildClass(builder);

    return Future.value();
  }

}

const intend = "  ";

String withIntend(String? content) {
  if (content == null) {
    return "";
  }
  return content.split("\n").map((e) => "$intend$e").join("\n");
}

class RouteItem {
  final String _name;
  final RouteItem? parent;
  final List<RouteItem> children;

  RouteItem(this._name, this.parent, this.children, this.route);

  bool get isRoot => parent == null;

  bool get isLeaf => children.isEmpty;

  bool get isParameter => _name.startsWith(':');

  String get name => isParameter ? _name.substring(1) : _name;

  String get className {
    var name = capitalize;
    if (parent != null) {
      name = parent!.className + name;
    }
    return name;
  }

  String get privateClassName {
    if (isRoot) {
      return className;
    }
    return "_$className";
  }

  String get capitalize {
    final name = this.name;
    if (name.isEmpty) {
      return name;
    }

    if (name.length == 1) {
      return name.toUpperCase();
    }
    return name[0].toUpperCase() + name.substring(1);
  }

  String get builtRoute {
    final parts = route.split('/').where((element) =>
    element
        .trim()
        .isNotEmpty).toList();

    final fParts = parts.map((e) {
      if (e.startsWith(':')) {
        return "\${${e.replaceFirst(":", "")}}";
      }
      return e;
    }).toList().join("/");

    return "/$fParts";
  }

  RouteItem add(String path) {
    final parts = path.split('/')
        .where((element) =>
    element
        .trim()
        .isNotEmpty)
        .toList();

    final first = parts.first;
    final rest = parts.skip(1).join('/');

    final existing = children.firstWhereOrNull((element) =>
    element._name == first);

    if (existing != null) {
      return existing.add(rest);
    }

    final child = RouteItem(first, this, [], "$route/$first");

    children.add(child);

    if (rest.isNotEmpty) {
      return child.add(rest);
    }

    return child;
  }

  String get camelCase {
    var parts = name.split('_');
    final buffer = StringBuffer();
    for (final part in parts) {
      buffer.write(part[0].toLowerCase());
      buffer.write(part.substring(1));
    }
    return buffer.toString();
  }

  List<String> get params {
    final buffer = <String>[];
    var current = parent;
    while (current != null) {
      if (current.isParameter) {
        if (buffer.contains(current.name)) {
          throw Exception("Duplicate parameter name: ${current.name}");
        }
        buffer.add(current.name);
      }

      current = current.parent;
    }


    return buffer;
  }

  String route;

  void buildClass(TypeBuilder builder) {
    final constructorParams = [];


    String? currentParam;

    if (isParameter) {
      currentParam = "final String $name;";
      constructorParams.add(name);
    }

    String? otherParams;

    if (params.isNotEmpty) {
      otherParams = params.map((e) => "final String $e;").join("\n");
      constructorParams.addAll(params);
    }

    String constructor;

    if (constructorParams.isNotEmpty) {
      constructor = """
$privateClassName({${constructorParams.map((e) => 'required this.$e').join(
          ', ')}});    
    """;
    } else {
      constructor = "$privateClassName();";
    }


    String? callMethod;

    bool childHasParam = false;

    for (final child in children) {
      if (child.isParameter) {
        childHasParam = true;
        break;
      }
    }

    if (childHasParam && children.length > 1) {
      throw Exception("Cannot have multiple children with parameters");
    }

    if (childHasParam) {
      final child = children.firstWhere((element) => element.isParameter);
      callMethod = """
${child.privateClassName} call(String ${child.camelCase}) => ${child
          .privateClassName}(
${[child.camelCase, ...child.params].map((e) => '$e: $e').join(', ')}
);
      """;
    }

    List<String> getters = [];


    for (final child in children) {
      if (child.isParameter) {
        continue;
      }

      List<String> getterParams = [];

      if (params.isNotEmpty) {
        getterParams.addAll(params);
      }


      if (isParameter) {
        getterParams.add(camelCase);
      }

      for (var i = 0; i < getterParams.length; i++) {
        getterParams[i] = "${getterParams[i]}: ${getterParams[i]}";
      }


      var pa = getterParams.join(", ");


      getters.add("""
${child.privateClassName} get ${child.camelCase} => ${child
          .privateClassName}($pa);
      """);
    }


    final clazz = """
class $privateClassName extends Route {
${withIntend(currentParam)}
${withIntend(otherParams)}
${withIntend(constructor)}
${withIntend("@override")}
${withIntend("String get route => \"$builtRoute\";")}

${withIntend(getters.join("\n"))}

${withIntend(callMethod)}

}    
    
    """;

    builder.declareType(
        privateClassName, DeclarationCode.fromString(clazz));


    for (final child in children) {
      child.buildClass(builder);
    }
  }


  @override
  String toString() {
    return "RouteItem(\n$_name,\n${children.toString().split("\n").join(
        "\n   ")}\n)";
  }

}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) {
        return element;
      }
    }
    return null;
  }
}


class APIBase {
  static String baseUrl = "http://localhost:8080";
  static String? token;

  static bool get isAuthenticated => token != null;
  static Future<dynamic> Function({
  required int statusCode,
  required String rBody,
  required Map<String, String> headers,
  required String? reasonPhrase
  })? handleResponse;

  static void Function()? invalidateToken;

}

abstract class Route {

  Route();

  String get route;

  Future<dynamic> get(String? p,
      {Map<String, String>? query,
        Map<String, String>? additionalHeaders}) async {
    return _handleResponse(await http.get(_uri(route, p, query),
        headers: authHeaders(additionalHeaders)));
  }

  Future<dynamic> post(String? p, Map<String, dynamic>? body,
      {Map<String, String>? query,
        Encoding? encoding,
        Map<String, String>? additionalHeaders}) async {
    return _handleResponse(await http.post(_uri(route, p, query),
        body: body != null ? jsonEncode(body) : null,
        encoding: encoding,
        headers: authHeaders(additionalHeaders)));
  }

  Future<dynamic> put(String? p, Map<String, dynamic>? body,
      {Map<String, String>? query,
        Encoding? encoding,
        Map<String, String>? additionalHeaders}) async {
    return _handleResponse(await http.put(_uri(route, p, query),
        body: body != null ? jsonEncode(body) : null,
        encoding: encoding,
        headers: authHeaders(additionalHeaders)));
  }

  Future<dynamic> delete(String? p,
      {Map<String, String>? query,
        Map<String, String>? additionalHeaders}) async {
    return _handleResponse(await http.delete(_uri(route, p, query),
        headers: authHeaders(additionalHeaders)));
  }

  Uri _uri(String p, String? sec, [Map<String, String>? query]) {
    final uri = Uri.parse(APIBase.baseUrl);

    return Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.port,
        queryParameters: query,
        path: "$p${sec == null ? "" : "/$sec"}".replaceAll("//", "/"));
  }

  static Map<String, String> authHeaders(
      [Map<String, String>? additionalHeaders]) {
    return {
      "Origin": APIBase.baseUrl,
      if (APIBase.isAuthenticated) "Authorization": "Bearer ${APIBase.token}",
      "Content-Type": "application/json",
      if (additionalHeaders != null) ...additionalHeaders,
      ..._Session.headers
    };
  }


  Future<dynamic> _handleResponse(http.Response res) async {
    final statusCode = res.statusCode;
    final rBody = res.body;
    final headers = res.headers;
    final reasonPhrase = res.reasonPhrase;
    _Session.updateCookie(headers);
    if (statusCode < 299) {
      if (headers['content-type']?.contains('application/json') == true) {
        return json.decode(rBody);
      }

      return rBody;
    } else if (statusCode > 399) {
      if (statusCode == 401) {
        APIBase.invalidateToken?.call();
        throw APIError(401, "Unauthorized", "unauthorized", {});
      }

      dynamic jsonBody;

      try {
        final body = json.decode(rBody);
        jsonBody = body;
      } catch (e) {
        throw APIError(
            statusCode, reasonPhrase ?? "unknown", "unknown", {});
      }

      throw APIError.fromMap(statusCode, jsonBody);
    }
  }


}

class APIError extends Error {
  APIError(this.statusCode, this.statusMessage, this.reason, this.payload);

  APIError.fromMap(this.statusCode, Map<String, dynamic> map)
      : statusMessage = map["status_text"],
        reason = map["reason"],
        payload = map["payload"];

  final int statusCode;
  final String statusMessage;
  final String reason;
  final Map<String, dynamic>? payload;

  @override
  String toString() {
    return 'APIError: $statusMessage: $reason : $payload ';
  }
}


class _Session {
  static final Map<String, String> headers = {};

  static void updateCookie(Map<String, String> headers) {
    String? rawCookie = headers['set-cookie'];

    if (rawCookie != null) {
      _Session.headers['cookie'] =
          Cookie.fromSetCookieValue(rawCookie).toString();
    }
  }
}
