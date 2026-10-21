<p align="right">
  <a href="README.md">🇬🇧 English</a> • <b>🇧🇷 Português</b>
</p>

# Enterprise GitOps & DevSecOps Cloud Platform

[![CI/CD - Build and GitOps Sync](https://github.com/mdhenriques/gitops-lab/actions/workflows/deploy.yaml/badge.svg)](https://github.com/mdhenriques/gitops-lab/actions/workflows/deploy.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Kubernetes](https://img.shields.io/badge/kubernetes-v1.30+-326ce5.svg?logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![Terraform](https://img.shields.io/badge/terraform-v1.11+-844fba.svg?logo=terraform&logoColor=white)](https://www.terraform.io)
[![AWS](https://img.shields.io/badge/AWS-Certified%20Architecture-232f3e.svg?logo=amazon-aws&logoColor=white)](https://aws.amazon.com)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-v3.5.5-orange.svg?logo=argo&logoColor=white)](https://argoproj.github.io/cd/)
[![Kyverno](https://img.shields.io/badge/Kyverno-v3.9.1-008080.svg?logo=kyverno&logoColor=white)](https://kyverno.io/)
[![Checkov](https://img.shields.io/badge/Checkov-IaC%20Security-red.svg)](https://www.checkov.io/)

Uma plataforma cloud-native de nível corporativo projetada para demonstrar **GitOps Corporativo, Shift-Left DevSecOps e Governança Zero-Trust em Kubernetes**.

Desenhada para eliminar os anti-padrões mais comuns em ambientes de nuvem (como credenciais estáticas em pipelines de CI/CD, segredos em texto claro no state do Terraform e containers com permissões irrestritas em runtime), esta plataforma implementa um ciclo de entrega totalmente declarativo, auditável e automatizado integrando **AWS**, **GitHub Actions**, **ArgoCD**, **Kyverno** e **Prometheus**.

---

## 📑 Índice

- [🏛️ Arquitetura da Solução & Fluxo do Sistema](#-arquitetura-da-solucao-e-fluxo-do-sistema)
- [🧠 Decisões de Engenharia Aprofundadas & "O Porquê"](#-decisoes-de-engenharia-aprofundadas--o-porque)
  - [1. CI/CD Sem Chaves via Federação OIDC do AWS IAM](#1-cicd-sem-chaves-via-federacao-oidc-do-aws-iam)
  - [2. Pipeline de Segurança Shift-Left (Checkov, Trivy, Pytest)](#2-pipeline-de-seguranca-shift-left-checkov-trivy-pytest)
  - [3. Entrega GitOps Baseada em Pull vs. CI/CD Baseado em Push](#3-entrega-gitops-baseada-em-pull-vs-cicd-baseado-em-push)
  - [4. Runtime Zero-Trust & Policy-as-Code (Kyverno)](#4-runtime-zero-trust--policy-as-code-kyverno)
  - [5. Estado Remoto S3 Blindado, Sanitização de Segredos & Tokens ECR Dinâmicos](#5-estado-remoto-s3-blindado-sanitizacao-de-segredos--tokens-ecr-dinamicos)
  - [6. Isolamento de Rede em Defesa em Profundidade](#6-isolamento-de-rede-em-defesa-em-profundidade)
  - [7. Probes de Saúde Resilientes & Telemetria OpenMetrics](#7-probes-de-saude-resilientes--telemetria-openmetrics)
- [💡 Comparativo de Arquitetura (Anti-padrões vs. Padrão Enterprise)](#-comparativo-de-arquitetura-anti-padroes-vs-padrao-enterprise)
- [⚖️ Trade-offs: Laboratório Local vs. Produção AWS](#️-trade-offs-laboratorio-local-vs-producao-aws)
- [📁 Estrutura do Repositório](#-estrutura-do-repositorio)
- [🛠️ Stack Tecnológica](#️-stack-tecnologica)
- [🚀 Guia de Reprodução Local (Runbooks)](#-guia-de-reproducao-local-runbooks)
- [📄 Licença](#-licenca)

---

<a id="solution-architecture-and-workflow"></a>
## 🏛️ Arquitetura da Solução & Fluxo do Sistema

A arquitetura da plataforma conecta serviços gerenciados na nuvem pública (**AWS**), esteiras de automação security-first no **GitHub Actions** e um cluster **Kubernetes** multi-node com hardening sincronizado de forma declarativa via **ArgoCD**:

<p align="center">
  <img src="docs/assets/architecture.svg" alt="Arquitetura Enterprise GitOps & DevSecOps" width="100%">
</p>

---

## 🧠 Decisões de Engenharia Aprofundadas & "O Porquê"

### 1. CI/CD Sem Chaves via Federação OIDC do AWS IAM

* **O Problema:** Armazenar `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY` de longa duração nos Secrets do GitHub representa um risco de segurança crítico. Chaves estáticas não expiram automaticamente, carecem de restrições contextuais e, se vazadas, concedem acesso amplo e de difícil rastreamento à conta AWS.
* **A Solução de Engenharia:** Foi configurado um **Provedor de Identidade OpenID Connect (OIDC)** entre o GitHub Actions e o AWS IAM. A esteira utiliza a action oficial `aws-actions/configure-aws-credentials` para solicitar credenciais temporárias do STS (com validade de 15 a 60 min) via `sts:AssumeRoleWithWebIdentity`.
* **Hardening de Segurança:** A política de confiança (Trust Policy) da Role IAM avalia rigorosamente claims imutáveis do repositório GitHub:
  ```json
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub": "repo:mdhenriques@103260127/gitops-lab@1416272098:ref:refs/heads/master"
    }
  }
  ```
  Mesmo que o nome do repositório seja clonado ou forkeado por terceiros, apenas os IDs numéricos exatos e imutáveis da conta e do repositório conseguem assumir a Role de deploy.

<p align="center">
  <img src="docs/assets/github-actions-build-job.png" alt="Execução OIDC Sem Chaves no GitHub Actions" width="90%">
</p>

---

### 2. Pipeline de Segurança Shift-Left (Checkov, Trivy, Pytest)

* **O Problema:** Identificar vulnerabilidades de infraestrutura ou imagens base inseguras em produção é ordens de grandeza mais caro e perigoso do que detectá-las durante o code review.
* **A Solução de Engenharia:** Foi implementado um gate de validação shift-left em três camadas executado diretamente no runner do GitHub Actions:
  1. **Testes Unitários e de Contrato:** O `pytest apps/api/test_main.py` roda antes de qualquer empacotamento, garantindo a corretude funcional (fail-fast).
  2. **SAST de Infraestrutura como Código (IaC):** O `checkov` analisa todos os módulos Terraform e manifestos Kubernetes em busca de más configurações de segurança (ex: portas expostas, ausência de criptografia, wildcards em políticas IAM).
  3. **Varredura de CVEs em Containers:** A action `aquasecurity/trivy-action` inspeciona a imagem Docker recém-construída em busca de vulnerabilidades de SO e pacotes de severidade alta/crítica antes de permitir o push para o AWS ECR.

<p align="center">
  <img src="docs/assets/github-actions-checkov-job.png" alt="Execução do Scan de Segurança Checkov" width="90%">
</p>

---

### 3. Entrega GitOps Baseada em Pull vs. CI/CD Baseado em Push

* **O Problema:** No modelo tradicional de deploy baseado em push (ex: script de CI executando `kubectl apply`), o runner de CI exige credenciais administrativas completas do cluster (`kubeconfig`). Isso expande a superfície de ataque do cluster para a infraestrutura de CI e é incapaz de detectar alterações manuais feitas diretamente por operadores (*configuration drift*).
* **A Solução de Engenharia:** Adotamos um **motor GitOps baseado em Pull (ArgoCD)** executando dentro do cluster. A esteira de CI compila a imagem do container tagueada com o hash de commit imutável do Git e abre um Pull Request automatizado atualizando o arquivo `k8s/base/deployment.yaml`. Após o merge, o ArgoCD reconcilia o estado do cluster com o repositório Git.
* **Governança via ArgoCD `AppProject`:** As cargas de trabalho são isoladas dentro de um `gitops-lab-project` dedicado que impõe:
  - Whitelist restrita permitindo apenas `https://github.com/mdhenriques/gitops-lab.git` como repositório de origem válido.
  - Destino de deploy restrito estritamente ao namespace `production`.
  - Bloqueio de criação não autorizada de recursos em escopo de cluster (*cluster-scoped*).

<p align="center">
  <img src="docs/assets/argo-applications.png" alt="Visão Geral de Sincronização Multi-Aplicação no ArgoCD" width="95%">
</p>

<p align="center">
  <img src="docs/assets/argo-tree.png" alt="Árvore Topológica das Cargas de Trabalho no ArgoCD" width="95%">
</p>

---

### 4. Runtime Zero-Trust & Policy-as-Code (Kyverno)

* **O Problema:** Clusters Kubernetes padrão não impedem desenvolvedores de acidentalmente subir containers executando como `root`, montando filesystems com permissão de escrita ou consumindo memória e CPU ilimitados, causando o fenômeno de "vizinho barulhento" (*noisy neighbor*) e esgotamento do nó.
* **A Solução de Engenharia:** Foram impostas **Políticas Declarativas de Admission Controller** via **Kyverno** operando em modo `Enforce`. Qualquer recurso submetido ao API Server é inspecionado antes de ser persistido no `etcd`:
  - **`disallow-root-and-privileged`:** Impõe `runAsNonRoot: true`, UID numérico não-root (10001), remoção de todas as capabilities do Linux (`drop: ["ALL"]`) e bloqueio de escalonamento de privilégios (`allowPrivilegeEscalation: false`).
  - **`require-resources`:** Exige que todo container declare explicitamente `requests` e `limits` tanto para CPU quanto para memória.
  - **Hardening de Container:** A imagem da API é construída com usuário não-root e monta o filesystem raiz como somente leitura (`readOnlyRootFilesystem: true`), neutralizando injeção de scripts e adulteração de arquivos.

<p align="center">
  <img src="docs/assets/kyverno-blocking.png" alt="Admission Webhook do Kyverno Bloqueando Rogue Pod" width="95%">
</p>

---

### 5. Estado Remoto S3 Blindado, Sanitização de Segredos & Tokens ECR Dinâmicos

* **O Problema com State Local & Vazamento de Credenciais:**
  - Arquivos `terraform.tfstate` locais na máquina de desenvolvedores são um dos vetores mais comuns de vazamento de credenciais em nuvem. Quando o Terraform provisiona a Access Key IAM para o External Secrets Operator (`aws_iam_access_key.eso_user_key`), a chave secreta é obrigatoriamente gravada no state. Se o state ficar na máquina do desenvolvedor, um `git add .` acidental ou uma máquina compartilhada expõe as credenciais da AWS.
  - Além disso, senhas de banco de dados passadas em módulos Terraform tradicionais ficam expostas em texto claro no `.tfstate`.
  - Simultaneamente, tokens de autenticação do AWS ECR expiram a cada 12 horas, tradicionalmente forçando equipes a manter CronJobs frágeis em Bash para atualizar secrets do Kubernetes.
* **A Solução de Engenharia:**
  1. **Backend Remoto S3 Blindado & Arquitetura Bootstrap (`terraform/bootstrap`):**
     - **Stack de Bootstrap Desacoplada:** Resolve o problema do *"ovo e a galinha"* provisionando o bucket S3 de estado em um módulo bootstrap isolado e declarativo *antes* da execução da infraestrutura principal.
     - **Criptografia em Repouso:** Criptografia obrigatória AES-256 (`SSE-S3`) com bucket keys habilitadas para proteger os dados armazenados.
     - **Bloqueio de Acesso Público Total:** O `aws_s3_bucket_public_access_block` impõe bloqueio rigoroso em todos os 4 vetores de ACLs e políticas públicas.
     - **Exigência Estrita de TLS:** Uma política de bucket rejeita qualquer requisição HTTP não criptografada (`aws:SecureTransport = false`).
     - **Versionamento & Proteção contra Exclusão:** Versionamento habilitado com `prevent_destroy = true` e política de lifecycle de 90 dias para versões antigas de state.
     - **State Locking Nativo no S3 (`use_lockfile = true`):** Utiliza a funcionalidade nativa do Terraform 1.10+ diretamente no S3, garantindo controle de concorrência distribuído e prevenindo corrupção de estado sem a necessidade nem os custos de uma tabela DynamoDB separada.
     - **Zero Credenciais em Disco Local:** Como o state é enviado diretamente via TLS para o bucket S3 criptografado, **nenhum arquivo de state contendo Access Keys da AWS toca o sistema de arquivos local nem o Git** (o `.gitignore` atua como barreira adicional de defesa em profundidade).
  2. **Terraform 1.11+ `ephemeral` & `value_wo` (Senhas com Zero Vazamento):** Senhas geradas via `ephemeral.random_password` são transmitidas para o AWS SSM Parameter Store usando o atributo write-only `value_wo`. O segredo é enviado diretamente para a AWS e nunca é persistido nem no state local nem no remoto.
  3. **External Secrets Operator (ESO) + Gerador Nativo ECR:** Utiliza o `ClusterGenerator` nativo do ESO (`kind: ECRAuthorizationToken`) associado a um `ExternalSecret`. O operador comunica-se diretamente com o AWS STS/ECR, renovando o token de autenticação Docker a cada 30 minutos de forma totalmente transparente e sem scripts manuais.

> [!NOTE]
> **Arquitetura de Plataforma Desacoplada (Segredo Demonstrativo vs. Banco Real):**
> Neste repositório de portfólio, o parâmetro do AWS SSM armazena uma string de conexão de banco de dados demonstrativa gerada dinamicamente. Provisionar um banco gerenciado real na nuvem (como um Amazon RDS PostgreSQL) para um laboratório pessoal incorreria em custos mensais desnecessários (~$15 a $30/mês) e ciclos lentos de provisionamento.
> 
> A competência de engenharia central demonstrada aqui é o **pipeline completo de injeção e ciclo de vida de segredos**:
> `Terraform (ephemeral) ➔ AWS SSM Parameter Store ➔ Política de Menor Privilégio IAM ➔ External Secrets Operator ➔ Kubernetes Secret ➔ Ambiente do Pod`.
> Em um cenário de produção com um banco de dados real, toda a arquitetura de GitOps, ESO e Kubernetes permanece 100% idêntica — apenas o valor do parâmetro no SSM apontaria para o endpoint real do RDS.

---

### 6. Isolamento de Rede em Defesa em Profundidade

* **O Problema:** O modelo de rede padrão do Kubernetes é aberto por definição: qualquer pod em qualquer namespace pode se comunicar com qualquer outro pod, expondo serviços internos a ataques de movimento lateral caso algum container seja comprometido.
* **A Solução de Engenharia:** Foi implementada uma `NetworkPolicy` zero-trust no namespace `production`:
  - **Restrição de Ingress Padrão:** Bloqueia todo o tráfego de entrada, exceto tráfego HTTP explícito na porta 8000 e coleta de métricas a partir do namespace `monitoring`.
  - **Whitelist Seletiva de Egress:** Permite resolução de DNS (`kube-system` UDP 53) e tráfego HTTPS de saída (porta 443) exclusivamente para os endpoints das APIs do AWS SSM e ECR, bloqueando conexões externas arbitrárias.

---

### 7. Probes de Saúde Resilientes & Telemetria OpenMetrics

* **O Problema:** Misturar a finalidade das probes de Liveness e Readiness é uma causa frequente de falhas em cascata em sistemas distribuídos. Se um banco de dados oscilar e a probe de Liveness falhar, o Kubernetes reinicia o pod, sobrecarregando ainda mais as réplicas sobreviventes.
* **A Solução de Engenharia:**
  - **Liveness Probe (`/healthz`):** Avalia estritamente se o processo Python e o event loop da aplicação estão ativos e responsivos. Não verifica dependências downstream.
  - **Readiness Probe (`/readyz`):** Avalia se parâmetros de configuração, segredos do SSM e conectividade estão prontos. Se uma dependência oscilar, o tráfego é desviado do pod sem que o container seja reiniciado.
  - **Observabilidade com Prometheus:** Integração com `prometheus-fastapi-instrumentator` expondo métricas essenciais (taxa de requisições HTTP, taxa de erros e percentis de latência) no endpoint `/metrics`.

<p align="center">
  <img src="docs/assets/prometheus-graph-rate.png" alt="Gráfico de Telemetria em Tempo Real no Prometheus" width="95%">
</p>

---

## 💡 Comparativo de Arquitetura (Anti-padrões vs. Padrão Enterprise)

| Domínio | Abordagem Tradicional (Anti-padrão) | Abordagem Deste Projeto (Padrão Enterprise) | Benefício Arquitetural |
| :--- | :--- | :--- | :--- |
| **Autenticação CI/CD** | Chaves estáticas `AWS_ACCESS_KEY_ID` salvas nos Secrets do GitHub. | **AWS IAM OIDC Federation:** Autenticação sem chaves de longa duração, usando claims imutáveis do repositório. | Elimina necessidade de rotação de chaves e remove risco de vazamento de credenciais permanentes. |
| **Armazenamento de State & Segredos em IaC** | Arquivo `terraform.tfstate` local e desprotegido armazenando Access Keys geradas e senhas em texto claro no disco do desenvolvedor. | **S3 Remote Backend Blindado + `value_wo`:** State armazenado no S3 com AES-256, TLS obrigatório e locking nativo; senhas não gravadas no state e chaves IAM nunca salvas localmente. | Elimina vazamento de credenciais na máquina do desenvolvedor; o state fica criptografado, versionado, com lock e auditável. |
| **Autenticação para Pull no ECR** | CronJob customizado executando script em bash para renovar `dockerconfigjson` a cada 12h. | **Gerador `ECRAuthorizationToken` do ESO:** Operador nativo renova o token automaticamente a cada 30m. | Elimina scripts frágeis; ciclo gerenciado de forma autônoma e declarativa pelo Kubernetes. |
| **Deploy via GitOps** | Runner de CI executa `kubectl apply` utilizando credenciais administrativas do cluster (`kubeconfig`). | **GitOps Baseado em Pull (ArgoCD):** O cluster puxa as alterações; PRs automatizados atualizam as tags das imagens. | As credenciais do cluster nunca saem do cluster; detecção contínua e correção automática de desvios (*drift*). |
| **Segurança na Esteira (CI)** | Código sem validações compilado e enviado diretamente ao registry. | **Shift-Left Security:** Testes unitários com Pytest, varredura de IaC com Checkov e scan de CVEs com Trivy. | Falhas, vulnerabilidades e violações de compliance bloqueadas no commit antes do empacotamento. |
| **Hardening de Runtime** | Containers rodando como `root` com filesystem gravável e permissões completas. | **CIS Hardening & Kyverno:** `readOnlyRootFilesystem`, UID 10001 não-root e remoção de capabilities Linux. | Mitiga ataques de quebra de container (*breakout*) e adulteração de arquivos em runtime. |
| **Governança do Cluster** | Todas as aplicações submetidas no projeto `default` do ArgoCD sem restrições. | **`AppProject` Dedicado no ArgoCD:** Whitelist estrita de repositórios Git, namespaces de destino e recursos autorizados. | Garante isolamento multi-tenant e impede usurpação arbitrária de recursos cluster-scoped. |
| **Otimização de Custos (FinOps)** | Repositório ECR retendo imagens indefinidamente sem regras de expiração. | **ECR Lifecycle Policy:** Retém estritamente as 10 imagens mais recentes, limpando builds obsoletos. | Custos de armazenamento previsíveis e praticamente nulos na AWS (**FinOps** best practice). |
| **Observabilidade** | Probe única verificando tanto a disponibilidade do servidor quanto do banco de dados. | **Separação estrita Liveness (`/healthz`) vs. Readiness (`/readyz`)** + **Métricas OpenMetrics**. | Evita tempestades de reinício em cascata; fornece telemetria granular em tempo real. |

---

## ⚖️ Trade-offs: Laboratório Local vs. Produção AWS

Esta plataforma foi desenvolvida para ser **100% reproduzível localmente em uma estação de trabalho** via **Kind**, conectando-se a recursos reais na nuvem AWS com custos praticamente nulos. Para equilibrar fidelidade à produção e economia financeira, as seguintes decisões conscientes foram tomadas:

| Componente | Implementação Neste Lab (Kind) | Produção Corporativa (AWS EKS) | Justificativa do Trade-off |
| :--- | :--- | :--- | :--- |
| **Autenticação K8s ➔ AWS** | `aws_iam_access_key` com menor privilégio armazenada em Secret do Kubernetes. | **EKS Pod Identity** ou **IRSA (IAM Roles for Service Accounts)**. | Clusters locais fora da AWS não possuem o emissor OIDC nativo do EKS. Em produção no EKS, as credenciais estáticas do ESO são 100% substituídas por anotações de Service Account. |
| **Persistência de Armazenamento** | Armazenamento efêmero em memória (`persistentVolume: false`) para o Prometheus. | **EBS CSI Driver** ou **Amazon Managed Prometheus (AMP)**. | Elimina cobranças mensais por volumes EBS e overhead de provisioners dinâmicos no Kind, mantendo o cluster local leve e rápido de inicializar. |
| **Scanners DevSecOps** | Execução em modo informativo (`soft_fail: true` / `exit-code: 0`). | Bloqueio rígido de pipeline (*Hard-fail*) com gates restritos de compliance. | Permite auditoria contínua sem quebrar a esteira por políticas corporativas que exigiriam custos extras na AWS (ex: KMS CMK dedicado, Replicação Cross-Region do S3 e Access Logging). |
| **Armazenamento de Parâmetros** | AWS Systems Manager (SSM) Standard Parameter Store. | AWS Secrets Manager com chaves KMS gerenciadas pelo cliente (CMK). | O SSM Standard Parameter Store cumpre perfeitamente o papel de injeção segura de segredos com custo zero de faturamento na AWS. |
| **Backend de Banco de Dados** | Parâmetro demonstrativo com conexão injetada via SSM. | Instância dedicada do **Amazon RDS (PostgreSQL/Aurora)** em subnets privadas. | Economiza ~$15 a $30/mês em custos de banco ocioso. O foco da plataforma é o pipeline de entrega de segredos, que é 100% compatível e plug-and-play para bancos reais. |

> [!NOTE]
> **Postura de Segurança no Pipeline (Soft-Fail & FinOps):**
> Os scanners de segurança estática (**Checkov**) e vulnerabilidade de contêineres (**Aqua Trivy**) operam intencionalmente em **modo informativo** (`soft_fail: true`). Apontamentos como ausência de *S3 Access Logging* ou *Replicação Cross-Region* no bucket de estado de laboratório são decisões conscientes de **FinOps**: mantêm o ambiente com custos praticamente nulos na AWS sem mascarar os relatórios de conformidade.

---

## 📁 Estrutura do Repositório

```text
├── .github/workflows/
│   └── deploy.yaml              # CI/CD no GitHub Actions (Pytest, Checkov, Trivy, OIDC, bot de PR)
├── apps/api/
│   ├── Dockerfile               # Container multi-stage com hardening (não-root UID 10001, python:3.11-slim)
│   ├── main.py                  # Aplicação FastAPI com instrumentador Prometheus e probes de saúde
│   ├── test_main.py             # Testes unitários automatizados para endpoints e métricas
│   ├── requirements.txt         # Dependências de execução da aplicação
│   └── requirements-dev.txt     # Dependências de desenvolvimento e testes (pytest, httpx)
├── argocd/
│   ├── app-project.yaml         # Política de governança do ArgoCD (whitelist de repositórios e destinos)
│   ├── application.yaml         # Aplicação GitOps principal gerenciando cargas de k8s/base/
│   ├── monitoring-app.yaml      # Integração declarativa da stack do Prometheus
│   └── security-policies-app.yaml # Aplicação GitOps para as políticas de admissão do Kyverno
├── k8s/
│   ├── base/
│   │   ├── api-external-secret.yaml     # Sincronização do ESO entre AWS SSM e Kubernetes Secret
│   │   ├── aws-secret-store.yaml        # Definição do provedor ClusterSecretStore
│   │   ├── deployment.yaml              # Deployment de produção (com securityContext endurecido)
│   │   ├── ecr-cluster-generator.yaml   # ClusterGenerator do ESO para autenticação no AWS ECR
│   │   ├── ecr-pull-external-secret.yaml # Secret docker-registry auto-renovado a cada 30m
│   │   ├── network-policy.yaml          # Isolamento de rede zero-trust para o namespace production
│   │   └── service.yaml                 # Definição de Service ClusterIP
│   └── eso-values.yaml                  # Configurações do Helm para o External Secrets Operator
├── policies/kyverno/
│   ├── disallow-root.yaml       # Política de admissão exigindo non-root e proibindo privilege escalation
│   └── require-resources.yaml   # Política de admissão exigindo requests e limits de CPU/Memória
├── terraform/
│   ├── bootstrap/               # Stack isolada para bucket S3 com AES-256 e versionamento
│   │   └── main.tf
│   ├── main.tf                  # AWS ECR (lifecycle policy), SSM Parameter, IAM OIDC Role & Policies
│   └── variables.tf             # Configurações parametrizadas com variáveis tipadas
├── docs/assets/                 # Diagramas de arquitetura, gráficos de observabilidade e prints
├── kind-config.yaml             # Configuração do cluster Kubernetes multi-node (1 control-plane, 2 workers)
└── README.md                    # Documentação principal da plataforma e runbooks de engenharia
```

---

## 🛠️ Stack Tecnológica

- **Infraestrutura em Nuvem:** AWS (ECR com Lifecycle Policy, SSM Parameter Store, Federação IAM OIDC, Backend Remoto S3)
- **Infraestrutura como Código (IaC):** Terraform >= 1.11 (HCL modular, parâmetros write-only no SSM, bootstrap de estado)
- **Containerização & Runtime:** Docker, Kubernetes v1.30+ (Kind multi-node: 1 control-plane, 2 workers)
- **Entrega Contínua GitOps:** ArgoCD v3.5.5 (Governança com AppProject, auto-healing automatizado, prune declarativo)
- **Policy-as-Code & Segurança:** Kyverno v3.9.1 (Admission Controller Webhooks), External Secrets Operator v2.12.0, Checkov (IaC SAST), Aqua Trivy (Scanner CVE de Containers)
- **Aplicação & Observabilidade:** Python 3.11, FastAPI, Uvicorn, Pytest, Prometheus, OpenMetrics, Logs Estruturados em JSON

---

## 🚀 Guia de Reprodução Local (Runbooks)

Caso você queira provisionar e testar a plataforma completa localmente na sua máquina, siga os passos abaixo:

### ⚠️ Passo 0: Fork Obrigatório (Não utilize `git clone` direto)

> [!WARNING]
> **Fazer `git clone` diretamente deste repositório matriz NÃO funcionará no seu laboratório!**
> 
> Este projeto opera sob o modelo de **GitOps e Automação Contínua (CI/CD)**. Para que o ciclo funcione de ponta a ponta:
> - Você precisa de permissões de escrita para que a esteira do GitHub Actions compile as imagens e abra Pull Requests automatizados.
> - A Role IAM via OIDC na sua conta AWS só autorizará execuções originadas do seu próprio repositório.
> - O ArgoCD local precisa monitorar e reconciliar um repositório sob o seu total controle.
> 
> **Passo a passo obrigatório:**
> 1. Clique no botão **Fork** (no canto superior direito desta página do GitHub) para criar uma cópia na sua conta.
> 2. Clone o **seu fork** para a sua máquina local:
>    ```bash
>    git clone https://github.com/SEU_USUARIO/gitops-lab.git
>    cd gitops-lab
>    ```
> 3. Atualize as URLs nos manifestos do ArgoCD para apontarem para o seu fork:
>    ```bash
>    sed -i 's/mdhenriques/SEU_USUARIO/g' argocd/*.yaml
>    ```
> 4. Configure a claim OIDC no [terraform/variables.tf](terraform/variables.tf) (variável `github_oidc_sub`):  
>    O GitHub Actions exige o formato de IDs imutáveis (`repo:USER@ID/REPO@ID:ref:refs/heads/master`). Para descobrir os IDs numéricos da sua conta e do seu repositório forkeado, execute:
>    ```bash
>    # 1. Obter o ID numérico da sua conta GitHub:
>    curl -s https://api.github.com/users/SEU_USUARIO | grep -m1 '"id":'
>    
>    # 2. Obter o ID numérico do seu repositório gitops-lab:
>    curl -s https://api.github.com/repos/SEU_USUARIO/gitops-lab | grep -m1 '"id":'
>    ```
>    Substitua o valor em `terraform/variables.tf`:
>    ```hcl
>    variable "github_oidc_sub" {
>      default = "repo:SEU_USUARIO@SEU_USER_ID/gitops-lab@SEU_REPO_ID:ref:refs/heads/master"
>    }
>    ```

---

### 1. Pré-requisitos
- [Docker](https://docs.docker.com/get-docker/) e [Kind](https://kind.sigs.k8s.io/) instalados
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.11
- [kubectl](https://kubernetes.io/docs/tasks/tools/) e [Helm](https://helm.sh/)
- Conta na AWS com permissões para provisionar recursos IAM, SSM e ECR

---

### 2. Provisionamento da Infraestrutura AWS
```bash
# 1. Provisionar o Bucket de Estado S3 com Hardening (State Bootstrap)
cd terraform/bootstrap
terraform init && terraform apply -auto-approve

# 2. Provisionar os recursos principais (ECR com Lifecycle Policy, SSM, IAM OIDC Role)
cd ..
terraform init && terraform apply -auto-approve
```

> [!NOTE]
> O stack de bootstrap cria o bucket S3 do zero de forma declarativa. Caso você já possua um bucket pré-existente na sua conta AWS que deseje reutilizar, execute antes do apply: `terraform import aws_s3_bucket.terraform_state <nome-do-bucket>`.

---

### 3. Inicialização do Cluster Kubernetes e Ferramentas Base
```bash
# 1. Criar o cluster Kind multi-node (1 control-plane e 2 workers)
kind create cluster --config kind-config.yaml --name gitops-lab

# 2. Instalar o External Secrets Operator (versão fixada v2.12.0)
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets \
  --version 2.12.0 \
  -n external-secrets --create-namespace \
  -f k8s/eso-values.yaml

# 3. Instalar o Kyverno Admission Controller (versão fixada 3.9.1)
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno \
  --version 3.9.1 \
  -n kyverno --create-namespace

# 4. Instalar o ArgoCD (versão fixada v3.5.5)
kubectl create namespace argocd
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.5/manifests/install.yaml
```

---

### 4. Configuração das Credenciais do ESO (One-time Bootstrap)
Obtenha as credenciais geradas pelo Terraform e crie os secrets nos namespaces necessários:
```bash
# Criar o namespace production da aplicação
kubectl create namespace production

# Obter credenciais do stack terraform
ESO_KEY=$(terraform -chdir=terraform output -raw eso_access_key_id)
ESO_SECRET=$(terraform -chdir=terraform output -raw eso_secret_access_key)

# Criar o Secret nos namespaces do operador e da aplicação
for ns in external-secrets production; do
  kubectl create secret generic aws-secret \
    --from-literal=access-key-id="$ESO_KEY" \
    --from-literal=secret-access-key="$ESO_SECRET" \
    -n $ns
done
```

---

### 5. Ativar as Aplicações no ArgoCD
```bash
# 1. Aplica o AppProject com governança e restrições de segurança
kubectl apply -f argocd/app-project.yaml

# 2. Aplica as aplicações declarativas (Workload, Políticas e Monitoramento)
kubectl apply -f argocd/application.yaml
kubectl apply -f argocd/security-policies-app.yaml
kubectl apply -f argocd/monitoring-app.yaml
```

> [!TIP]
> Caso seja a primeira execução em uma conta AWS limpa com o repositório ECR recém-criado, acione o workflow **CI/CD - Build and GitOps Sync** no GitHub Actions para compilar a primeira imagem e aprove o Pull Request automatizado aberto pelo bot.

---

### 6. Verificação e Testes Práticos

#### Testando a Resiliência das Políticas de Segurança (Kyverno)
Tente executar um container padrão que viole as regras de non-root ou de limites de recursos no namespace `production`:
```bash
kubectl run rogue-pod --image=nginx -n production
```
Resultado esperado:
```text
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request: 
resource Pod/production/rogue-pod was blocked due to the following policies:
disallow-root-and-privileged: Containers must run as non-root.
require-resources: CPU and Memory limits and requests are required.
```

#### Testando a API e Injeção Segura de Segredos
```bash
kubectl port-forward svc/gitops-api-svc 8000:80 -n production
```
- Acesse `http://localhost:8000/`: Valida que o segredo foi recuperado do AWS SSM via ESO sem expor senhas em texto claro.
- Acesse `http://localhost:8000/healthz` e `http://localhost:8000/readyz`: Testa a segregação estrita entre probes de liveness e readiness.
- Acesse `http://localhost:8000/metrics`: Exposição de métricas de requisição e latência no formato OpenMetrics.

#### Acessando os Dashboards Web
- **ArgoCD (`http://localhost:8080`):**
  ```bash
  kubectl port-forward svc/argocd-server -n argocd 8080:443
  kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d && echo ""
  ```
- **Prometheus (`http://localhost:9090`):**
  ```bash
  kubectl port-forward svc/prometheus-server -n monitoring 9090:80
  ```

#### Executando os Testes Unitários Localmente
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r apps/api/requirements.txt -r apps/api/requirements-dev.txt
pytest apps/api/test_main.py -v
```

---

## 📄 Licença
Distribuído sob a licença MIT. Veja [LICENSE](LICENSE) para mais informações.
