import 'dart:math' as math;

// Mirrors the `getCommitGraph` callable's payload
// (functions/src/flows/getCommitGraph.ts) — branch-topology data fetched
// on demand from the GitHub API (commit docs in Firestore carry no parents).
//
// Also hosts `buildGraphRows`, the pure lane-assignment pass (the standard
// git log --graph / gitk "active lanes" algorithm) that turns the commit
// list into per-row paint geometry. Kept here (no Flutter imports) so it is
// unit-testable — see test/commit_graph_layout_test.dart.

class GraphCommit {
  final String sha;
  final String message;
  final DateTime committedAt;

  /// Parent SHAs. A SHA not present in the fetched window means the line
  /// runs off-screen (older than the range / un-fetched branch).
  final List<String> parents;

  /// GitHub login; null when the commit email isn't linked to an account.
  final String? authorLogin;
  final String authorName;
  final String? avatarUrl;
  final String primaryBranch;
  final bool isMerge;
  final int? prNumber;

  const GraphCommit({
    required this.sha,
    required this.message,
    required this.committedAt,
    this.parents = const [],
    this.authorLogin,
    this.authorName = '',
    this.avatarUrl,
    this.primaryBranch = '',
    this.isMerge = false,
    this.prNumber,
  });

  factory GraphCommit.fromMap(Map<String, dynamic> map) {
    final author = Map<String, dynamic>.from(map['author'] as Map? ?? {});
    return GraphCommit(
      sha: map['sha'] as String? ?? '',
      message: map['message'] as String? ?? '',
      committedAt:
          DateTime.tryParse(map['committedAt'] as String? ?? '')?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
      parents: List<String>.from(map['parents'] as List? ?? []),
      authorLogin: author['login'] as String?,
      authorName: author['name'] as String? ?? '',
      avatarUrl: author['avatarUrl'] as String?,
      primaryBranch: map['primaryBranch'] as String? ?? '',
      isMerge: map['isMerge'] as bool? ?? false,
      prNumber: (map['prNumber'] as num?)?.toInt(),
    );
  }
}

class GraphBranch {
  final String name;
  final String tipSha;
  final bool isDefault;

  const GraphBranch({
    required this.name,
    required this.tipSha,
    this.isDefault = false,
  });

  factory GraphBranch.fromMap(Map<String, dynamic> map) => GraphBranch(
        name: map['name'] as String? ?? '',
        tipSha: map['tipSha'] as String? ?? '',
        isDefault: map['isDefault'] as bool? ?? false,
      );
}

class CommitGraph {
  /// Newest first (the callable sorts by committedAt desc).
  final List<GraphCommit> commits;
  final List<GraphBranch> branches;

  /// True when the branch cap or a per-branch history page limit was hit.
  final bool truncated;

  const CommitGraph({
    this.commits = const [],
    this.branches = const [],
    this.truncated = false,
  });

  factory CommitGraph.fromMap(Map<String, dynamic> map) => CommitGraph(
        commits: (map['commits'] as List? ?? [])
            .map((e) => GraphCommit.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        branches: (map['branches'] as List? ?? [])
            .map((e) => GraphBranch.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        truncated: map['truncated'] as bool? ?? false,
      );

  /// tip sha → branch name, for labeling branch heads in the graph.
  Map<String, String> get tipLabels => {
        for (final b in branches)
          if (b.tipSha.isNotEmpty) b.tipSha: b.name,
      };
}

// ---- Lane assignment ("active lanes" algorithm) -----------------------------

/// Paint geometry for one commit row of the branch graph. All lane indices are
/// columns; the painter maps column l to x = laneWidth/2 + l*laneWidth.
class GraphRowGeometry {
  final GraphCommit commit;

  /// The column the node dot sits in.
  final int lane;

  /// Lane has a child above (line from the top edge down to the node).
  final bool topStem;

  /// Lane continues below toward the first parent (node down to bottom edge).
  final bool bottomStem;

  /// Columns whose vertical line passes straight through this row.
  final List<bool> passThrough;

  /// Columns (above the row) whose line converges diagonally into the node —
  /// merge lines from other lanes ending at this commit.
  final List<int> intoNode;

  /// Columns (below the row) that fork diagonally out of the node — extra
  /// parents of a merge commit opening (or joining) other lanes.
  final List<int> outOfNode;

  const GraphRowGeometry({
    required this.commit,
    required this.lane,
    required this.topStem,
    required this.bottomStem,
    this.passThrough = const [],
    this.intoNode = const [],
    this.outOfNode = const [],
  });

  /// Number of columns this row touches (for rail sizing).
  int get laneSpan {
    var span = lane + 1;
    for (var l = 0; l < passThrough.length; l++) {
      if (passThrough[l]) span = math.max(span, l + 1);
    }
    for (final l in intoNode) {
      span = math.max(span, l + 1);
    }
    for (final l in outOfNode) {
      span = math.max(span, l + 1);
    }
    return span;
  }
}

/// Assigns lanes to [commits] (must be newest → oldest, exactly the fetched
/// window) with the standard git-log/gitk active-lanes pass:
///
/// * a lane "expects" the next SHA on its line going down;
/// * a commit sits in the leftmost lane expecting it (other expecting lanes
///   converge into it and are freed — merge collapse), or opens a new lane
///   when nothing expects it (branch tip / child off-window);
/// * its lane then expects its first parent; extra parents (merges) either
///   join the lane already expecting them or open a new lane (fork edge) —
///   loops over all parents, so octopus merges need nothing special;
/// * a first parent missing from the window simply keeps the lane's line
///   running off the bottom edge (off-screen history stub).
List<GraphRowGeometry> buildGraphRows(List<GraphCommit> commits) {
  final active = <String?>[]; // lane → the SHA that lane expects next
  final rows = <GraphRowGeometry>[];

  int alloc() {
    final free = active.indexOf(null);
    if (free != -1) return free;
    active.add(null);
    return active.length - 1;
  }

  for (final c in commits) {
    final above = List<String?>.of(active);

    var lane = active.indexOf(c.sha);
    final isTip = lane == -1;
    if (isTip) lane = alloc();

    // Other lanes expecting this commit converge into the node and free up.
    final intoNode = <int>[];
    for (var l = 0; l < active.length; l++) {
      if (l != lane && active[l] == c.sha) {
        intoNode.add(l);
        active[l] = null;
      }
    }

    // The node's own line continues down toward its first parent.
    active[lane] = c.parents.isEmpty ? null : c.parents.first;

    // Extra parents: join the lane already expecting them, else open one.
    final outOfNode = <int>[];
    for (var k = 1; k < c.parents.length; k++) {
      final p = c.parents[k];
      var l = active.indexOf(p);
      if (l == -1) {
        l = alloc();
        active[l] = p;
      }
      if (l != lane) outOfNode.add(l);
    }

    final below = List<String?>.of(active);
    final cols = math.max(above.length, below.length);
    final passThrough = List<bool>.generate(cols, (l) {
      if (l == lane) return false;
      final a = l < above.length ? above[l] : null;
      final b = l < below.length ? below[l] : null;
      return a != null && a == b;
    });

    rows.add(GraphRowGeometry(
      commit: c,
      lane: lane,
      topStem: !isTip,
      bottomStem: c.parents.isNotEmpty,
      passThrough: passThrough,
      intoNode: intoNode,
      outOfNode: outOfNode,
    ));

    // Keep the lane list compact so freed right-edge columns are reusable.
    while (active.isNotEmpty && active.last == null) {
      active.removeLast();
    }
  }
  return rows;
}
