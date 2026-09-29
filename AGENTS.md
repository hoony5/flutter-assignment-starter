# Agent Instructions

## Decision Provider / Agent Routing

- Preserve Korean/user-language source evidence locally. Before sending a bounded semantic decision to Laya, Kev, or Jev/TypeSafe, create an English provider copy of all natural-language `state`, question instructions, choice IDs, and criteria. Preserve structure, facts, code identifiers, numbers, and candidate cardinality; do not summarize or add evidence.
- If a provider packet is non-English, the host GPT/Codex may normalize it exactly once. Revalidate the English packet; if it is still invalid/non-English, fail closed rather than retrying or silently changing semantics.
- Domain callers must use a provider-neutral decision boundary. Do not embed Laya/Kev/Jev SDKs, URLs, API keys, or model IDs in domain workflows. Provider selection belongs in configuration/adapters so implementations can be replaced without changing caller contracts.
- For repository analysis, use exact/source search first, Graft or an existing impact/dependency graph for structural blast radius when available, then deterministic pruning before semantic decisions. Small validated bounded shortlists may use a lightweight local provider such as Kev; larger, long-context, or ambiguous decisions may escalate to Jev. Model confidence never grants execution authority.
- Runtime safety, deployment, deletion, external writes, financial actions, auth/security gates, and other side effects remain deterministic/approval-controlled. Decision models are advisory unless a project-specific tested contract explicitly says otherwise.
- Decision choice cardinality: concrete choices max 4; abstract/overlapping semantic choices max 8. Never send >8 choices to Laya/Kev/Jev; prune, split, or reframe first. Shared use-case/evidence definitions live in the global decision-gateway registry when available.

