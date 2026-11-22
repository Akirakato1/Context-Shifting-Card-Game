/* Local Figma plugin. Builds reusable controls and one empty design frame. */
const BASE = { width: 1920, height: 1080 };
const palette = {
  page: "#eff2f4", surface: "#e3e8ec", field: "#ffffff", stroke: "#86929c",
  ink: "#26323b", subtle: "#4e5e6b", active: "#cde3ed", focus: "#386487"
};

function componentSpecs() {
  const match = "match/match_screen.tscn";
  const phase = "match/phase_controls.tscn";
  const card = "match/card_widget.tscn";
  const seat = "match/player_seat.tscn";
  const ability = "match/ability_panel.tscn";
  const target = "match/targeting_overlay.tscn";
  const menu = "lobby/main_menu_screen.tscn";
  const lobby = "lobby/lobby_screen.tscn";
  const results = "results/results_screen.tscn";
  const theme = "themes/placeholder_theme.tres";
  const spec = (id, width, height, labels, godot, options = {}) =>
    ({ id, width, height, labels, godot, ...options });
  return {
    Controls: [
      ...["normal", "primary", "hover", "pressed", "focus", "disabled", "selected"].map(state =>
        spec("button_" + state, 226, 60, ["Button label"], theme, { state, slice: 12 })),
      spec("text_field", 320, 62, ["Field value"], menu + " / PlayerName, Code", { fill: "field", slice: 12 }),
      spec("dropdown", 252, 62, ["Selected option", "▾"], lobby + " / Layout/Body/Settings", { fill: "field", slice: 12 }),
      spec("stepper", 210, 60, ["−", "0", "+"], phase + " / StartControls/RequestGrid", { fill: "field", slice: 12 }),
      spec("checkbox", 228, 56, ["□", "Option label"], lobby + " / Layout/Footer/ReadyButton", { fill: "field", slice: 9 }),
      spec("status_badge", 168, 40, ["Status"], seat + " / Info/Status", { slice: 9 }),
      spec("panel_surface", 480, 210, [], "themes/shift_panel.tres", { slice: 24 })
    ],
    Cards: [
      spec("card_frame", 126, 160, [], card, { note: "Place and shape half-card components as your design requires." }),
      spec("card_back", 108, 87, [], card + " / Back"),
      spec("ability_back", 108, 87, [], ability),
      ...["rise", "flourish", "fall", "joker"].map(context =>
        spec("half_" + context, 126, 74, ["Rank / Suit", context === "joker" ? "Joker" : "Context"], card + " / Face")),
      ...["active_half", "hover", "staged", "eligible", "selected", "locked", "disabled"].map(state =>
        spec("card_overlay_" + state, 126, state === "active_half" ? 74 : 160, [], card, {
          fill: null, border: "focus", note: "Export with transparency."
        })),
      ...["manipulation", "field", "buff_nerf", "sabotage"].map(type =>
        spec("ability_" + type, 304, 96, ["Ability name", "Timing / rules"], ability + " / Drawer"))
    ],
    Table: [
      spec("table_playmat", BASE.width, BASE.height, [], match + " / Backdrop", { fill: "page", radius: 0 }),
      spec("seat_nameplate", 321, 152, ["Player name", "Score / readiness"], seat + " / Info", { slice: 18 }),
      spec("phase_tab", 150, 52, ["Phase"], match + " / Header/Phase", { slice: 9 }),
      spec("timer_frame", 124, 55, ["0:00"], match + " / Header/Timer", { slice: 9 }),
      spec("context_clock", 480, 124, ["Current context", "Cycle direction"], match + " / Center/ContextClock"),
      ...["rise", "flourish", "fall"].map(context =>
        spec("pile_" + context, 144, 84, [context, "Remaining"], match + " / Center/Piles", { slice: 10 })),
      spec("field_token", 330, 58, ["Field name / duration"], match + " / Center/Fields", { slice: 10 }),
      spec("reveal_tray", 760, 180, ["Revealed submissions"], seat + " / Hand", { slice: 14 }),
      spec("submission_shelf", 945, 222, ["Submission shelf"], phase + " / HandPlayControls/SubmissionShelf", { slice: 18 }),
      spec("score_preview", 438, 222, ["Score preview", "Base / factors / projected score"], phase + " / HandPlayControls/Preview", { slice: 18 }),
      spec("ability_drawer", 369, 360, ["Abilities"], ability + " / Drawer", { slice: 21 }),
      spec("target_prompt", 540, 225, ["Target prompt", "Choices remaining"], target + " / Panel", { slice: 24 }),
      spec("target_dimmer", BASE.width, BASE.height, [], target + " / Dimmer", { fill: "ink", border: null, radius: 0, alpha: 0.65, export: false }),
      spec("connection_dialog", 672, 258, ["Connection status", "Message / time remaining"], match + " / ConnectionOverlay/Panel", { slice: 24 })
    ],
    Lobby: [
      spec("wordmark_slot", 360, 114, ["Title"], menu + " / Content/Title", { fill: null }),
      spec("room_code", 264, 66, ["Room code"], lobby + " / Layout/Header/RoomCode", { slice: 12 }),
      spec("roster_row", 630, 69, ["Player name / role / status"], lobby + " / Layout/Body/Roster/Players", { slice: 12 }),
      spec("standings_row", 972, 72, ["Rank / player / score / wins"], results + " / Layout/Standings", { slice: 12 })
    ]
  };
}

async function importComponentKit() {
  const font = { family: "Inter", style: "Regular" };
  const bold = { family: "Inter", style: "Semi Bold" };
  await Promise.all([figma.loadFontAsync(font), figma.loadFontAsync(bold)]);
  const originalPage = figma.currentPage;
  const createdPages = [];
  const paint = (name, opacity = 1) => {
    const hex = palette[name];
    const channel = index => parseInt(hex.slice(index, index + 2), 16) / 255;
    return { type: "SOLID", color: { r: channel(1), g: channel(3), b: channel(5) }, opacity };
  };
  function put(node, parent, name, x, y) {
    parent.appendChild(node);
    node.name = name;
    node.x = x;
    node.y = y;
    return node;
  }
  function addText(parent, value, x, y, size, width, title = false) {
    const label = put(figma.createText(), parent, value, x, y);
    label.fontName = title ? bold : font;
    label.fontSize = size;
    label.characters = value;
    label.fills = [paint(title ? "ink" : "subtle")];
    label.textAutoResize = "HEIGHT";
    label.resize(width, label.height);
    return label;
  }
  async function addPage(name) {
    const page = figma.createPage();
    createdPages.push(page);
    page.name = name;
    await figma.setCurrentPageAsync(page);
    return page;
  }
  function createComponent(page, group, part, x, y) {
    const component = put(figma.createComponent(), page, group + "/" + part.id, x, y);
    component.resize(part.width, part.height);
    component.fills = [];
    component.clipsContent = true;
    component.description = [part.godot, part.note, part.slice && "Nine-slice margin " + part.slice + " px at 1×."]
      .filter(Boolean).join("\n");

    const skin = put(figma.createRectangle(), component, "Art · " + part.id, 0, 0);
    const fill = part.fill === undefined ? "surface" : part.fill;
    const border = part.border === undefined ? "stroke" : part.border;
    skin.resize(part.width, part.height);
    skin.constraints = { horizontal: "STRETCH", vertical: "STRETCH" };
    const fillsByState = { primary: "active", hover: "active", pressed: "stroke", selected: "active", disabled: "page" };
    skin.fills = fill ? [paint(fillsByState[part.state] || fill, part.alpha ?? 1)] : [];
    skin.strokes = border ? [paint(part.state === "focus" ? "focus" : border)] : [];
    skin.strokeWeight = part.state === "focus" ? 3 : 1;
    skin.strokeAlign = "INSIDE";
    skin.cornerRadius = part.radius ?? 8;
    if (part.export !== false) skin.exportSettings = [{ format: "PNG", constraint: { type: "SCALE", value: 2 } }];

    const inline = ["dropdown", "stepper", "checkbox"].includes(part.id);
    const fontSize = part.width < 150 ? 14 : 17;
    const textWidth = part.width - 20;
    part.labels.forEach((value, index) => {
      const column = inline ? textWidth / part.labels.length : textWidth;
      const label = addText(component, value, 10 + (inline ? column * index : 0), 10 + (inline ? 0 : index * 24), fontSize, column);
      label.name = "Label / " + value;
      if (!inline) label.constraints = { horizontal: "STRETCH", vertical: "MIN" };
    });
    return component;
  }

  try {
    const library = await addPage("Shift · Components");
    let y = 0;
    let largeY = 0;
    let total = 0;
    for (const [group, parts] of Object.entries(componentSpecs())) {
      addText(library, group, 0, y, 32, 560, true);
      y += 54;
      parts.forEach((part, index) => {
        const x = (index % 4) * 424;
        const rowY = y + Math.floor(index / 4) * 455;
        const large = part.width > 400 || part.height > 300;
        const component = createComponent(library, group, part, large ? 1810 : x, large ? largeY + 42 : rowY + 114);
        addText(library, part.id, x, rowY, 17, 400, true);
        addText(library, part.width + " × " + part.height + " px  ·  " + part.godot, x, rowY + 28, 14, 400);
        if (large) {
          const sample = put(component.createInstance(), library, "Preview / " + part.id, x, rowY + 114);
          const scale = Math.min(400 / part.width, 300 / part.height);
          sample.resize(part.width * scale, part.height * scale);
          addText(library, part.id + "  ·  Full-size master", 1810, largeY, 17, 560, true);
          largeY += part.height + 80;
        }
        total++;
      });
      y += Math.ceil(parts.length / 4) * 455 + 16;
    }
    const canvasPage = await addPage("Shift · Design");
    const canvas = put(figma.createFrame(), canvasPage, "1920 × 1080", 0, 0);
    canvas.resize(BASE.width, BASE.height);
    canvas.fills = [paint("page")];
    canvasPage.selection = [canvas];
    figma.viewport.scrollAndZoomIntoView([canvas]);
    figma.closePlugin("Created " + total + " editable components and one empty 1920 × 1080 frame.");
  } catch (error) {
    await figma.setCurrentPageAsync(originalPage);
    createdPages.reverse().forEach(page => page.remove());
    throw error;
  }
}

if (typeof figma !== "undefined") {
  importComponentKit().catch(error => {
    console.error(error);
    figma.closePlugin("Shift component import failed: " + error.message);
  });
} else if (typeof module !== "undefined") {
  module.exports = { BASE, componentSpecs, importComponentKit };
}
