# Thesis Methodology: Implementation-to-Text Mapping

This outline maps your existing code in `src/` to the "Methodology" chapter of your thesis. Use the mathematical formulations and architectural details below to write the content.

## 3. Methodology

### 3.1 Overview of Sec-LogLLM
*   **Concept**: A hybrid architecture combining a specialist encoder (SecBERT) with a generalist reasoning engine (LLM) via a novel explainability bottleneck.
*   **Code Reference**: `src/models/sec_logllm.py`
*   **Architecture Diagram (Mental Model)**:
    ```mermaid
    graph LR
        Log[Raw Log] --> Encoder[SecBERT Encoder]
        Encoder --> Emb[Embeddings]
        Emb --> Projector[Alpha-Gated Projector]
        Projector -->|Alpha| Gate[Importance Gate]
        Projector -->|Features| Linear[Linear Proj]
        Gate -->|Weight| Combined[Weighted Embeddings]
        Linear --> Combined
        Combined --> LLM[Quantized LLM Decoder]
        LLM --> Analysis[JSON Analysis]
    ```

### 3.2 Encoder Component
*   **Purpose**: To extract semantic representations from security logs using domain-specific pre-training.
*   **Implementation**: `src/models/encoder.py`
*   **Details**:
    *   **Base Model**: `jackaduma/SecBERT` (Cybersecurity-specific BERT).
    *   **Mechanism**: Uses the `[CLS]` token from the last hidden state as the sequence representation.
    *   **Frozen Layers**: Lower layers (first 10) are frozen to retain general syntactic knowledge, while top layers are fine-tuned for the specific anomaly detection task.

### 3.3 The Alpha-Gating Mechanism (Novelty)
*   **Purpose**: To solve the "Black Box" problem by explicitly learning *which* logs contribute to the decision.
*   **Implementation**: `src/models/projector.py`
*   **Mathematical Formulation**:
    Let $x \in \mathbb{R}^{d_{bert}}$ be the encoder embedding.
    The gating network $G(x)$ computes a scalar importance score $\alpha \in (0, 1)$:

    $$
    h = \text{SiLU}(W_1 x + b_1)
    $$
    $$
    \text{logits} = W_2 h + b_2
    $$
    $$
    \alpha = \sigma\left(\frac{\text{logits}}{T}\right)
    $$

    Where:
    *   $W_1 \in \mathbb{R}^{d_{hidden} \times d_{bert}}$ is the first projection.
    *   $W_2 \in \mathbb{R}^{1 \times d_{hidden}}$ is the output projection.
    *   $\sigma$ is the Sigmoid function.
    *   $T$ is the temperature scaling factor (default $T=1.0$).
    *   Code Variable: `alpha_temperature`.

    The final projected embedding $z$ passed to the LLM is:
    $$
    z = \alpha \cdot \text{LayerNorm}(\text{Dropout}(W_{proj} x + b_{proj}))
    $$

### 3.4 Alignment & Sparsity (Training Objective)
*   **Purpose**: To align the BERT latent space with the LLM concept space while enforcing the "Need-to-Know" principle via sparsity.
*   **Implementation**: `src/training/custom_loss.py`
*   **Loss Function**:
    The Stage 2 alignment loss $\mathcal{L}_{total}$ is composed of a reconstruction error and a sparsity penalty:

    $$
    \mathcal{L}_{align} = \text{MSE}(z, z_{target})
    $$
    $$
    \mathcal{L}_{sparsity} = \frac{1}{N} \sum_{i=1}^{N} |\alpha_i|
    $$
    $$
    \mathcal{L}_{total} = \mathcal{L}_{align} + \lambda_{L1} \cdot \mathcal{L}_{sparsity}
    $$

    Where:
    *   $z$ is the predicted embedding from the projector.
    *   $z_{target}$ is the target semantic embedding from the LLM.
    *   $\lambda_{L1}$ controls the sparsity strength (Code default: `0.01`).

### 3.5 Three-Stage Training Strategy
*   **Phased Learning**:
    1.  **Stage 1 (Decoder Adaptation)**: Fine-tune the LLM (via LoRA) to understand the *output format* (JSON) and *security reasoning* reasoning using text-only inputs.
    2.  **Stage 2 (Projector Alignment)**: Freeze the LLM and Encoder. Train *only* the Projector to map logs to the LLM's embedding space. This initializes the "communication channel".
    3.  **Stage 3 (End-to-End)**: Fine-tune the Projector and LLM Adapters together to maximize task performance (F1 Score) and Explanability (Recall).

## 4. Key Experimental Variables
*   **Datasets**: AIT-LDS v1.1 (multi-host) and OpenSSH (single-host, generalization).
*   **Metrics**:
    *   **Fidelity**: Measures if high-$\alpha$ logs are truly causal.
    *   **Hallucination Rate**: Rate of assigning MITRE codes to normal events (OOD testing).
    *   **Alpha Sparsity**: $\frac{1}{N} \sum \mathbb{I}(\alpha < 0.1)$.
