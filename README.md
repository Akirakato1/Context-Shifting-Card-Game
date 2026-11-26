<p align="center"><img src="assets/artwork/logo.png" width="460" alt="Zeitklus: The Cycle of Ages logo"></p>

# Zeitklus: The Cycle of Ages

Zeitklus is a competitive card game where the table cycles through **Rise**, **Flourish**, and **Fall**. Each card has two halves. Flip cards to play the half that fits the current context, then build a hand that earns the most from its ranks, shape, context, and field effects. Play abilities to reshape your hand, turn the context clock, or disrupt an opponent.

![Hand Play in Zeitklus with the score preview above the hand and the ability tray open on the right](docs/images/hand-play.jpg)

## Play

- **Tutorial** teaches the controls, scoring, and abilities in a guided match.
- **Practice** is an offline match with configurable bots and on-demand hints from Zetty.
- **Create Lobby** or **Join Lobby** for online play with up to four players. Share the six-character code with friends or spectators. The host can fill open player seats with bots.

Zeitklus runs on Windows and natively on macOS. To play from source, open `project.godot` in Godot 4.7.2. Online play from source requires the [Godot WebRTC Native extension](https://github.com/godotengine/webrtc-native/releases/tag/1.2.2-stable).

### Practice

In the Practice lobby, click **Avatar** next to **You** to choose your portrait. If a bot has it, you swap portraits. Play against up to three bots, choose their portraits, and set each bot to **Easy**, **Standard**, or **Hard**. Practice defaults to an untimed race to three round wins. Use **Practice Settings** to change the win condition, timers, or ability deck.

During **Hand Play**, click **Zetty** above the score display for your best guaranteed hand, then click again for the play sequence. Card numbers count from the left and update as you sort or move cards. Zetty accounts for sabotage already in effect and recalculates when your hand or available abilities change, including after a random ability resolves. Drag Zetty to move it.

## Credits

Made by **anarchira** and **akts625**. Music by Serjo De Lua (Keys of Moon Music), used with the composer's published permission for games. [The Epic Hero](https://www.youtube.com/watch?v=6wMNM0BjJGM) · [Composer's channel](https://www.youtube.com/@KeysofMoonMusic)

The in-game Credits list the [sound and ambience creators](assets/sound_effects/README.md), [typeface](assets/fonts/mountain_king/ATTRIBUTION.md), and tools used to make Zeitklus. The game code is available under the [MIT License](LICENSE).
