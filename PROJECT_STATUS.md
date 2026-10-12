# 📌 Maestri Wire Client — Estado Atual do Projeto & Backlog Técnico

Este documento consolida o diagnóstico técnico completo da arquitetura, funcionalidades concluídas, correções aplicadas e o mapa de próximos passos a serem implementados no cliente multiplataforma (Android / Windows / macOS) do protocolo **Maestri Wire**.

---

## 🚀 1. Estado Atual da Implementação

### 🎨 Interface e Identidade Visual (macOS Sequoia Dark)
- [x] **Tema Obsidian Dark & Glassmorphism**: Fundo `#090A0E`, superfícies elevadas `#13151D`, bordas de contraste suave `#1E212D`, e acentos neon (cobalto `#0A84FF`, violeta `#BF5AF2`, verde status `#32D74B`).
- [x] **Tipografia de Precisão**: Inter para elementos de navegação e UI; JetBrains Mono para saídas de terminal, branches e endereços.
- [x] **Barra de Janela macOS**: Indicador pulsante de status de conexão com o servidor Linux (DCX), nome do host, workspace ativo, botão de menu lateral e botão de disparo rápido de novos prompts para agentes.
- [x] **Canvas Infinito 2D**:
  - Navegação suave com pan bidirecional e zoom por gesto de pinça (`InteractiveViewer`).
  - Grid de fundo pontilhado animado no espaço de coordenadas do mundo.
  - Minimapa responsivo no canto inferior direito com indicador de visão da câmera e botão de recentralização instantânea nos nós.
  - Renderizador de **Cabos Bézier Elásticos** com animação de pulsos de energia em tempo real (`CablePainter`).

---

### 🌐 Conectividade e Protocolo Maestri Wire
- [x] **Criptografia & Pinning TLS**:
  - Certificado autoassinado do host é aceito só se o SHA-256 da SPKI (ou do DER completo, formato antigo) bater com o `serverKeyHash` do pareamento (`lib/core/network/tls_pinning.dart`), inclusive nos WebSockets de Feed e Terminal.
  - Pareamento manual, sem hash: o certificado visto é fixado no primeiro contato (TOFU).
  - Limitação: certificados que passam na validação padrão do sistema (CA pública) não passam pelo pin.
- [x] **Pareamento Flexível**:
  - Leitura de QR Code via câmera integrada (`mobile_scanner`).
  - **Upload de imagem/print da galeria** para pareamento quando o QR Code foi capturado por screenshot.
  - Pareamento manual por IP/porta via Código de 6 dígitos ou Senha do Host (`/pair`).
  - Persistência segura de tokens e credenciais criptografadas via `flutter_secure_storage`.
- [x] **Sincronização em Tempo Real**:
  - `FeedSocket`: WebSocket persistente em `/api/feed/stream` com heartbeat a cada 15 segundos e auto-reconexão inteligente em falhas de rede.
  - Desenvelopamento correto de frames `snapshot` e detecção de `mutations`.
  - Polling redundante de 3s no `WireController` para garantia de atualização de miniaturas mesmo sob variações de latência.

---

### 💻 Terminais e Agentes de IA (Codex, Claude, Shell)
- [x] **Streaming PTY Interativo**: Conexão bidirecional via WebSocket em `/api/terminals/{id}/stream`.
  - UTF-8 decodificado de forma incremental: caractere acentuado cortado entre frames não vira `�`.
  - Buffer de terminal simplificado (`terminal_text.dart`): `\r` redesenha a linha (spinner "Working" não duplica), `ESC[K` apaga até o fim.
  - Tela de terminal em blocos de conversa: mensagem do usuário (`›`), resposta do agente (`•`), status ("Working"/"Worked for") e saída crua.
- [x] **Suporte Completo a Acentuações em Português Brasileiro**: Envio de payloads estritamente em UTF-8 nativo (`application/json; charset=utf-8`), garantindo que palavras como `ação, coração, café, você, número` cheguem sem caracteres corrompidos (`?` / ``).
- [x] **Seleção de Texto e Cópia Estável**:
  - Substituição da árvore `SelectionArea` instável por `SelectableText` de alta performance, eliminando por completo o erro `Null check operator used on a null value`.
  - Botão de cabeçalho "Copiar Tudo" (`Icons.copy_all_rounded`).
- [x] **Filtro de Redraws e Spams de Linha**:
  - Sanitização de sequências ANSI brutas e caracteres de controle invisíveis.
  - Substituição in-place de linhas de temporizador dinâmico (ex: `Worked for 34s`), evitando poluição de tela.
- [x] **Despacho Inteligente de Input**:
  - Agentes (`Codex`, `Claude`): despacham instruções via endpoint REST `/api/terminals/{id}/prompt`.
  - Shell Genérico: despacha bytes crus diretamente ao PTY remoto.
  - Atalhos integrados de aprovação e rejeição de ações (`/approve`, `/reject` e botões `y`/`n`).

---

### 🌐 Portais Web
- [x] Modal de controle de navegador headless com botões nativos de **Recarregar** (`/reload`) e **Voltar** (`/back`).

---

## 📋 2. Backlog e Próximos Passos a Serem Implementados

### 🎯 Prioridade Alta (Essencial)
1. **Renderização de Cores ANSI no Terminal**:
   - Mapear as cores do terminal a partir da paleta ANSI enviada pelo host (`ansiPalette`), permitindo destacar saídas de código, logs com cores (verde, amarelo, vermelho) e realce de sintaxe.
2. **Buffer de Histórico Paginado no Terminal**:
   - Permitir rolagem infinita para trás para consultar saídas antigas do PTY que ultrapassam a tela atual.
3. **Criação de Novos Terminais pelo Celular**:
   - Adicionar botão flutuante `+` no canvas ou no menu para criar novas instâncias de Shell ou invocar novos agentes (Codex/Claude) remotamente via `/api/terminals`.

---

### ⚡ Prioridade Média (Produtividade e UX)
4. **Manipulação Interativa de Nós no Canvas**:
   - Permitir arrastar os nós flutuantes (`onPanUpdate`) e persistir as novas coordenadas (`x`, `y`) no servidor Linux via endpoint `/api/workspaces/{id}/canvas/move`.
   - Adicionar botão de exclusão / encerramento de nó.
5. **Pré-visualização Gráfica de Portais**:
   - Integrar visualização de screenshot renderizado do navegador headless do host diretamente dentro do card do Portal no canvas.
6. **Suporte a Múltiplos Andares (`Floors`)**:
   - Interface para alternar entre andares (`Térreo`, `Isolamento Git`) e visualizar o status de cada branch.

---

### 🔔 Prioridade Baixa (Polimento e Features Futuras)
7. **Notificações Locais no Android**:
   - Disparar notificação sonora/vibração quando um agente finalizar uma execução demorada ou solicitar aprovação humana.
8. **Distribuição e Empacotamento Windows**:
   - Compilar instalador `.msi` / `.zip` para execução nativa no desktop Windows mantendo a mesma base de código Flutter.
