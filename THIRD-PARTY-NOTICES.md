# Third-Party Notices

Local Flow distributes the following third-party runtime components:

- `whisper.cpp` 1.8.6, MIT License
  <https://github.com/ggml-org/whisper.cpp>
- `ggml` 0.15.1, MIT License
  <https://github.com/ggml-org/ggml>
- LLVM OpenMP runtime (`libomp`), Apache License 2.0 with LLVM Exceptions
  <https://openmp.llvm.org/>

The Whisper model files are not included in the application bundle. Local
Flow downloads the selected model from the official `ggerganov/whisper.cpp`
repository on Hugging Face at revision
`5359861c739e955e79d9a303bcbc70fb988958b1` and verifies its SHA-256 checksum
before use:

<https://huggingface.co/ggerganov/whisper.cpp>

The full `whisper.cpp`, `ggml`, and LLVM OpenMP license texts are copied into
the application bundle during the release build.
