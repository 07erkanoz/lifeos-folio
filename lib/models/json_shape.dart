/// A list in JSON that another device, a file or a server gave: empty when
/// it is none. `value as List?` throws on a map or a string, and one such
/// field took a whole merge back with it.
List<dynamic> jsonList(Object? value) => value is List ? value : const [];
