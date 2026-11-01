─────────────────────────────────────────────────────────────────────────
    @EntryPoint()
    operation RunSafaSensorCNNPipeline() : Unit {

        let nQubits   = 8;
        let dModel    = 8;   // Simulation scale (real: 4096)
        let nShots    = 50;

        Message("=== SafaSensor CNN Pipeline — WebGPU Q# ===");

        let convStack = SafaSensorConvStack();
        Message($"Conv layers: {Length(convStack)}");
        for cfg in convStack {
            let (ic, oc, k, s, name) = cfg!;
            Message($"  {name}: {ic}→{oc} ch, k={k}, s={s}");
        }

        use inputReg   = Qubit[nQubits];
        use weightReg  = Qubit[nQubits];
        use conv1Out   = Qubit[nQubits];
        use conv2Out   = Qubit[nQubits];
        use conv3Out   = Qubit[nQubits];
        use conv4Out   = Qubit[nQubits];
        use poolOut    = Qubit[nQubits];
        use featureVec = Qubit[dModel];

        // Initialize input with sensor data
        ApplyToEach(H, inputReg);
        ApplyToEach(H, weightReg);

        // Layer 1: Conv(8→32, k=7, s=2) + ReLU
        Message("Running Conv1 (7×7, stride=2)...");
        QuantumConv2DLayer(convStack[0], inputReg, weightReg, conv1Out, 0.1);

        // Layer 2: Conv(32→64, k=5, s=2) + ReLU
        Message("Running Conv2 (5×5, stride=2)...");
        QuantumConv2DLayer(convStack[1], conv1Out, weightReg, conv2Out, 0.08);

        // Layer 3: Conv(64→128, k=3, s=1) + ReLU
        Message("Running Conv3 (3×3, stride=1)...");
        QuantumConv2DLayer(convStack[2], conv2Out, weightReg, conv3Out, 0.06);

        // Layer 4: Conv(128→256, k=3, s=1) + ReLU
        Message("Running Conv4 (3×3, stride=1)...");
        QuantumConv2DLayer(convStack[3], conv3Out, weightReg, conv4Out, 0.04);

        // Global Average Pooling
        Message("Running Global Average Pooling...");
        GlobalAveragePooling(conv4Out, poolOut);

        // Linear Projection → d_model
        Message($"Projecting to d_model={dModel}...");
        LinearProjection(poolOut, featureVec, PI() / 4.0);

        // WebGPU shader simulation
        Message("Simulating WebGPU workgroup execution...");
        WGSLShaderSimulation(256, featureVec, featureVec);

        // Measure output feature vector
        let features = MultiM(featureVec);
        Message($"Feature vector: {features}");
        Message($"Output norm (estimated): {Length(features)}");

        ResetAll(inputReg);
        ResetAll(weightReg);
        ResetAll(conv1Out);
        ResetAll(conv2Out);
        ResetAll(conv3Out);
        ResetAll(conv4Out);
        ResetAll(poolOut);
        ResetAll(featureVec);

        Message("=== CNN Pipeline Complete ===");
    }
}
