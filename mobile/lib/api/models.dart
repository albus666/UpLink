class WorkspaceInfo {
  WorkspaceInfo({
    required this.path,
    required this.exists,
    required this.agentBin,
    required this.model,
    this.git,
    this.gitError,
  });

  final String path;
  final bool exists;
  final String agentBin;
  final String model;
  final GitStatus? git;
  final String? gitError;

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) {
    return WorkspaceInfo(
      path: json['path'] as String? ?? '',
      exists: json['exists'] as bool? ?? false,
      agentBin: json['agent_bin'] as String? ?? 'agent',
      model: json['model'] as String? ?? '',
      git: json['git'] is Map<String, dynamic>
          ? GitStatus.fromJson(json['git'] as Map<String, dynamic>)
          : null,
      gitError: json['git_error'] as String?,
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
    this.resultText,
    this.error,
    this.logs = const [],
    this.logCount = 0,
  });

  final String id;
  final String prompt;
  final String status;
  final String createdAt;
  final String? startedAt;
  final String? finishedAt;
  final String? sessionId;
  final String? resultText;
  final String? error;
  final List<LogLine> logs;
  final int logCount;

  bool get isActive => status == 'queued' || status == 'running';

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
      resultText: json['result_text'] as String?,
      error: json['error'] as String?,
      logs: logs,
      logCount: json['log_count'] as int? ?? logs.length,
    );
  }
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
