# AGENT_HANDOFF: <slice-id>

Короткая шапка для передачи среза другому исполнителю (человеку или любому AI-агенту). Полный контракт — [TASK_SPEC](TASK_SPEC.md); доказательства — [EVIDENCE](EVIDENCE.md).

- **Task ID / branch:** 
- **Current HEAD (live, `git rev-parse origin/main`):** 
- **Goal (observable result):** 
- **Scope / non-goals:** 
- **Source authority (ADR / spec / config links):** 
- **Impacted stable IDs / files:** 
- **Done so far (commits):** 
- **Acceptance (what must pass):** 
- **Test commands:** `python scripts/validate_work.py` · `python scripts/validate_agent_skills.py` · `python -m unittest discover -s tests -v`
- **Evidence link (PR / CI run):** 
- **Open questions / blockers (with owner = user decision or next slice):** 
- **Next concrete action:** 

Правила: секреты и токены не в repo; `main` не переписывать; destructive и нормативные изменения не мержить без решения пользователя; смена принятого gameplay-правила — через ADR. Исполнитель не закрепляется за моделью.
