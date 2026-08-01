# Enemy Intent AI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace concrete locked enemy action sequences with three public tactical intent phases that dynamically select scored actions from monster-only card pools.

**Architecture:** Typed intent-rating and AI-profile resources extend the existing enemy deck recipes. `EnemyIntentPlan` stores only two primary categories, one fallback category, manifestation information, and forced special actions; `EnemyIntentPlanner` selects categories at lock time and chooses a bounded action sequence at execution time. `TacticalEnemyBehavior` owns the three-stage lifecycle, while chapter rules remain isolated forced actions.

**Tech Stack:** Godot 4.7, statically typed GDScript, Resource-based enemy/card data, headless scene diagnostics.

## Global Constraints

- One enemy turn executes primary intent one, primary intent two, then one fallback intent; after fallback completion the turn ends even when AP remains.
- An intent may play multiple cards, but candidate scoring reads only the rating for the currently executing intent.
- The public plan never stores concrete cards, targets, paths, or predicted damage.
- Monster-only card copies set `reward_eligible = false` and do not depend on player-only resource loops.
- Forced Boss and archetype actions stay outside the three generic intent slots and remain publicly visible.
- Run Godot diagnostics with `--headless --disable-crash-handler --log-file <path> --path D:\py_work\my-deck`; request an unsandboxed run only if AppData or renderer initialization is blocked.
- Do not revert unrelated dirty-worktree changes.

---

### Task 1: Typed Intent Data

**Files:**
- Create: `scripts/enemies/enemy_intent_category.gd`
- Create: `scripts/enemies/enemy_card_intent_rating.gd`
- Create: `scripts/enemies/enemy_ai_profile.gd`
- Modify: `scripts/enemies/enemy_card_pool_entry.gd`
- Modify: `scripts/enemies/enemy_deck_rule.gd`
- Modify: `scripts/enemies/enemy_data.gd`
- Create: `tools/diagnostics/enemy_intent_ai_check.gd`
- Create: `tools/diagnostics/enemy_intent_ai_check.tscn`

**Interfaces:**
- Produces `EnemyIntentCategory.Type` with `APPROACH`, `DEFEND`, `ATTACK`, `UTILITY`, `CURSE`, `RETREAT`, and `HARVEST`.
- Produces `EnemyCardIntentRating.get_score_context()` data for exactly one category.
- Produces `EnemyAIProfile.create_preset(profile_id)` and `EnemyDeckRule.find_tactical_entry(card)`.

- [ ] Add a diagnostic that constructs a multi-label card entry and asserts lookup returns only the requested category rating; run it and verify RED because the classes do not exist.
- [ ] Add the three typed resources, stable card-key matching for runtime card duplicates, and AI-profile presets.
- [ ] Run the diagnostic and require the data tests to pass.

### Task 2: Category-Only Public Plans

**Files:**
- Modify: `scripts/enemies/enemy_intent_plan.gd`
- Modify: `scripts/enemies/enemy_intent_planner.gd`
- Modify: `scripts/enemies/chapter_two_enemy_rules.gd`
- Modify: `scripts/battle/battle_controller.gd`
- Test: `tools/diagnostics/enemy_intent_ai_check.gd`

**Interfaces:**
- `EnemyIntentPlan.configure(primary_one, primary_two, fallback, round_number)` stores categories without card/unit/cell references.
- `EnemyIntentPlan.get_current_category()`, `advance_stage()`, `is_fallback_stage()`, and `finish()` drive execution.
- `forced_steps` stores only chapter/archetype special actions.

- [ ] Extend the diagnostic to assert every generated plan contains two primary categories and one fallback category, exposes no concrete `steps`, and preserves manifestation fields; run RED.
- [ ] Replace concrete plan storage with category stages and move chapter-two special decorators plus champion switching into `forced_steps`.
- [ ] Remove lock-time seen-card disclosure from `BattleController` and run the diagnostic GREEN.

### Task 3: Dynamic Intent Action Search

**Files:**
- Create: `scripts/enemies/enemy_intent_action.gd`
- Modify: `scripts/enemies/enemy_intent_planner.gd`
- Modify: `scripts/enemies/tactical_enemy_behavior.gd`
- Test: `tools/diagnostics/enemy_intent_ai_check.gd`

**Interfaces:**
- `EnemyIntentPlanner.choose_action(controller, unit, category, ap_budget) -> EnemyIntentAction` returns one currently legal action from the current category.
- `EnemyIntentPlanner.has_legal_action(...)` determines stage completion without leaking candidates to UI.
- `TacticalEnemyBehavior` advances stages when no action is legal, enforces the stage-one AP budget, and finishes immediately after fallback exhaustion.

- [ ] Add failing tests for stage-one AP reservation, dynamic replacement after hand changes, backup termination with AP remaining, and multi-label score isolation.
- [ ] Implement card, approach, retreat, harvest, basic-strike, and weapon-switch candidate generation with bounded targets and movement cells.
- [ ] Implement current-category-only scoring using numeric rating fields, target preference, kill bonus, distance, defense need, and combo tags.
- [ ] Implement three-stage execution and run the focused diagnostic GREEN.

### Task 4: AI Profiles and Catalog Assignment

**Files:**
- Modify: `scripts/enemies/chapter_one_enemy_catalog.gd`
- Modify: `scripts/enemies/chapter_two_enemy_catalog.gd`
- Modify: `tools/diagnostics/chapter_one_enemy_check.gd`
- Modify: `tools/diagnostics/chapter_two_enemy_check.gd`
- Test: `tools/diagnostics/enemy_intent_ai_check.gd`

**Interfaces:**
- Catalog specs accept `ai_profile` and optional profile overrides.
- Every generated deck card resolves to at least one `EnemyCardIntentRating`.

- [ ] Add failing assertions that ranged enemies use ranged-control profiles, defensive and berserk archetypes diverge below their health threshold, and all chapter-one/two deck cards have tactical metadata.
- [ ] Assign balanced, ranged-control, low-health-guard, and low-health-berserk profiles by archetype.
- [ ] Add explicit multi-intent ratings and numeric values to common, mutation, military, variant, fixed, and curse entries.
- [ ] Run all three enemy diagnostics GREEN.

### Task 5: Monster-Only Class Card Copies

**Files:**
- Create: `scripts/cards/chapter_one_enemy_class_card_effect.gd`
- Modify: `scripts/enemies/chapter_one_enemy_catalog.gd`
- Modify: `tools/diagnostics/chapter_one_enemy_check.gd`
- Test: `tools/diagnostics/enemy_intent_ai_check.gd`

**Interfaces:**
- Chapter-one class-flavored cards are runtime-independent monster cards with `reward_eligible = false`.
- Simplified cards preserve the approved tactical role without warrior momentum, ranger combo/element inventory, or druid mana/transformation.

- [ ] Record and obtain approval for the simplification mapping before changing these cards.
- [ ] Add a failing diagnostic proving chapter-one enemies no longer reference reward-eligible player class cards.
- [ ] Implement approved monster-only copies and their tactical entries.
- [ ] Run reward-pool, chapter-one, and intent diagnostics GREEN.

### Task 6: Intent UI

**Files:**
- Modify: `scripts/battle/ui/battle_detail_panel.gd`
- Modify: `scripts/battle/battle_map_view.gd`
- Modify: `tools/diagnostics/enemy_intent_ai_check.gd`

**Interfaces:**
- Map badge shows two primary intent labels plus a compact fallback marker.
- Detail panel shows category descriptions and the active stage, never card names, targets, AP allocation, or predicted damage.

- [ ] Add failing string-model assertions for category-only public intent text.
- [ ] Replace concrete-step rendering with category labels and active-stage highlighting.
- [ ] Run the intent diagnostic and battle HUD layout diagnostic GREEN.

### Task 7: Regression Verification and Documentation

**Files:**
- Modify: `non_project_docs/chapter_one_enemy_implementation.md`
- Modify: the project-local enemy/AI maintenance documentation found during implementation
- Verify: all targeted diagnostics

**Interfaces:**
- Documents describe category lock, dynamic execution, tactical metadata ownership, monster-card isolation, and regression traps.

- [ ] Run `enemy_intent_ai_check`, chapter-one, chapter-two, battle-flow, battle-load, HUD-layout, curse, and mutation diagnostics independently.
- [ ] Run a headless editor import/parse check and require exit code 0 with no script parse errors.
- [ ] Inspect the final diff for accidental player-card edits or unrelated UI/resource churn.
- [ ] Update documentation with test commands and the rule that `EnemyCardPoolEntry`, not display text or `CardData.card_type`, is the tactical source of truth.
