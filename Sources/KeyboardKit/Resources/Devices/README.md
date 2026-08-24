# Device profiles

One JSON file per keyboard model. Adding a keyboard means adding a file here —
no Swift changes.

| Field | Meaning |
|---|---|
| `id` | slug, also the filename |
| `vendorID` / `productIDs` | USB ids, decimal. Tri-mode boards may enumerate under several product ids — list them all |
| `family` | wire protocol. `royuan` covers Attack Shark, Epomaker, Akko, Hator, ikbc, NOPPOO, MEETION |
| `layout` | file under `Layouts/`, without extension. Omit if the board has no drawn layout yet |
| `capabilities.lighting` | `whole`, `zones`, `perKey` or `none` |
| `capabilities.screen` | omit when there is no screen |
| `capabilities.screen.verified` | `true` only when the resolution was confirmed on real hardware. A datasheet or another project's constant is not confirmation — the ROYUAN protocol reports "ready" for any frame size, so the panel cannot be asked |

To find your board's ids on macOS:

```sh
ioreg -p IOUSB -l -w 0 | grep -iE '"USB Product Name"|idVendor|idProduct'
```

Then run `kstudio probe` and `kstudio measure` to check what the board answers.
