# Third-party notices

Switchyard is inspired by [jdsimcoe/dia-router](https://github.com/jdsimcoe/dia-router), and two small pieces of it are adapted from that project (as of commit [`44bb00f`](https://github.com/jdsimcoe/dia-router/tree/44bb00f2654797fee78ddddeca396f41a99e7e93)):

| Switchyard file | Adapted from | What |
| --- | --- | --- |
| `Sources/RouterCore/ChromiumLocalState.swift` | `Sources/DiaRouter/DiaProfileState.swift` | Decoding Dia's Chromium `Local State` file (the `info_cache` structure and file path) and sorting the profiles it lists |
| `scripts/build-app.sh` | `scripts/build-app.sh` | Automatically finding an Apple Development signing identity, the `signing.local.zsh` override, and the fallback to ad-hoc signing |

Those portions are used under the following license:

```
MIT License

Copyright (c) 2026 Jonathan Simcoe

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
