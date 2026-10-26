"""Compose the remaining client adapters inside the installer's source transaction."""

from feed_classic_patches import feed_classic_edits, feed_classic_patches
from local_pins_patches import local_pins_edits, local_pins_patches
from navigation_patches import navigation_edits, navigation_patches
from remaining_presentation_patches import (
    remaining_presentation_edits,
    remaining_presentation_patches,
)
from runtime_patches import apply_privacy
from source_patches import SourcePatches
from spy_patches import stage_spy_patches
from visual_effects_patches import visual_effects_edits, visual_effects_patches


def prepare_client_completion_patches(root):
    patches = SourcePatches(root)
    checkpoint = (dict(patches.original), dict(patches.pending), {key: set(value) for key, value in patches.features.items()})
    try:
        apply_privacy(patches)
    except Exception:
        patches.original, patches.pending, patches.features = checkpoint
        raise
    for edits in (feed_classic_edits(), remaining_presentation_edits(), navigation_edits(), visual_effects_edits(), local_pins_edits()):
        for edit in reversed(edits):
            source = patches.read(edit.path)
            if edit.after in edit.before and edit.before in source:
                continue
            if source.count(edit.after) == getattr(edit, "count", 1):
                patches.pending[edit.path] = source.replace(edit.after, edit.before)
    return patches.write()


def apply_client_completion_patches(root):
    patches = SourcePatches(root)
    # Later adapters insert inside earlier anchors. Normalize their exact blocks
    # before reapplying the ordered composition; drift remains a hard error.
    for edits in (feed_classic_edits(), navigation_edits()):
        for edit in reversed(edits):
            source = patches.read(edit.path)
            if source.count(edit.after) == getattr(edit, "count", 1):
                patches.pending[edit.path] = source.replace(edit.after, edit.before)
    stage_spy_patches(patches)
    local_pins_patches(patches)
    visual_effects_patches(patches)
    navigation_patches(patches)
    remaining_presentation_patches(patches)
    feed_classic_patches(patches)
    return patches.write()
