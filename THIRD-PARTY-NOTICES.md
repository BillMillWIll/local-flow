# Third-Party Notices

Local Flow distributes the following third-party runtime components:

- `whisper.cpp` 1.9.2 (`whisper-cli`, `parakeet-cli`, `libwhisper`,
  `libparakeet`), MIT License
  <https://github.com/ggml-org/whisper.cpp>
- `ggml` 0.20.0 including its Metal, CPU and BLAS backends, MIT License
  <https://github.com/ggml-org/ggml>
- LLVM OpenMP runtime (`libomp`), Apache License 2.0 with LLVM Exceptions
  <https://openmp.llvm.org/>

Model files are not included in the application bundle. Depending on the
selected engine, Local Flow downloads them once at a pinned repository
revision and verifies the SHA-256 checksum before use:

- Whisper Large v3 Turbo (`ggml-large-v3-turbo-q5_0.bin`), MIT License,
  from `ggerganov/whisper.cpp` at revision
  `5359861c739e955e79d9a303bcbc70fb988958b1`
  <https://huggingface.co/ggerganov/whisper.cpp>
- Silero VAD v5.1.2 (`ggml-silero-v5.1.2.bin`), MIT License,
  from `ggml-org/whisper-vad` at revision
  `9ffd54a1e1ee413ddf265af9913beaf518d1639b`
  <https://huggingface.co/ggml-org/whisper-vad>
- NVIDIA Parakeet TDT 0.6B v3 (`ggml-parakeet-tdt-0.6b-v3-q8_0.bin`),
  CC-BY-4.0, converted by `ggml-org/parakeet-GGUF` at revision
  `35156454d1a39de06863303dd209fd2bed6ee079`
  <https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3>
  <https://huggingface.co/ggml-org/parakeet-GGUF>

The Apple engine uses the speech recognition and language model assets that
macOS 26 manages itself; Local Flow does not distribute them.

The full `whisper.cpp`, `ggml`, and LLVM OpenMP license texts are copied into
the application bundle during the release build.
