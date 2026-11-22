# Shift UI component kit

Open the blank **1920 × 1080** frame on **Shift · Design**. Drag placeholders from the **Assets** panel, or copy instances from **Shift · Components**. Use the component descriptions to find their Godot scenes. Layout, copy and prototype connections are yours to set. [Open Shift in Figma](https://www.figma.com/design/4AGen53itkM3p8K1HaDntH?node-id=1-12)

The library includes controls, card pieces and states, table components, and lobby and results parts. The reference dimensions are editable. The live Godot UI uses a 1920 × 1080 design canvas and scales to the selected window size.

## Texture handoff

- Select the component’s **Art** layer for the 2× PNG export. Keep names such as `card_frame` and `submission_shelf` so the texture can be traced back to the right component.
- Keep names, ranks, scores, timers, and rules in editable label layers. Use alpha for overlays and cutouts. The component description lists nine-slice margins where applicable.
- Share the file with the artist after choosing your screen layout and component dimensions. The [full art checklist](../../docs/art-ui-audio-asset-checklist.md) covers artwork, audio, and effects.

## Attach the textures in Godot

Scene paths in the catalog are relative to `res://src/view/`, with theme resources under `res://themes/`. They identify the existing control or region responsible for each visual. Figma’s sizing gives the artist a reference canvas. Godot’s containers can adjust the actual rectangle for content.

| Texture family | Godot integration point |
| --- | --- |
| Playmat and screen backgrounds | Replace the named `Backdrop` surface with a full-rect `TextureRect`. Preserve mouse passthrough. |
| Menu and results panels | Swap the styles on `MenuSurface` and `ResultsSurface`. `res://themes/shift_panel.tres` is their current shared surface. |
| Buttons, input fields, and choices | Add state-specific `StyleBoxTexture` entries to `res://themes/placeholder_theme.tres`. Keep the control’s text and signals. |
| Match seats and phase panel | Swap the `panel` style override on `PlayerSeat` and `PhaseControls`. |
| Full card, halves, and overlays | Work inside `card_widget.tscn`. Preserve separate half input regions and keep orientation, Joker controls, and targeting bound to the existing card script. |
| Clock, piles, fields, and score preview | Add the skin to the named region in `match_screen.tscn` or `phase_controls.tscn`. Live values stay in the existing labels. |
| Ability drawer, target prompt, and reconnect dialog | Replace each scene’s panel surface. The dim layer is a built-in `ColorRect`. |

Check legibility at the 1280 × 720 window setting and fullscreen. Test both selected and disabled states with the same textures the artist delivers.

## Local installer

To create a fresh kit in another file, import [manifest.json](manifest.json) through Figma Desktop's Development menu and run **Shift UI Component Kit**. This adds a blank design page and a separate component page. If Figma requests a registered plugin ID, copy the ID from a development plugin you created in the desktop app. [Figma’s development plugin import guide](https://help.figma.com/hc/en-us/articles/360042786733-Create-a-classic-plugin-for-development)
