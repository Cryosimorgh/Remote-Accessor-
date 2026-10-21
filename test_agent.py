import json
import os
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

import agent


class AgentTests(unittest.TestCase):
    def test_config(self):
        env = {
            "RA_MQTT_HOST": "broker.example.net",
            "RA_MQTT_PORT": "8883",
            "RA_MQTT_USERNAME": "agent",
            "RA_MQTT_PASSWORD": "test-secret",
            "RA_DEVICE_ID": "my_pc-1",
        }
        with patch.dict(os.environ, env, clear=True):
            self.assertEqual(agent.load_config(), ("broker.example.net", 8883, "agent", "test-secret", "my_pc-1"))

    def test_invalid_device_id_cannot_inject_topic(self):
        with patch.dict(os.environ, {"RA_MQTT_HOST": "broker", "RA_MQTT_USERNAME": "u", "RA_MQTT_PASSWORD": "p", "RA_DEVICE_ID": "pc/+/x"}, clear=True):
            with self.assertRaises(ValueError):
                agent.load_config()

    @patch("agent.psutil.cpu_percent", return_value=25.5)
    def test_cpu_request(self, sample):
        client = Mock()
        msg = SimpleNamespace(topic="ra/pc-01/request", retain=False, payload=b"get_cpu")
        agent.handle_message(client, msg, "pc-01")
        sample.assert_called_once_with(interval=0.1)
        topic, response = client.publish.call_args.args
        payload = json.loads(response)
        self.assertEqual(topic, "ra/pc-01/response")
        self.assertEqual(payload["device_id"], "pc-01")
        self.assertEqual(payload["cpu_percent"], 25.5)
        self.assertTrue(payload["timestamp"].endswith("Z"))
        self.assertEqual(client.publish.call_args.kwargs, {"qos": 0, "retain": False})

    def test_main_uses_tls_and_reconnects(self):
        env = {
            "RA_MQTT_HOST": "broker.example.net",
            "RA_MQTT_USERNAME": "agent",
            "RA_MQTT_PASSWORD": "test-secret",
            "RA_DEVICE_ID": "pc-01",
        }
        client = Mock()
        client.subscribe.return_value = (agent.mqtt.MQTT_ERR_SUCCESS, 1)
        with patch.dict(os.environ, env, clear=True), patch.object(agent.mqtt, "Client", return_value=client), patch.object(agent.ssl, "create_default_context") as ctx:
            agent.main()
        self.assertTrue(client.on_connect)
        self.assertTrue(client.on_message)
        client.on_connect(client, None, None, 0, None)
        client.subscribe.assert_called_once_with("ra/pc-01/request", qos=0)
        client.tls_set_context.assert_called_once_with(ctx.return_value)
        client.reconnect_delay_set.assert_called_once_with(min_delay=1, max_delay=60)
        client.connect_async.assert_called_once_with("broker.example.net", 8883, keepalive=60)
        client.loop_forever.assert_called_once_with(retry_first_connection=True)
        client.disconnect.assert_called_once()

    @patch("agent.psutil.cpu_percent")
    def test_ignores_wrong_retained_and_unrecognized_requests(self, sample):
        client = Mock()
        for msg in (
            SimpleNamespace(topic="ra/another-pc/request", retain=False, payload=b"get_cpu"),
            SimpleNamespace(topic="ra/pc-01/request", retain=True, payload=b"get_cpu"),
            SimpleNamespace(topic="ra/pc-01/request", retain=False, payload=b"shutdown"),
            SimpleNamespace(topic="ra/pc-01/request", retain=False, payload=b'{"command":"get_cpu"}'),
        ):
            agent.handle_message(client, msg, "pc-01")
        client.publish.assert_not_called()
        sample.assert_not_called()


if __name__ == "__main__":
    unittest.main()
