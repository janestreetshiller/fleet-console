use crate::snapshot::{FleetTopology, TopologyEdgeKind, TopologyNodeKind};
use std::collections::{HashMap, HashSet};

pub(crate) const CARD_WIDTH: f32 = 220.0;
pub(crate) const CARD_HEIGHT: f32 = 82.0;
pub(crate) const COLUMN_GAP: f32 = 30.0;
pub(crate) const ROW_GAP: f32 = 34.0;
const SESSION_GAP: f32 = 48.0;
const COLUMNS: usize = 4;
const LIMIT: usize = 120;
const SESSION_RESERVE: usize = 24;

#[derive(Debug, PartialEq)]
pub(crate) struct PlacedNode {
    pub(crate) source_index: usize,
    pub(crate) x: f32,
    pub(crate) y: f32,
}

#[derive(Debug, PartialEq, Eq)]
pub(crate) struct PlacedEdge {
    pub(crate) source_index: usize,
    pub(crate) source: usize,
    pub(crate) target: usize,
}

#[derive(Debug, PartialEq)]
pub(crate) struct Layout {
    pub(crate) nodes: Vec<PlacedNode>,
    pub(crate) edges: Vec<PlacedEdge>,
    pub(crate) width: f32,
    pub(crate) height: f32,
    pub(crate) omitted: usize,
}

impl Layout {
    pub(crate) fn new(topology: &FleetTopology) -> Self {
        use TopologyNodeKind::{Leader, Listener, Owner, Service, Session};

        let capacity = topology.nodes.len().min(LIMIT);
        let mut layout = Self {
            nodes: Vec::with_capacity(capacity),
            edges: Vec::new(),
            width: 0.0,
            height: 0.0,
            omitted: 0,
        };
        let reserved_sessions = if topology.nodes.len() > LIMIT {
            topology
                .nodes
                .iter()
                .filter(|node| node.kind == Session)
                .take(SESSION_RESERVE)
                .count()
        } else {
            0
        };
        let registry_capacity = capacity - reserved_sessions;
        for kind in [Owner, Service, Leader, Listener, Session] {
            let band_capacity = if kind == Session {
                capacity
            } else {
                registry_capacity
            };
            let remaining = band_capacity - layout.nodes.len();
            if remaining == 0 {
                continue;
            }
            let start_y = if layout.nodes.is_empty() {
                0.0
            } else if kind == Session {
                layout.height + SESSION_GAP
            } else {
                layout.height + ROW_GAP
            };
            let matching = topology
                .nodes
                .iter()
                .enumerate()
                .filter(|(_, node)| node.kind == kind);
            for (slot, (source_index, _)) in matching.take(remaining).enumerate() {
                let x = (slot % COLUMNS) as f32 * (CARD_WIDTH + COLUMN_GAP);
                let y = start_y + (slot / COLUMNS) as f32 * (CARD_HEIGHT + ROW_GAP);
                layout.width = layout.width.max(x + CARD_WIDTH);
                layout.height = y + CARD_HEIGHT;
                layout.nodes.push(PlacedNode { source_index, x, y });
            }
        }
        layout.omitted = topology.nodes.len() - layout.nodes.len();
        if topology.edges.is_empty() || layout.nodes.is_empty() {
            return layout;
        }

        let mut indices = HashMap::with_capacity(layout.nodes.len());
        for (index, placed) in layout.nodes.iter().enumerate() {
            indices.insert(topology.nodes[placed.source_index].id.as_str(), Some(index));
        }
        for (source_index, node) in topology.nodes.iter().enumerate() {
            if let Some(index) = indices.get_mut(node.id.as_str()) {
                if index.is_some_and(|i| layout.nodes[i].source_index != source_index) {
                    *index = None;
                }
            }
        }

        let mut seen = HashSet::new();
        for (source_index, edge) in topology.edges.iter().enumerate() {
            let (Some(&Some(source)), Some(&Some(target))) =
                (indices.get(edge.source.as_str()), indices.get(edge.target.as_str()))
            else {
                continue;
            };
            let source_kind = topology.nodes[layout.nodes[source].source_index].kind;
            let target_kind = topology.nodes[layout.nodes[target].source_index].kind;
            if matches!(
                (edge.kind, source_kind, target_kind),
                (TopologyEdgeKind::Owns, Owner, Service)
                    | (TopologyEdgeKind::VerifiedLeader, Service, Leader)
                    | (TopologyEdgeKind::ObservedListener, Service, Listener)
            ) && seen.insert((source, target))
            {
                layout.edges.push(PlacedEdge { source_index, source, target });
            }
        }
        layout
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::snapshot::{TopologyEdge, TopologyNode};
    use TopologyEdgeKind::{ObservedListener, Owns, VerifiedLeader};
    use TopologyNodeKind::{Leader, Listener, Owner, Service, Session};

    fn node(id: &str, kind: TopologyNodeKind) -> TopologyNode {
        TopologyNode {
            id: id.to_owned(),
            kind,
            title: id.to_owned(),
            detail: String::new(),
            service_id: Some("registry-service".to_owned()),
            owner: Some("registry-owner".to_owned()),
            observed_at: None,
            cpu_pct: None,
            mem_mb: None,
        }
    }

    fn edge(source: &str, target: &str, kind: TopologyEdgeKind) -> TopologyEdge {
        TopologyEdge {
            source: source.to_owned(),
            target: target.to_owned(),
            kind,
            observed_at: Some(1.0),
            provenance: "test evidence",
        }
    }

    fn topology(nodes: Vec<TopologyNode>, edges: Vec<TopologyEdge>) -> FleetTopology {
        FleetTopology {
            generated_at: 1.0,
            is_stale: false,
            valid_until: None,
            nodes,
            edges,
            limitations: &[],
        }
    }

    #[test]
    fn orders_cards_in_nonoverlapping_bands() {
        let topology = topology(
            vec![
                node("session", Session),
                node("listener", Listener),
                node("leader", Leader),
                node("owner", Owner),
            ]
            .into_iter()
            .chain((0..5).map(|i| node(&format!("service:{i}"), Service)))
            .collect(),
            vec![],
        );
        let layout = Layout::new(&topology);
        assert_eq!(layout, Layout::new(&topology));
        let sources: Vec<_> = layout.nodes.iter().map(|node| node.source_index).collect();
        assert_eq!(sources, [3, 4, 5, 6, 7, 8, 2, 1, 0]);
        assert!(layout.edges.is_empty());
        assert_eq!(layout.omitted, 0);
        let session = layout.nodes.last().unwrap();
        assert!(
            layout.nodes[..layout.nodes.len() - 1]
                .iter()
                .all(|node| node.y + CARD_HEIGHT < session.y)
        );
        for (index, a) in layout.nodes.iter().enumerate() {
            assert!(a.x >= 0.0 && a.x + CARD_WIDTH <= layout.width);
            assert!(a.y >= 0.0 && a.y + CARD_HEIGHT <= layout.height);
            for b in &layout.nodes[index + 1..] {
                assert!((a.x - b.x).abs() >= CARD_WIDTH || (a.y - b.y).abs() >= CARD_HEIGHT);
            }
        }
    }

    #[test]
    fn places_only_explicit_edges_with_unambiguous_valid_endpoints() {
        let topology = topology(
            vec![
                node("listener", Listener), node("service", Service), node("leader", Leader),
                node("owner", Owner), node("session", Session), node("other-service", Service),
                node("duplicate", Listener), node("duplicate", Listener),
            ],
            vec![
                edge("owner", "service", Owns),
                edge("service", "leader", VerifiedLeader),
                edge("service", "listener", ObservedListener),
                edge("owner", "missing", Owns),
                edge("owner", "session", Owns),
                edge("service", "service", Owns),
                edge("listener", "service", ObservedListener),
                edge("service", "duplicate", ObservedListener),
                edge("owner", "service", Owns),
            ],
        );
        assert_eq!(Layout::new(&topology).edges, [
            PlacedEdge { source_index: 0, source: 0, target: 1 },
            PlacedEdge { source_index: 1, source: 1, target: 3 },
            PlacedEdge { source_index: 2, source: 1, target: 4 },
        ]);
    }

    #[test]
    fn bounds_card_count_and_keeps_sessions_visible() {
        let mut nodes = vec![node("owner", Owner)];
        nodes.extend((0..LIMIT).map(|i| node(&format!("service:{i}"), Service)));
        nodes.push(node("session", Session));
        let topology = topology(nodes, vec![edge("owner", "service:119", Owns)]);
        let layout = Layout::new(&topology);
        assert_eq!(layout.nodes.len(), LIMIT);
        assert_eq!(layout.omitted, 2);
        assert_eq!(layout.nodes.last().unwrap().source_index, topology.nodes.len() - 1);
        assert!(layout.edges.is_empty());
    }
}
