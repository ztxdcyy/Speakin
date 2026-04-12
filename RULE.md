Based on everything we've covered, here are the three most important principles:

---

发布流程：

1. 推送代码到远端仓库，判断本次改动是否足以发布一个新版本，如果可以，打上一个tag。
2. 编译产物，推送到GitHub/release，保持简洁。
3. 根据本次更改内容更新 changelog和readme。

严格遵循流程：提问 → Plan → Action → Check

在完成任务后，需要 AI 来执行 make run。确认完成编译且没有问题之后等待人工测试。

在开发过程中可以适量添加 flag 以及 debug 语句方便定位问题，也可以记录 log 到 logs 文件夹或者 tmp 文件夹。

善于搜索网络，优先搜索开发者文档！！！

## Principle 1: Persist Progress to the Filesystem, Not the Context Window

**Core action:** Force artifact writes before every session ends.

Maintain three types of files:

- `progress.txt` (free-form text): what was done, where it got stuck, what comes next
- `features.json` (structured): feature status tracking — Agents may only update the `status` field, never rewrite the whole file
- `git log`: a natural audit trail of every decision

**Why it's critical:** Your project will inevitably span multiple sessions. Without this, every Agent starts by guessing the current state — and either duplicates work or declares the project done prematurely. Anthropic and OpenAI independently converged on the same conclusion.

---

## Principle 2: Separate Thinking from Execution — Validate the Plan Before Any Code is Written

**Core action:** For complex tasks, enforce a two-phase workflow. The planning phase must produce a reviewable artifact before execution begins.

Small changes can go straight to execution. But any task touching multiple files, crossing module boundaries, or involving architectural decisions requires a written plan first. Human confirms the direction, then the Agent proceeds.

**Why it's critical:** Reviewing a 20-line plan takes 5 minutes. Reviewing 500 lines of generated code takes 30 — and by then you're psychologically reluctant to throw it away. The planning phase is the cheapest error-correction window you have. When the spec is right, the implementation follows naturally. When the spec is wrong, you catch it before 500 lines are generated.

---

## Principle 3: Encode Rules into the Environment, Not into the Prompt

**Core action:** Architectural constraints must have machine-executable expressions — linters, CI checks, structural tests — not just written descriptions.

Written rules ("please follow layered architecture") get ignored. Machine rules (a linter that detects a dependency violation, then injects the error message directly into the Agent's context as a correction signal) must be responded to.

OpenAI's approach: the dependency direction `Types → Config → Repo → Service → Runtime → UI` is enforced mechanically by a linter. Any violation triggers an automatic repair loop.

**Why it's critical:** Agents drift over long-running projects, gradually replicating whatever patterns already exist in the codebase — including bad ones. Only machine-executable constraints resist this entropy. Documentation is for humans. Rules are for the environment.

---

## How the Three Relate

```
Principle 3 (environment constraints) → guarantees quality at each step
Principle 2 (plan validation)         → guarantees correctness of direction
Principle 1 (progress persistence)    → guarantees continuity across sessions
```

Remove any one of the three, and an engineering-grade project will break down at some point.
