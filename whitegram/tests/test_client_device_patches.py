import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from client_device_patches import CHAT, LOAD, REQUEST, RECORDING, DEVICE_RUNTIME_FILES, client_device_patches, apply_client_device_patches, _replace
from media_camera_patches import round_camera_choice_patches
from source_patches import SourcePatches
from test_media_camera_patches import errors


class DeviceSourceTests(unittest.TestCase):
    def test_runtime_sources_parse(self):
        for name in DEVICE_RUNTIME_FILES:
            self.assertEqual(errors((ROOT / 'cleanroom' / name).read_text(encoding='utf-8')), [], name)
        for path in (ROOT / 'tests/client_device').glob('*.swift'):
            self.assertEqual(errors(path.read_text(encoding='utf-8')), [], path.name)

    def test_counted_edits_reject_mixed_and_duplicate_sources(self):
        before, after = 'original\n', 'installed\noriginal\n'
        for text in ('', before * 2, after * 2, after + before):
            patches = SourcePatches(ROOT)
            patches.original['fixture'] = patches.pending['fixture'] = text
            with self.subTest(text=text), self.assertRaises(ValueError):
                _replace(patches, 'device', 'fixture', before, after)


@unittest.skipUnless(os.environ.get('WHITEGRAM_ASSEMBLED_SOURCE'), 'Set WHITEGRAM_ASSEMBLED_SOURCE')
class DeviceIntegrationTests(unittest.TestCase):
    def source(self, pristine=False):
        patches = SourcePatches(Path(os.environ['WHITEGRAM_ASSEMBLED_SOURCE']))
        if pristine:
            for path in (CHAT, LOAD, REQUEST, RECORDING):
                text = subprocess.check_output(['git', '-C', str(patches.root), 'show', f'HEAD:{path}']).decode('utf-8')
                patches.original[path] = patches.pending[path] = text
        return patches

    def test_pristine_assembled_and_both_camera_orders_replay(self):
        for pristine in (False, True):
            for camera_first in (False, True):
                patches = self.source(pristine)
                # Load all camera files from HEAD as well in the pristine case.
                from media_camera_patches import RECORDING, ROUND_SCREEN
                if pristine:
                    for path in (RECORDING, ROUND_SCREEN):
                        text = subprocess.check_output(['git', '-C', str(patches.root), 'show', f'HEAD:{path}']).decode('utf-8')
                        patches.original[path] = patches.pending[path] = text
                operations = [round_camera_choice_patches, client_device_patches]
                if not camera_first: operations.reverse()
                for operation in operations: operation(patches)
                once = dict(patches.pending)
                for operation in operations: operation(patches)
                self.assertEqual(once, patches.pending)
                for path, text in once.items():
                    if path.endswith('.swift'): self.assertEqual(errors(text), errors(patches.original[path]), path)
                for path in patches.original:
                    if not pristine: self.assertEqual((patches.root / path).read_text(encoding='utf-8'), patches.original[path])

    def test_device_override_reaches_only_init_connection_device_field(self):
        patches = self.source()
        client_device_patches(patches)
        source = patches.pending[REQUEST]
        self.assertIn('objectForKey:@"wg_fakeDeviceName"', source)
        self.assertIn('isKindOfClass:[NSString class]', source)
        self.assertIn('whitegramDeviceName.length != 0 ? whitegramDeviceName : _apiEnvironment.deviceModel', source)
        self.assertLess(source.index('appendInt32:(int32_t)0xc1cd5ea9'), source.index('id whitegramDeviceObject'))
        self.assertLess(source.index('id whitegramDeviceObject'), source.index('[buffer appendTLString:_apiEnvironment.systemVersion]'))
        self.assertEqual(source.count('[buffer appendTLString:_apiEnvironment.appVersion]'), 1)

    def test_read_action_and_voice_patch_order_is_exact(self):
        from content_control_patches import read_action_patches
        from voice_patches import voice_patches
        for first, second in ((client_device_patches, read_action_patches), (read_action_patches, client_device_patches), (client_device_patches, voice_patches), (voice_patches, client_device_patches)):
            patches = self.source()
            first(patches)
            second(patches)
            once = dict(patches.pending)
            second(patches)
            first(patches)
            self.assertEqual(once, patches.pending)
            self.assertEqual(errors(patches.pending[RECORDING]), errors(patches.original[RECORDING]))

    def test_missing_and_mixed_deferred_hooks_fail_before_write(self):
        base = self.source()
        client_device_patches(base)
        anchor = '            if commit || !isScheduledMessages {\n'
        for source in (base.original[CHAT].replace(anchor, ''), base.original[CHAT] + anchor, base.pending[CHAT] + anchor):
            patches = self.source()
            patches.read(CHAT)
            patches.pending[CHAT] = source
            with patch('client_device_patches.SourcePatches', return_value=patches), patch.object(patches, 'write') as write:
                with self.assertRaises(ValueError): apply_client_device_patches(patches.root)
                write.assert_not_called()

    def test_deferred_path_preserves_enqueue_wrappers_and_native_schedule(self):
        patches = self.source()
        client_device_patches(patches)
        for path in (CHAT, LOAD, RECORDING):
            source = patches.pending[path]
            self.assertIn('WhitegramDeviceDeferredMessages.prepare(messages:', source)
            self.assertIn('whitegramPresentDeferredSend(whitegramDeferredBatch, messageIds: messageIds)', source)
            self.assertEqual(source.count('whitegramEnqueueMessages('), patches.original[path].count('whitegramEnqueueMessages('))
            self.assertEqual(source.count('whitegramReadOnActionSignal()'), patches.original[path].count('whitegramReadOnActionSignal()'))
        core = (ROOT / 'cleanroom/WhitegramDeviceDeferredMessages.swift').read_text(encoding='utf-8')
        self.assertIn('OutgoingScheduleInfoMessageAttribute(scheduleTime: deadline, repeatPeriod: nil)', core)
        self.assertIn('synchronouslyLookupCorrelationId', core)
        self.assertIn('Namespaces.Message.allScheduled.contains(id.namespace)', core)
        self.assertIn('removeIfPossiblyDelivered: false', core)

    def test_missing_device_anchor_fails_before_any_write(self):
        patches = self.source()
        patches.read(REQUEST)
        original = '[buffer appendTLString:_apiEnvironment.deviceModel]'
        installed = '[buffer appendTLString:whitegramDeviceName.length != 0 ? whitegramDeviceName : _apiEnvironment.deviceModel]'
        anchor = installed if installed in patches.pending[REQUEST] else original
        self.assertEqual(patches.pending[REQUEST].count(anchor), 1)
        patches.pending[REQUEST] = patches.pending[REQUEST].replace(anchor, '[buffer appendTLString:@"broken"]')
        with patch('client_device_patches.SourcePatches', return_value=patches), patch.object(patches, 'write') as write:
            with self.assertRaises(ValueError): apply_client_device_patches(patches.root)
            write.assert_not_called()

    def test_real_disk_application_reports_and_replays_in_owned_scratch(self):
        with tempfile.TemporaryDirectory() as temporary:
            scratch = Path(temporary)
            for path in (CHAT, LOAD, REQUEST, RECORDING):
                destination = scratch / path
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes((self.source().root / path).read_bytes())
            report = apply_client_device_patches(scratch)
            before = {path: (scratch / path).read_bytes() for path in (CHAT, LOAD, REQUEST, RECORDING)}
            self.assertEqual(report, {'deferredMessages': sorted([CHAT, LOAD, RECORDING]), 'fakeDeviceName': [REQUEST]})
            self.assertEqual(apply_client_device_patches(scratch), report)
            self.assertEqual(before, {path: (scratch / path).read_bytes() for path in before})
