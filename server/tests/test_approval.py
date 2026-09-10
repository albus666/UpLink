from __future__ import annotations

import unittest

from app.approval import check_tool_call


def _shell(command: str) -> dict:
    return {"shellToolCall": {"args": {"command": command}}}


def _read(path: str) -> dict:
    return {"readToolCall": {"args": {"path": path}}}


def _write(path: str) -> dict:
    return {"writeToolCall": {"args": {"path": path}}}


class ApprovalTests(unittest.TestCase):
    def test_readonly_status_query_is_not_sensitive(self) -> None:
        command = (
            "ss -tlnp | rg '4399|80|8080' || true; ls -lh /home/ubuntu/apps/; "
            "ip -4 addr show | rg 'inet '; curl -s ifconfig.me 2>/dev/null || "
            "curl -s icanhazip.com 2>/dev/null; echo; ls /etc/nginx/sites-enabled 2>/dev/null; "
            "systemctl is-active nginx 2>/dev/null; which python3 node 2>/dev/null"
        )
        self.assertFalse(check_tool_call(_shell(command)).sensitive)

    def test_readonly_service_and_config_queries(self) -> None:
        for command in (
            "systemctl status nginx",
            "systemctl is-enabled uplink",
            "nginx -t",
            "cat /etc/nginx/nginx.conf",
            "ls /etc/systemd/system",
            "ufw status",
            "iptables -L -n",
            "journalctl -u nginx -n 20",
        ):
            self.assertFalse(check_tool_call(_shell(command)).sensitive, command)

    def test_mutating_system_commands_are_sensitive(self) -> None:
        for command in (
            "systemctl restart nginx",
            "sudo systemctl reload nginx",
            "nginx -s reload",
            "ufw allow 8080",
            "iptables -A INPUT -p tcp --dport 80 -j ACCEPT",
            "reboot",
            "echo ok > /etc/nginx/sites-enabled/app",
            "chmod 777 /etc/ssh/sshd_config",
        ):
            self.assertTrue(check_tool_call(_shell(command)).sensitive, command)

    def test_secret_reads_are_sensitive(self) -> None:
        self.assertTrue(check_tool_call(_shell("cat /home/ubuntu/.env")).sensitive)
        self.assertTrue(check_tool_call(_read("/opt/uplink/server/.env")).sensitive)
        self.assertTrue(check_tool_call(_shell("cat ~/.ssh/id_ed25519")).sensitive)

    def test_workspace_write_is_not_sensitive(self) -> None:
        self.assertFalse(check_tool_call(_write("/opt/uplink/workspace/README.md")).sensitive)
        self.assertTrue(check_tool_call(_write("/etc/nginx/nginx.conf")).sensitive)


if __name__ == "__main__":
    unittest.main()
