class DevRowModel {
  final String name;
  final String meta;
  final String status;
  final bool ok;
  final List<String> actions;

  const DevRowModel({required this.name, required this.meta, required this.status, required this.ok, required this.actions});

  factory DevRowModel.fromJson(Map<String, dynamic> json) {
    return DevRowModel(
      name: json['name'] as String? ?? '',
      meta: json['meta'] as String? ?? '',
      status: json['status'] as String? ?? '',
      ok: json['ok'] as bool? ?? false,
      actions: (json['actions'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}
