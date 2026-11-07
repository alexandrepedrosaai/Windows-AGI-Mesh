# Benchmarks

## 15 Benchmark Cases

| Case | Qubits | Shots | Backend | Expected Mean |
|---|---|---|---|---|
| case_01 | 1 | 100 | simulator | [0.3, 0.7] |
| case_02 | 2 | 200 | simulator | [0.3, 0.7] |
| case_03 | 4 | 500 | simulator | [0.3, 0.7] |
| case_04 | 8 | 1000 | simulator | [0.3, 0.7] |
| case_05 | 4 | 100 | microsoft.majorana-1 | [0.3, 0.7] |
| case_06 | 4 | 100 | quantinuum.qpu.helios-1 | [0.3, 0.7] |
| case_07 | 4 | 100 | ibm.nighthawk-r2 | [0.3, 0.7] |
| case_08 | 4 | 100 | ionq.qpu.forte-1 | [0.3, 0.7] |
| case_09 | 2 | 50 | aqt.pine | [0.3, 0.7] |
| case_10 | 4 | 200 | simulator | [0.3, 0.7] |
| case_11 | 6 | 500 | simulator | [0.3, 0.7] |
| case_12 | 4 | 100 | microsoft.majorana-1 | [0.3, 0.7] |
| case_13 | 8 | 1000 | simulator | [0.3, 0.7] |
| case_14 | 4 | 200 | pasqal.sim.emu-mps | [0.3, 0.7] |
| case_15 | 4 | 100 | rigetti.ankaa-9q-3 | [0.3, 0.7] |

## Running

cd Azure
python benchmarks/run_all.py
cd AzureQuantum
python -m src.python.cli benchmark --cases-dir ../benchmarks/cases --parallel
```

## Performance Targets

| Metric | Target |
|---|---|
| Simulator (4 qubits, 100 shots) | < 1 second |
| MAIA 300 inference (512 tokens) | < 20 ms |
| Brainwave FPGA attention | < 1 ms |
| HCF transport (100 km) | < 500 us |
| Majorana QEC cycle | < 100 us |
