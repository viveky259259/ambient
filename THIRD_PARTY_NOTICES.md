# Third-party notices

## Orb

The Dock glow technique — a click-through window one level below the Dock, the Accessibility
lookup of the Dock's platter, and the feathered mask behind its glass — is adapted from
[Orb](https://github.com/nithish6541/orbdock).

```
MIT License

Copyright (c) 2026 nithish6541

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

## Offline voice (downloaded separately)

The offline voice is not part of Ambient itself. When you choose it, Ambient downloads the `ambient-voice` helper and
the Kokoro model. The helper's zip carries each library's full license under `licenses/`.

| Component | Used for | License | Copyright |
| --- | --- | --- | --- |
| [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M), MLX weights via [prince-canuma/Kokoro-82M](https://huggingface.co/prince-canuma/Kokoro-82M) | The voice model and voices | Apache-2.0 | hexgrad |
| [kokoro-ios](https://github.com/mlalma/kokoro-ios) | Running Kokoro with MLX in Swift | MIT | © 2025 Lassi Maksimainen |
| [MisakiSwift](https://github.com/mlalma/MisakiSwift) | Turning text into phonemes (no espeak) | Apache-2.0 | Lassi Maksimainen |
| [MLXUtilsLibrary](https://github.com/mlalma/MLXUtilsLibrary) | Model file loading | Apache-2.0 | Lassi Maksimainen |
| [MLX Swift](https://github.com/ml-explore/mlx-swift) and [MLX](https://github.com/ml-explore/mlx) | Running the model on Apple silicon | MIT | © 2023 ml-explore, © 2023 Apple Inc. |
| [Swift Numerics](https://github.com/apple/swift-numerics) | Math for MLX | Apache-2.0 | Apple Inc. |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | Reading model archives | MIT | © 2017–2026 Thomas Zoechling |

Apache-2.0 text: https://www.apache.org/licenses/LICENSE-2.0
