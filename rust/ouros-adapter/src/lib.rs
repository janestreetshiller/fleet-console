//! Ouros-X brain adapter compatibility and bridge module.
//!
//! Ingests:
//! - Agent task graphs and state machine transitions
//! - Context memory allocation vs system RAM
//! - Token budgets and consumption velocity
//! - Decision logs and rationales
//! - Unmanaged service triggers

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AgentState {
    Idle,
    Reasoning,
    ToolExecution,
    AwaitingInput,
    Suspended,
    Terminated,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContextMemoryAllocation {
    pub total_tokens: u64,
    pub max_context_tokens: u64,
    pub prompt_cache_bytes: u64,
    pub working_heap_bytes: u64,
    pub memory_lock_ratio: f32,
}

impl ContextMemoryAllocation {
    pub fn utilization_ratio(&self) -> f32 {
        if self.max_context_tokens == 0 {
            0.0
        } else {
            (self.total_tokens as f32 / self.max_context_tokens as f32).min(1.0)
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TokenBudget {
    pub total_allocated: u64,
    pub consumed: u64,
    pub tokens_per_second: f32,
    pub unit_cost_micro_cents: u64,
}

impl TokenBudget {
    pub fn remaining(&self) -> u64 {
        self.total_allocated.saturating_sub(self.consumed)
    }

    pub fn percent_used(&self) -> f32 {
        if self.total_allocated == 0 {
            100.0
        } else {
            ((self.consumed as f64 / self.total_allocated as f64) * 100.0) as f32
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DecisionChoice {
    pub option: String,
    pub confidence: f32,
    pub rationale: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DecisionNode {
    pub id: String,
    pub agent_id: String,
    pub timestamp_seconds: f64,
    pub goal: String,
    pub chosen_action: String,
    pub confidence: f32,
    pub alternatives: Vec<DecisionChoice>,
    pub invoked_tool: Option<String>,
    pub latency_ms: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UnmanagedServiceTrigger {
    pub trigger_id: String,
    pub service_name: String,
    pub target_executable: String,
    pub pid: Option<u32>,
    pub listening_socket: Option<String>,
    pub rollback_command: Option<String>,
    pub triggered_by_agent: String,
    pub is_active: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AgentTaskNode {
    pub task_id: String,
    pub name: String,
    pub agent_type: String,
    pub state: AgentState,
    pub active_pid: Option<u32>,
    pub context_memory: ContextMemoryAllocation,
    pub token_budget: TokenBudget,
    pub current_goal: String,
    pub recent_decisions: Vec<DecisionNode>,
    pub listening_socket: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AgentTaskEdge {
    pub source_task_id: String,
    pub target_task_id: String,
    pub relation: String, // "Subagent", "Dependency", "IpcChannel", "DataFlow"
    pub throughput_messages_sec: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AgentTaskGraph {
    pub nodes: HashMap<String, AgentTaskNode>,
    pub edges: Vec<AgentTaskEdge>,
    pub unmanaged_triggers: Vec<UnmanagedServiceTrigger>,
}

impl Default for AgentTaskGraph {
    fn default() -> Self {
        Self {
            nodes: HashMap::new(),
            edges: Vec::new(),
            unmanaged_triggers: Vec::new(),
        }
    }
}

/// Ingestion interface for communicating with the Ouros-X brain adapter.
pub trait OurosAdapter: Send + Sync {
    fn poll_task_graph(&mut self) -> Result<AgentTaskGraph, String>;
    fn trigger_remediation(
        &mut self,
        target_id: &str,
        action: &str,
    ) -> Result<String, String>;
    fn stream_logs(&self, agent_id: &str) -> Vec<String>;
}

/// Standard bridge module maintaining active state from Ouros-X runtime.
pub struct OurosBrainBridge {
    active_graph: AgentTaskGraph,
    log_cache: HashMap<String, Vec<String>>,
}

impl OurosBrainBridge {
    pub fn new() -> Self {
        let mut bridge = Self {
            active_graph: AgentTaskGraph::default(),
            log_cache: HashMap::new(),
        };
        bridge.load_default_topology();
        bridge
    }

    fn load_default_topology(&mut self) {
        let mut nodes = HashMap::new();

        nodes.insert(
            "ouros-core".to_string(),
            AgentTaskNode {
                task_id: "ouros-core".to_string(),
                name: "Ouros Core Brain".to_string(),
                agent_type: "Coordinator".to_string(),
                state: AgentState::Reasoning,
                active_pid: Some(1001),
                context_memory: ContextMemoryAllocation {
                    total_tokens: 48_500,
                    max_context_tokens: 128_000,
                    prompt_cache_bytes: 384 * 1024 * 1024,
                    working_heap_bytes: 850 * 1024 * 1024,
                    memory_lock_ratio: 0.38,
                },
                token_budget: TokenBudget {
                    total_allocated: 500_000,
                    consumed: 142_300,
                    tokens_per_second: 32.5,
                    unit_cost_micro_cents: 15,
                },
                current_goal: "Evaluating spatial mapping layout and system resource topology".to_string(),
                recent_decisions: vec![DecisionNode {
                    id: "dec-001".to_string(),
                    agent_id: "ouros-core".to_string(),
                    timestamp_seconds: 1770000000.0,
                    goal: "Resolve memory pressure on swift-frontend".to_string(),
                    chosen_action: "Throttle context caching and trigger GC".to_string(),
                    confidence: 0.94,
                    alternatives: vec![
                        DecisionChoice {
                            option: "Kill process immediately".to_string(),
                            confidence: 0.42,
                            rationale: "Causes loss of uncommitted Swift build state".to_string(),
                        },
                        DecisionChoice {
                            option: "Throttle context caching".to_string(),
                            confidence: 0.94,
                            rationale: "Relieves RSS without breaking IPC sockets".to_string(),
                        },
                    ],
                    invoked_tool: Some("caching_throttle".to_string()),
                    latency_ms: 128,
                }],
                listening_socket: Some("127.0.0.1:50139".to_string()),
            },
        );

        nodes.insert(
            "codex-worker".to_string(),
            AgentTaskNode {
                task_id: "codex-worker".to_string(),
                name: "Codex Code Synthesis".to_string(),
                agent_type: "Coder".to_string(),
                state: AgentState::ToolExecution,
                active_pid: Some(1002),
                context_memory: ContextMemoryAllocation {
                    total_tokens: 92_000,
                    max_context_tokens: 200_000,
                    prompt_cache_bytes: 512 * 1024 * 1024,
                    working_heap_bytes: 420 * 1024 * 1024,
                    memory_lock_ratio: 0.46,
                },
                token_budget: TokenBudget {
                    total_allocated: 1_000_000,
                    consumed: 388_400,
                    tokens_per_second: 54.0,
                    unit_cost_micro_cents: 10,
                },
                current_goal: "Writing GPUI spatial mapping views".to_string(),
                recent_decisions: vec![],
                listening_socket: Some("127.0.0.1:60165".to_string()),
            },
        );

        let edges = vec![AgentTaskEdge {
            source_task_id: "ouros-core".to_string(),
            target_task_id: "codex-worker".to_string(),
            relation: "IPC Stream / Subagent".to_string(),
            throughput_messages_sec: 18.2,
        }];

        let unmanaged_triggers = vec![UnmanagedServiceTrigger {
            trigger_id: "trig-sys-frontend".to_string(),
            service_name: "swift-frontend-watchdog".to_string(),
            target_executable: "/usr/bin/swift-frontend".to_string(),
            pid: Some(1004),
            listening_socket: None,
            rollback_command: Some("kill -STOP 1004".to_string()),
            triggered_by_agent: "ouros-core".to_string(),
            is_active: true,
        }];

        self.active_graph = AgentTaskGraph {
            nodes,
            edges,
            unmanaged_triggers,
        };

        self.log_cache.insert(
            "ouros-core".to_string(),
            vec![
                "[19:00:01] [Ouros-Core] Session initialized on socket :50139".to_string(),
                "[19:00:03] [Ouros-Core] Connecting to local telemetry provider".to_string(),
                "[19:00:05] [Ouros-Core] Spawned worker codex-worker on :60165".to_string(),
                "[19:00:12] [Ouros-Core] Spatial topology plane synced".to_string(),
            ],
        );
    }
}

impl Default for OurosBrainBridge {
    fn default() -> Self {
        Self::new()
    }
}

impl OurosAdapter for OurosBrainBridge {
    fn poll_task_graph(&mut self) -> Result<AgentTaskGraph, String> {
        Ok(self.active_graph.clone())
    }

    fn trigger_remediation(
        &mut self,
        target_id: &str,
        action: &str,
    ) -> Result<String, String> {
        match action {
            "ThrottleAgent" => {
                if let Some(node) = self.active_graph.nodes.get_mut(target_id) {
                    node.state = AgentState::Suspended;
                    return Ok(format!("Agent {target_id} throttled to Suspended state"));
                }
                Err(format!("Agent {target_id} not found"))
            }
            "CompactContext" => {
                if let Some(node) = self.active_graph.nodes.get_mut(target_id) {
                    node.context_memory.total_tokens /= 2;
                    node.context_memory.prompt_cache_bytes /= 2;
                    return Ok(format!("Context compacted for {target_id}"));
                }
                Err(format!("Agent {target_id} not found"))
            }
            _ => Ok(format!("Remediation {action} dispatched to {target_id}")),
        }
    }

    fn stream_logs(&self, agent_id: &str) -> Vec<String> {
        self.log_cache
            .get(agent_id)
            .cloned()
            .unwrap_or_else(|| vec![format!("[{agent_id}] No active log streams.")])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_adapter_topology() {
        let mut bridge = OurosBrainBridge::new();
        let graph = bridge.poll_task_graph().expect("graph poll failed");
        assert_eq!(graph.nodes.len(), 2);
        assert_eq!(graph.edges.len(), 1);
        assert_eq!(graph.unmanaged_triggers.len(), 1);

        let remediation = bridge
            .trigger_remediation("ouros-core", "CompactContext")
            .unwrap();
        assert!(remediation.contains("compacted"));
    }
}
