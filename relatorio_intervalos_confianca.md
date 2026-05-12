# Relatório: Intervalos de Confiança para a Distribuição Exponencial

**Simulação de Monte Carlo — Avaliação de Cobertura**  
Data: 2026-05-12 | Parâmetros base: θ = 2, n = 20, α = 10%, R = 100 000

---

## Item 1 — Amostra única e construção dos intervalos

Fixando **θ = 2**, **n = 20** e **α = 10%**, uma amostra de tamanho 20 foi gerada de uma
distribuição Exp(θ = 2) (média = 1/θ = 0,5).

### Quantis necessários

| Quantidade       | Fórmula                          | Valor obtido |
|------------------|----------------------------------|-------------|
| λ₁               | qchisq(α/2 = 0,05 ; 2n = 40)    | **26,5093** |
| λ₂               | qchisq(1−α/2 = 0,95 ; 2n = 40)  | **55,7585** |
| z = z₀,₉₅       | qnorm(1−α/2 = 0,95)              | **1,6449**  |

### Estatísticas da amostra

| Estatística        | Valor      |
|--------------------|------------|
| Σ Xᵢ               | 12,1418    |
| X̄                  | 0,6071     |
| θ̂ = 1/X̄           | 1,6472     |

### Intervalos calculados

**CI 1 — Qui-quadrado (exato)**

$$
\left[\frac{\lambda_1}{2 \sum X_i}, \frac{\lambda_2}{2 \sum X_i}\right]
= \left[\frac{26{,}5093}{2 \times 12{,}1418}, \frac{55{,}7585}{2 \times 12{,}1418}\right]
= [1{,}0917 \;;\; 2{,}2961]
$$

**CI 2 — Normal assintótico (EMV)**

$$
\left[\frac{1}{\bar{X}} \pm z\sqrt{\frac{1}{n\bar{X}^2}}\right]
= \left[1{,}6472 \pm 1{,}6449 \times \sqrt{\frac{1}{20 \times 0{,}6071^2}}\right]
= [1{,}0414 \;;\; 2{,}2530]
$$

---

## Item 2 — O intervalo contém o parâmetro?

Com a amostra gerada:

| Intervalo                 | Contém θ = 2? |
|---------------------------|---------------|
| CI 1 (Qui-quadrado)       | **SIM**       |
| CI 2 (Normal assintótico) | **SIM**       |

Ambos os intervalos capturaram θ = 2 nesta replicação particular.

**Interpretação probabilística:** Se gerarmos infinitas amostras de tamanho 20
com α = 10%, esperamos que **90% dos intervalos CI 1** contenham θ = 2 — e isso
é exato, não apenas aproximado. Para o CI 2, a garantia de 90% é apenas assintótica;
na prática, ela pode diferir do valor nominal para n pequeno, como verificado no Item 7.

---

## Item 3 — Simulação de Monte Carlo: probabilidade de cobertura

**Configuração:** θ = 2, n = 20, α = 10%, **R = 100 000 replicações**.

| Intervalo                  | Taxa de cobertura | Nível nominal |
|---------------------------|-------------------|---------------|
| CI 1 (Qui-quadrado, exato) | **90,05 %**       | 90 %          |
| CI 2 (Normal assintótico)  | **90,58 %**       | 90 %          |

**Conclusão:** O CI 1 atingiu praticamente 90% exatos — confirmando que é um
intervalo exato, não assintótico. O CI 2 ficou levemente acima de 90% (90,58%),
indicando uma leve sobrecobertura nesse tamanho amostral. Isso será aprofundado
no Item 7.

---

## Item 4 — Efeito de n, R e θ sobre a taxa de cobertura

### 4a. Variando n (θ = 2, R = 100 000)

| n   | Cobertura CI 1 (%) | Cobertura CI 2 (%) | Nominal (%) |
|-----|--------------------|--------------------|-------------|
|   5 | 90,06              | 92,25              | 90,00       |
|  10 | 90,05              | 91,23              | 90,00       |
|  20 | 90,11              | 90,62              | 90,00       |
|  30 | 90,12              | 90,45              | 90,00       |
|  50 | 89,92              | 90,17              | 90,00       |
| 100 | 89,95              | 90,07              | 90,00       |
| 200 | 89,98              | 90,00              | 90,00       |
| 500 | 90,04              | 90,06              | 90,00       |

**Observação:** A taxa de cobertura do **CI 1 não depende de n** — ela oscila em
torno de 90% para qualquer tamanho amostral, confirmando o caráter *exato* do
intervalo. O **CI 2** converge para 90% à medida que n cresce, exibindo sobrecobertura
para n pequeno.

### 4b. Variando θ (n = 20, R = 100 000)

| θ    | Cobertura CI 1 (%) | Cobertura CI 2 (%) |
|------|--------------------|--------------------|
|  0,5 | 89,97              | 90,58              |
|  1,0 | 90,02              | 90,52              |
|  2,0 | 89,87              | 90,42              |
|  5,0 | 90,12              | 90,59              |
| 10,0 | 90,04              | 90,58              |

**Observação:** A cobertura de **ambos os intervalos é invariante ao valor de θ** —
como esperado, pois os limites do CI dependem de θ apenas via os dados (Σ Xᵢ ou X̄),
e a distribuição de cobertura é invariante ao parâmetro de escala.

---

## Item 5 — O segundo intervalo (CI 2): definição formal

O **CI 2** baseia-se na distribuição assintótica do Estimador de Máxima
Verossimilhança (EMV) de θ para a família exponencial.

Para Xᵢ ~ Exp(θ), o EMV é θ̂ = 1/X̄. Pelo Método Delta aplicado ao TCL:

$$
\sqrt{n}\left(\frac{1}{\bar{X}} - \theta\right) \xrightarrow{d} \mathcal{N}(0,\, \theta^2)
$$

Substituindo θ̂ por θ no desvio-padrão (estimativa plug-in), o IC assintótico fica:

$$
\left[\frac{1}{\bar{X}} - z_{1-\alpha/2}\sqrt{\frac{1}{n\bar{X}^2}}, \;\frac{1}{\bar{X}} + z_{1-\alpha/2}\sqrt{\frac{1}{n\bar{X}^2}}\right]
$$

Em Java, z é obtido com `new NormalDistribution().inverseCumulativeProbability(1.0 - alpha/2)`.

---

## Item 6 — Comparação dos dois intervalos

| n   | Cobertura CI 1 (%) | Cobertura CI 2 (%) | Nominal (%) |
|-----|--------------------|--------------------|-------------|
|   5 | 89,74              | 91,94              | 90,00       |
|  10 | 90,03              | 91,15              | 90,00       |
|  15 | 90,13              | 90,85              | 90,00       |
|  20 | 89,91              | 90,46              | 90,00       |
|  30 | 90,15              | 90,53              | 90,00       |
|  50 | 89,96              | 90,20              | 90,00       |
|  75 | 90,24              | 90,27              | 90,00       |
| 100 | 89,92              | 90,03              | 90,00       |
| 200 | 89,95              | 90,01              | 90,00       |
| 500 | 89,94              | 89,99              | 90,00       |

### Qual é o melhor?

**CI 1 (Qui-quadrado) é superior** pelos seguintes motivos:

1. **Exatidão:** a cobertura é exatamente 1 − α para *qualquer* n e *qualquer* θ, pois
   2θ · Σ Xᵢ ~ χ²(2n) é resultado teórico exato.
2. **Calibração:** não apresenta sobrecobertura nem subcobertura para nenhum n.
3. **Menor variabilidade amostral:** a sobrecobertura do CI 2 em amostras pequenas
   implica que seus limites são desnecessariamente largos, desperdiçando precisão.

O CI 2 só se torna competitivo quando n ≥ 100, onde a aproximação normal já é adequada.

---

## Item 7 — Distorções do CI 2 em amostras pequenas

O CI 2 é baseado na **distribuição assintótica** do EMV, que pressupõe que
θ̂ = 1/X̄ é aproximadamente normal. Entretanto, para n pequeno:

- A distribuição amostral de 1/X̄ é **assimétrica e leptocúrtica** (caudas mais
  pesadas que a normal), pois segue uma distribuição inversa do tipo Gamma.
- O sigma usado em CI 2 é estimado por *plug-in* (substituindo θ por θ̂),
  introduzindo incerteza adicional.
- O resultado observado é uma **sobrecobertura** do CI 2 para n ≤ 30
  (a normal subestima as caudas da distribuição real de θ̂, gerando um IC mais
  largo que o necessário → captura θ com frequência acima de 90%).

### Como n influi na qualidade da aproximação?

| n   | Excesso de cobertura CI 2 (p.p.) |
|-----|----------------------------------|
|   5 | +2,24                            |
|  10 | +1,15                            |
|  20 | +0,46                            |
|  50 | +0,20                            |
| 100 | +0,03                            |
| 500 | −0,01                            |

> **Conclusão:** A aproximação normal torna-se confiável somente para **n ≥ 100**.
> Para n ≤ 30, o CI 1 é o único que garante a cobertura nominal exata.

---

## Gráfico: Taxa de cobertura vs n

O gráfico **`output/plots/cobertura_ic_exponencial.pdf`** mostra as duas curvas
com escala logarítmica no eixo x:

- **Azul (■):** CI 1 — Qui-quadrado (exato) → linha horizontal estável em ~90%.
- **Vermelho (●):** CI 2 — Normal assintótico → começa em ~92% para n = 5 e
  converge monotonicamente para 90% conforme n cresce.
- **Linha tracejada cinza:** nível nominal de 90%.

O gráfico evidencia visualmente que o CI 1 é robusto a n, enquanto o CI 2 exibe
um excesso de cobertura que diminui com o aumento amostral.

---

## Resumo executivo

| Critério                       | CI 1 (Qui-quadrado) | CI 2 (Normal/EMV) |
|-------------------------------|----------------------|-------------------|
| Tipo                          | Exato                | Assintótico       |
| Cobertura — qualquer n        | ✅ ~90% sempre        | ⚠️ Acima de 90% para n < 50 |
| Cobertura — n grande (≥ 100)  | ✅ ~90%               | ✅ ~90%            |
| Dependência de θ              | Invariante           | Invariante        |
| Interpretação                 | Baseado em 2θ·ΣXᵢ ~ χ²(2n) | Método Delta + TCL |
| **Recomendação**              | **Preferível sempre** | Aceitável com n ≥ 100 |

