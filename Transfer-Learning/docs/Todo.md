Transfer-Learning/
├── docs/                    ← Arquitetura + Protocolo WT-MAIA/1.0
├── asm/                     ← AVX-512 (Hamming, Fisher, Gradientes)
├── WebTransporte/
│   ├── clustering/          ← Q# (Hamming, Centroid, Threshold, Novelty)
│   ├── replay/              ← Q# (Buffer PER, Scheduler)
│   ├── webtransport/        ← Q# (QUIC Streams, Sessions, Congestion)
│   ├── continual_learning/  ← Q# (EWC, Majorana Anchor)
│   ├── maia300/             ← Q# (MAIA-300 Node)
│   ├── windows_linux/       ← Q# (Bridge W↔L)
│   ├── automl/              ← Q# (AutoML Controller)
│   ├── autodl/              ← Q# (AutoDL NAS)
│   └── entrypoints/         ← Q# (8 entry points)
├── python/
│   ├── automl/              ← Python + QIR (.ll)
│   ├── autodl/              ← Python
│   ├── graph/               ← QIR (.ll)
│   ├── linux/               ← QIR (.ll)
│   ├── maia300/             ← C# (.cs)
│   ├── replay/              ← C# (.cs)
│   ├── training/            ← C# + C++/CUDA (.cu)
│   ├── transport/           ← C++/CUDA (.cu)
│   └── windows/             ← C++/CUDA (.cu)
├── tests/                   ← Python (clustering, automl, transport)
└── WindowsZenith/           ← AMD Ryzen AI Max+ 395
    ├── hip_rocm/            ← HIP/ROCm (.hip) — gfx1151
    ├── winui3/              ← WinUI 3 (XAML + C#)
    ├── maui/                ← .NET MAUI (C#)
    ├── qsharp/              ← Q# (XDNA 2 + Steane + VQE)
    ├── powershell/          ← PowerShell 7.4+
    ├── tests/               ← Python (planejado; contagem a definir)
    └── docs/                ← Specs AMD oficiais
