import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('preflight',Path(__file__).resolve().parents[1]/'check-secrets.py')
preflight=importlib.util.module_from_spec(spec);spec.loader.exec_module(preflight)

class PreflightTests(unittest.TestCase):
    def test_flags_private_file_without_showing_value(self):
        found=list(preflight.findings('client.json',b'{"client_secret":"' + b'z'*40 + b'"}'))
        self.assertTrue(any(rule=='private-file' for _,_,rule in found))
        self.assertTrue(any(rule=='literal-credential' for _,_,rule in found))
        self.assertNotIn('z'*40,repr(found))
    def test_template_and_test_literals_allowed(self):
        self.assertEqual(list(preflight.findings('example.txt',b'clientSecret="REPLACE_WITH_YOUR_CLIENT_SECRET"')),[])
    def test_connection_key_is_flagged_without_showing_it(self):
        found=list(preflight.findings('unsafe.json',b'{"connection_key":"' + b'a'*64 + b'"}'))
        self.assertTrue(any(rule=='literal-credential' for _,_,rule in found))
        self.assertNotIn('a'*64,repr(found))
    def test_private_key_detected(self):
        key=b'-----BEGIN '+b'PRIVATE KEY-----\nfixture'
        self.assertTrue(list(preflight.findings('unsafe.txt',key)))
    def test_personal_path_detected(self):
        data=b'/'+b'Users/'+b'fixture-name/private/file'
        self.assertTrue(list(preflight.findings('source.swift',data)))
