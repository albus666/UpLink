class WorkspaceInfo {
  WorkspaceInfo({
    required this.path,
    required this.exists,
    required this.agentBin,
    required this.model,
    this.modelLabel = '',
    this.models = const [],
    this.git,
    this.gitError,
  });

  final String path;
  final bool exists;
  final String agentBin;
  final String model;
  final String modelLabel;
  final List<AgentModelOption> models;
  final GitStatus? git;
  final String? gitError;

  String get displayModel => modelLabel.isEmpty ? (model.isEmpty ? '默认' : model) : modelLabel;

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) {
    return WorkspaceInfo(
      path: json['path'] as String? ?? '',
      exists: json['exists'] as bool? ?? false,
      agentBin: json['agent_bin'] as String? ?? 'agent',
      model: json['model'] as String? ?? '',
      modelLabel: json['model_label'] as String? ?? '',
      models: (json['models'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AgentModelOption.fromJson)
          .toList(),
      git: json['git'] is Map<String, dynamic>
          ? GitStatus.fromJson(json['git'] as Map<String, dynamic>)
          : null,
      gitError: json['git_error'] as String?,
    );
  }
}

class AgentModelOption {
  AgentModelOption({required this.id, required this.label});

  final String id;
  final String label;

  factory AgentModelOption.fromJson(Map<String, dynamic> json) {
    return AgentModelOption(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? json['id'] as String? ?? '',
    );
  }
}

class GitStatus {
  GitStatus({
    required this.branch,
    required this.dirty,
    required this.dirtyFiles,
    required this.lastCommit,
    required this.remote,
    this.output,
  });

  final String branch;
  final bool dirty;
  final List<String> dirtyFiles;
  final String lastCommit;
  final String remote;
  final String? output;

  factory GitStatus.fromJson(Map<String, dynamic> json) {
    return GitStatus(
      branch: json['branch'] as String? ?? '',
      dirty: json['dirty'] as bool? ?? false,
      dirtyFiles: (json['dirty_files'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      lastCommit: json['last_commit'] as String? ?? '',
      remote: json['remote'] as String? ?? '',
      output: json['output'] as String?,
    );
  }
}

class LogLine {
  LogLine({required this.ts, required this.kind, required this.text});

  final String ts;
  final String kind;
  final String text;

  factory LogLine.fromJson(Map<String, dynamic> json) {
    return LogLine(
      ts: json['ts'] as String? ?? '',
      kind: json['kind'] as String? ?? 'raw',
      text: json['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'ts': ts,
        'kind': kind,
        'text': text,
      };
}

class RemoteTask {
  RemoteTask({
    required this.id,
    required this.prompt,
    required this.status,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.sessionId,
    this.resumeOf,
    this.resultText,
    this.error,
    this.mode = 'agent',
    this.title,
    this.pinned = false,
    this.logs = const [],
    this.logCount = 0,
    this.pendingApproval,
  });

  final String id;
  final String prompt;
  final String status;
  final String createdAt;
  final String? startedAt;
  final String? finishedAt;
  final String? sessionId;
  final String? resumeOf;
  final String? resultText;
  final String? error;
  final String mode;
  final String? title;
  final bool pinned;
  final List<LogLine> logs;
  final int logCount;
  final Map<String, dynamic>? pendingApproval;

  bool get isActive =>
      status == 'queued' || status == 'running' || status == 'awaiting_approval';

  factory RemoteTask.fromJson(Map<String, dynamic> json) {
    final logs = (json['logs'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LogLine.fromJson)
        .toList();
    return RemoteTask(
      id: json['id'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      createdAt: json['created_at'] as String? ?? '',
      startedAt: json['started_at'] as String?,
      finishedAt: json['finished_at'] as String?,
      sessionId: json['session_id'] as String?,
      resumeOf: json['resume_of'] as String?,
      resultText: json['result_text'] as String?,
      error: json['error'] as String?,
      mode: json['mode'] as String? ?? 'agent',
      title: json['title'] as String?,
      pinned: json['pinned'] == true || json['pinned'] == 1,
      logs: logs,
      logCount: json['log_count'] as int? ?? logs.length,
      pendingApproval: json['pending_approval'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'prompt': prompt,
        'status': status,
        'created_at': createdAt,
        'started_at': startedAt,
        'finished_at': finishedAt,
        'session_id': sessionId,
        'resume_of': resumeOf,
        'result_text': resultText,
        'error': error,
        'mode': mode,
        'title': title,
        'pinned': pinned,
        'logs': logs.map((line) => line.toJson()).toList(),
        'log_count': logCount,
        'pending_approval': pendingApproval,
      };
}

class RemoteUpload {
  RemoteUpload({
    required this.id,
    required this.originalName,
    required this.relativePath,
    required this.size,
    required this.createdAt,
  });

  final String id;
  final String originalName;
  final String relativePath;
  final int size;
  final String createdAt;

  factory RemoteUpload.fromJson(Map<String, dynamic> json) {
    return RemoteUpload(
      id: json['id'] as String? ?? '',
      originalName: json['original_name'] as String? ?? '',
      relativePath: json['relative_path'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class RemoteFsEntry {
  RemoteFsEntry({
    required this.name,
    required this.path,
    required this.kind,
    required this.size,
    required this.text,
  });

  final String name;
  final String path;
  final String kind;
  final int size;
  final bool text;

  bool get isDir => kind == 'dir';

  factory RemoteFsEntry.fromJson(Map<String, dynamic> json) {
    return RemoteFsEntry(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      kind: json['kind'] as String? ?? 'file',
      size: json['size'] as int? ?? 0,
      text: json['text'] as bool? ?? false,
    );
  }
}

class RemoteFsListing {
  RemoteFsListing({
    required this.root,
    required this.path,
    required this.parent,
    required this.items,
  });

  final String root;
  final String path;
  final String parent;
  final List<RemoteFsEntry> items;

  factory RemoteFsListing.fromJson(Map<String, dynamic> json) {
    return RemoteFsListing(
      root: json['root'] as String? ?? '',
      path: json['path'] as String? ?? '',
      parent: json['parent'] as String? ?? '',
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RemoteFsEntry.fromJson)
          .toList(),
    );
  }
}

class RemoteFileContent {
  RemoteFileContent({required this.path, required this.name, required this.content, required this.size});

  final String path;
  final String name;
  final String content;
  final int size;

  factory RemoteFileContent.fromJson(Map<String, dynamic> json) {
    return RemoteFileContent(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      content: json['content'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }
}
