"""follow-through :: executable proof for every hook (FT-AC10).

Each gate: a blocking case, a passing case; plus the re-entry guard and malformed input for the
Stop gate, and the dirty/clean split for git in the guard. Every case runs the real script in a
subprocess with an isolated HOME, so the user's config and log are never touched.
Run: python3 -m unittest discover -s follow-through/hooks/tests
"""

import json
import os
import subprocess
import tempfile
import unittest

HOOKS = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


class Env:
    def __init__(self, claude_md="Communicate with me only in Russian or Ukrainian."):
        self.home = tempfile.mkdtemp()
        self.cwd = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.home, ".claude"))
        if claude_md is not None:
            with open(os.path.join(self.home, ".claude", "CLAUDE.md"), "w") as fh:
                fh.write(claude_md)

    def transcript(self, user_text, tools=()):
        path = os.path.join(self.cwd, "t.jsonl")
        with open(path, "w") as fh:
            fh.write(json.dumps({"type": "user", "message": {"role": "user", "content": user_text}}) + "\n")
            for name, data in tools:
                fh.write(json.dumps({"type": "assistant", "message": {"content": [
                    {"type": "tool_use", "name": name, "input": data}]}}) + "\n")
        return path

    def run(self, script, payload, raw=None):
        env = dict(os.environ, HOME=self.home)
        stdin = raw if raw is not None else json.dumps(payload)
        out = subprocess.run(["python3", os.path.join(HOOKS, script)], input=stdin,
                             capture_output=True, text=True, env=env, cwd=self.cwd, timeout=20)
        return out.returncode, out.stdout.strip()

    def stop(self, msg, user="Сделай, пожалуйста, эту задачу целиком.", tools=(), active=False):
        payload = {"session_id": "t", "cwd": self.cwd, "hook_event_name": "Stop",
                   "stop_hook_active": active, "last_assistant_message": msg,
                   "transcript_path": self.transcript(user, tools)}
        return self.run("stop_gate.py", payload)

    def log(self):
        p = os.path.join(self.home, ".claude", "follow-through", "triggers.log")
        if not os.path.exists(p):
            return ""
        with open(p) as fh:
            return fh.read()


RU_OK = "Сделал правку в контроллере и прогнал тесты: 14 из 14 зелёные. Ничего от тебя не нужно, работаю дальше над следующим шагом плана, который мы утвердили утром."


def blocked(out):
    try:
        return json.loads(out).get("decision") == "block"
    except Exception:
        return False


class StopGate(unittest.TestCase):
    def assertBlocks(self, rc_out, gate_word):
        rc, out = rc_out
        self.assertEqual(rc, 0)
        self.assertTrue(blocked(out), out)
        self.assertIn(gate_word, json.loads(out)["reason"])

    def assertPasses(self, rc_out):
        rc, out = rc_out
        self.assertEqual(rc, 0)
        self.assertFalse(blocked(out), out)

    # FT-AC1
    def test_announce_blocks(self):
        self.assertBlocks(Env().stop(RU_OK + "\n\nБеру следующий срез: лимиты тарифов."), "announcement")

    def test_announce_waiting_passes(self):
        self.assertPasses(Env().stop(RU_OK + "\n\nПродолжаю после твоего ответа на вопрос выше."))

    # FT-AC2
    def test_empty_reply_blocks(self):
        self.assertBlocks(Env().stop("No response requested."), "no answer")

    def test_short_user_message_passes(self):
        self.assertPasses(Env().stop("", user="ок"))

    # FT-AC3
    def test_prose_question_blocks(self):
        self.assertBlocks(Env().stop(RU_OK + "\n\nКакой вариант выбираешь, первый или второй?"), "AskUserQuestion")

    def test_question_via_tool_passes(self):
        self.assertPasses(Env().stop(RU_OK + "\n\nКакой вариант выбираешь?", tools=[("AskUserQuestion", {"questions": []})]))

    # FT-AC4
    def test_hand_back_blocks(self):
        self.assertBlocks(Env().stop("Поправил стили карточки товара. Залогинься в админку и пришли скриншот, как оно выглядит теперь у тебя."), "yourself")

    def test_hand_back_with_reason_passes(self):
        self.assertPasses(Env().stop("Поправил конфиг. Запусти это на сервере сам: нет доступа по ssh к проду, ключ есть только у тебя, а команда одна."))

    # FT-AC5
    def test_english_blocks_when_rule_present(self):
        msg = "I changed the controller and ran the whole suite, everything is green now and the endpoint returns the expected payload for every case we discussed this morning."
        self.assertBlocks(Env().stop(msg), "Russian")

    def test_english_passes_without_rule(self):
        msg = "I changed the controller and ran the whole suite, everything is green now and the endpoint returns the expected payload for every case we discussed this morning."
        self.assertPasses(Env(claude_md=None).stop(msg))

    def test_code_does_not_count_as_english(self):
        msg = "Поправил миграцию, вот команда:\n\n```bash\n./vendor/bin/sail artisan migrate --path=database/migrations/2026_10_05_add_index.php && ./vendor/bin/sail artisan test --filter=OrderIndexTest\n```\n\nНичего от тебя не нужно."
        self.assertPasses(Env().stop(msg))

    # FT-AC6
    def test_outbound_dash_list_ids_ai_block(self):
        msg = "Текст для БА:\n\n```outbound BA\nМы проверили — всё ок.\n- поле recipient_id не используется\nЭто сделал AI.\n```\n\nОт тебя: переслать."
        rc, out = Env().stop(msg)
        reason = json.loads(out)["reason"]
        for word in ("«—»", "list", "recipient_id", "AI"):
            self.assertIn(word, reason)

    def test_outbound_negative_claim_needs_source(self):
        msg = "```outbound client\nВыписать документ с нулевой суммой нельзя.\n```\nОт тебя: переслать."
        self.assertBlocks(Env().stop(msg), "source")

    def test_outbound_clean_passes(self):
        msg = "```outbound client\nДобрый день. Экспорт заказов возможно реализовать, сроки пришлю завтра после проверки.\n```\nОт тебя: переслать клиенту."
        self.assertPasses(Env().stop(msg))

    def test_outbound_lists_option(self):
        msg = "```outbound BA lists\n- первый пункт\n- второй пункт\n```\nОт тебя: переслать."
        self.assertPasses(Env().stop(msg))

    # FT-AC7
    def test_ui_claim_without_screenshot_blocks(self):
        tools = [("Edit", {"file_path": "/p/resources/views/admin/product.blade.php"})]
        self.assertBlocks(Env().stop("Готово, карточка товара теперь выровнена. Ничего от тебя не нужно.", tools=tools), "screenshot")

    def test_ui_claim_with_screenshot_passes(self):
        tools = [("Edit", {"file_path": "/p/resources/css/admin.css"}),
                 ("mcp__Claude_Browser__computer", {"action": "screenshot"})]
        self.assertPasses(Env().stop("Готово, карточка товара теперь выровнена. Ничего от тебя не нужно.", tools=tools))

    def test_screenshot_before_edit_does_not_count(self):
        tools = [("mcp__Claude_Browser__computer", {"action": "screenshot"}),
                 ("Edit", {"file_path": "/p/src/App.tsx"})]
        self.assertBlocks(Env().stop("Исправил, теперь работает. Ничего от тебя не нужно.", tools=tools), "screenshot")

    def test_ui_unverified_line_passes(self):
        tools = [("Edit", {"file_path": "/p/src/App.vue"})]
        self.assertPasses(Env().stop("Сделал правку.\nUI не проверен: экран корзины — нет браузерного инструмента в сессии.", tools=tools))

    def test_test_file_is_not_ui(self):
        tools = [("Edit", {"file_path": "/p/src/__tests__/App.test.tsx"})]
        self.assertPasses(Env().stop("Готово, тест исправлен. Ничего от тебя не нужно.", tools=tools))

    # guard rails
    def test_reentry_is_silent(self):
        self.assertPasses(Env().stop("Беру следующий срез.", active=True))

    def test_malformed_input_is_silent(self):
        rc, out = Env().run("stop_gate.py", None, raw="{not json")
        self.assertEqual((rc, out), (0, ""))

    def test_missing_transcript_is_safe(self):
        env = Env()
        rc, out = env.run("stop_gate.py", {"cwd": env.cwd, "last_assistant_message": RU_OK, "transcript_path": "/nope"})
        self.assertEqual(rc, 0)
        self.assertFalse(blocked(out))

    def test_gate_can_be_switched_off(self):
        env = Env()
        os.makedirs(os.path.join(env.cwd, ".claude"))
        with open(os.path.join(env.cwd, ".claude", "follow-through.json"), "w") as fh:
            json.dump({"gates": {"announce_stop": False}}, fh)
        self.assertPasses(env.stop(RU_OK + "\n\nБеру следующий срез."))

    def test_trigger_is_logged(self):
        env = Env()
        env.stop(RU_OK + "\n\nБеру следующий срез.")
        self.assertIn("announce_stop", env.log())


class Guard(unittest.TestCase):
    def run_bash(self, env, cmd):
        return env.run("guard.py", {"cwd": env.cwd, "tool_name": "Bash", "tool_input": {"command": cmd}})

    def asks(self, rc_out):
        rc, out = rc_out
        self.assertEqual(rc, 0)
        return bool(out) and json.loads(out)["hookSpecificOutput"]["permissionDecision"] == "ask"

    def git_repo(self, dirty):
        env = Env()
        subprocess.run(["git", "init", "-q", env.cwd], check=True)
        with open(os.path.join(env.cwd, "a.txt"), "w") as fh:
            fh.write("1")
        subprocess.run(["git", "-C", env.cwd, "add", "."], check=True)
        subprocess.run(["git", "-C", env.cwd, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "x"], check=True)
        if dirty:
            with open(os.path.join(env.cwd, "a.txt"), "w") as fh:
                fh.write("2")
        return env

    def test_migrate_fresh_asks(self):
        self.assertTrue(self.asks(self.run_bash(Env(), "./vendor/bin/sail artisan migrate:fresh --seed")))

    def test_migrate_fresh_testing_passes(self):
        self.assertFalse(self.asks(self.run_bash(Env(), "./vendor/bin/sail artisan migrate:fresh --env=testing")))

    def test_plain_migrate_passes(self):
        self.assertFalse(self.asks(self.run_bash(Env(), "./vendor/bin/sail artisan migrate")))

    def test_drop_table_via_client_asks(self):
        self.assertTrue(self.asks(self.run_bash(Env(), "mysql -e 'DROP TABLE orders'")))

    def test_grep_for_drop_passes(self):
        self.assertFalse(self.asks(self.run_bash(Env(), "grep -rn 'DROP TABLE' database/")))

    def test_checkout_file_dirty_asks(self):
        self.assertTrue(self.asks(self.run_bash(self.git_repo(True), "git checkout -- a.txt")))

    def test_checkout_file_clean_passes(self):
        self.assertFalse(self.asks(self.run_bash(self.git_repo(False), "git checkout -- a.txt")))

    def test_restore_staged_passes(self):
        self.assertFalse(self.asks(self.run_bash(self.git_repo(True), "git restore --staged a.txt")))

    def test_reset_hard_dirty_asks(self):
        self.assertTrue(self.asks(self.run_bash(self.git_repo(True), "git reset --hard HEAD")))

    def test_branch_switch_passes(self):
        self.assertFalse(self.asks(self.run_bash(self.git_repo(True), "git checkout -b feature/x")))

    def test_docker_volumes_ask(self):
        self.assertTrue(self.asks(self.run_bash(Env(), "docker compose down -v")))

    def test_docker_down_passes(self):
        self.assertFalse(self.asks(self.run_bash(Env(), "docker compose down")))

    def test_kill_asks(self):
        self.assertTrue(self.asks(self.run_bash(Env(), "./vendor/bin/sail artisan horizon:terminate")))
        self.assertTrue(self.asks(self.run_bash(Env(), "pkill -f vite")))

    def test_gate_config_edit_asks(self):
        env = Env()
        rc_out = env.run("guard.py", {"cwd": env.cwd, "tool_name": "Edit",
                                      "tool_input": {"file_path": "/p/.company-sdd.json"}})
        self.assertTrue(self.asks(rc_out))

    def test_gate_config_shell_write_asks(self):
        self.assertTrue(self.asks(self.run_bash(Env(), "sed -i '' 's/true/false/' .groundwork.json")))

    def test_gate_config_read_with_redirect_passes(self):
        self.assertFalse(self.asks(self.run_bash(Env(), "ls -la .claude/ 2>&1 | head; cat .groundwork.json 2>/dev/null")))

    def test_gate_config_read_passes(self):
        self.assertFalse(self.asks(self.run_bash(Env(), "cat .groundwork.json")))

    def test_ordinary_edit_passes(self):
        env = Env()
        rc_out = env.run("guard.py", {"cwd": env.cwd, "tool_name": "Edit",
                                      "tool_input": {"file_path": "/p/app/Http/Controllers/OrderController.php"}})
        self.assertFalse(self.asks(rc_out))

    def test_malformed_input_is_silent(self):
        rc, out = Env().run("guard.py", None, raw="garbage")
        self.assertEqual((rc, out), (0, ""))


class SessionStart(unittest.TestCase):
    def test_rules_are_injected(self):
        rc, out = Env().run("session_start.py", {"hook_event_name": "SessionStart"})
        self.assertEqual(rc, 0)
        self.assertIn("```outbound", json.loads(out)["hookSpecificOutput"]["additionalContext"])


if __name__ == "__main__":
    unittest.main()
