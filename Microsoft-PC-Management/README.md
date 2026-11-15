# OpenClawNet / Zenith

Runtime experimental .NET para inferência LLM, quantização, KV-cache, workloads CPU/ONNX, métricas, stress e implantação no host Zenith.

## Estado do modelo e eficiência

Este repositório **não inclui um conjunto de pesos treinados certificado**. Portanto não declara perplexidade, acurácia, tokens/s, latência ou eficiência energética como resultados medidos. Esses valores devem vir dos JSONL/benchmarks produzidos no hardware alvo.

### Arquitetura e pesos

- O planejamento do Transformer e a contagem de parâmetros são derivados da configuração do modelo.
- Há registro de pesos com shape, número de elementos, SHA-256, média, desvio padrão, esparsidade e tamanho armazenado.
- Persistência e shards usam verificação de integridade antes de recuperação.
- O pipeline de pós-refatoração suporta quantização por blocos e preservação separada de outliers.
- INT8 e a quantização pós-refatoração reduzem representação dos pesos; a perda numérica deve ser medida por tensor e no modelo final.
- KV-cache é tratado separadamente dos pesos para geração incremental.

## Métricas que definem eficiência

Não confunda tamanho comprimido com qualidade. Para cada build/modelo, registre pelo menos:

| Área | Métrica |
|---|---|
| Pesos | parâmetros, bytes, sparsity, hash |
| Quantização | erro máximo, erro médio/RMSE, compressão |
| Inferência | TTFT, tokens/s, P50/P95/P99 |
| Memória | working set, KV-cache por token/contexto |
| Qualidade | métrica apropriada ao dataset de avaliação |
| Estabilidade | erros, cancelamentos, recuperações |

`docs/zenith-dashboard.html` abre os arquivos JSONL localmente e aplica thresholds configuráveis a latência e taxa de erro.

## CI/CD Zenith

`.github/workflows/zenith-ci-cd.yml` executa restore, build, testes .NET, testes de rollback/recuperação e publicação Linux x64. O deploy em `main` usa um runner auto-hospedado rotulado `zenith` e os scripts de release/rollback existentes.

GitHub documenta workflows .NET em `.github/workflows`, `actions/setup-dotnet` para configurar o SDK e o uso de `dotnet restore/build/test` em CI. O deploy Zenith requer que o runner e o environment sejam configurados no repositório.

## Teste de recuperação

```powershell
pwsh ./tests/OpenClaw.Rollback.Tests/OpenClaw.Rollback.Tests.ps1
```

O teste corrompe a referência `current`, recupera a versão anterior e também confirma falha fechada quando o release de recuperação não existe.

## Dashboard

Abra `docs/zenith-dashboard.html`, selecione o JSONL e ajuste os thresholds. Os alertas são calculados no navegador, sem enviar métricas a serviços externos.

## Benchmarks reais e reprodutíveis no Zenith

Os projetos de benchmark abaixo executam código real da solução, mas **nenhum número de Ryzen Halo é publicado neste README sem ter sido medido no próprio Zenith**:

```powershell
pwsh ./powershell/Inference/Invoke-RyzenHaloBenchmarks.ps1
pwsh ./powershell/Inference/Invoke-TokenGenerationBenchmarks.ps1
pwsh ./powershell/Run-QuantizationBenchmarks.ps1
pwsh ./powershell/LoadTests/Invoke-ConcurrentLlmLoad.ps1 -Concurrency 32 -Requests 2000 -Width 1048576 -Output artifacts/metrics/zenith-load.jsonl
```

Após a execução, os valores observados devem ser mantidos em `artifacts/metrics/zenith-load.jsonl` e avaliados pelos gates. A política padrão rejeita taxa de erro acima de 1%, P95 acima de 5.000 ms ou throughput abaixo de 0,1 req/s. Esses limites são políticas de CI configuráveis, não alegações de desempenho do hardware.

```powershell
pwsh ./powershell/Quality/Test-ZenithQualityGates.ps1 `
  -MetricsPath artifacts/metrics/zenith-load.jsonl `
  -RequireMetrics
```

### Tabela de publicação de resultados

| Medição | Resultado publicado |
|---|---:|
| Quantização paralela | pendente de execução no runner Zenith |
| Geração token a token | pendente de execução no runner Zenith |
| Carga concorrente | pendente de execução no runner Zenith |
| P50 / P95 / P99 | pendente de execução no runner Zenith |
| Throughput | pendente de execução no runner Zenith |
| Taxa de erros | pendente de execução no runner Zenith |

Isso evita confundir um benchmark implementado com um resultado medido.

## Quality gates do CI/CD

O pipeline bloqueia a publicação quando build ou testes falham. Também executa injeção de falha de deployment seguida de recuperação, verifica o estado final da recuperação e aplica gates estáticos. Os gates de desempenho usam o JSONL produzido pelo Zenith e podem ser tornados obrigatórios no runner de hardware com `-RequireMetrics`.

## Recuperação após falha e finish

`tests/OpenClaw.Rollback.Tests/OpenClaw.FailureRecovery.Tests.ps1` injeta corrupção no release ativo, valida o release anterior, faz o commit da recuperação por arquivo temporário + rename e confirma o estado final sem marcador temporário. O deploy só deve ser considerado finalizado depois de build, testes, health/quality gates e commit do release.
