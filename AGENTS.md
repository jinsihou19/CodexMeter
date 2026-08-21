## 1. 提交须知

提交消息使用 Conventional Commits 格式：

```text
type(scope): subject
```

常用类型：

- `feat`：新特性
- `fix`：问题修复
- `docs`：文档修改
- `style`：格式调整，不改变逻辑
- `refactor`：重构
- `test`：测试相关
- `chore`：构建、脚本、维护任务
- `revert`：回滚

提交信息中不要出现 `Co-Authored-By` 等 AI 署名。
不要在改动之后自动提交，需要用户确认或者明确说提交相关的指令才能提交。

## 2. 代码规范

1. 新增或明显调整类时，写类注释，说明职责、使用边界和关键协作对象。
2. 新增或明显调整关键方法时，写方法注释，说明职责、参数约束、返回语义和异常场景。
3. 注释要解释业务意图、设计约束和不明显的取舍，不要写“给字段赋值”这类重复代码表面的注释。
4. 全部的函数和文件都需要中文注释。


## 3. 开发规范
修改完代码需要安装并测试

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **codex用量组件** (4414 symbols, 10526 relationships, 222 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> Index stale? Run `node .gitnexus/run.cjs analyze` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? `npx gitnexus analyze` (npm 11 crash → `npm i -g gitnexus`; #1939).

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows. For regression review, compare against the default branch: `detect_changes({scope: "compare", base_ref: "main"})`.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit changes without running `detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/codex用量组件/context` | Codebase overview, check index freshness |
| `gitnexus://repo/codex用量组件/clusters` | All functional areas |
| `gitnexus://repo/codex用量组件/processes` | All execution flows |
| `gitnexus://repo/codex用量组件/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
