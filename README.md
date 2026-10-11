# Maestri Wire Client (Flutter Multiplataforma: Android & Windows)

Cliente completo e de alta fidelidade visual do protocolo **Maestri Wire**, desenvolvido em **Flutter** para **Android** e **Windows**, projetado para conectar diretamente a servidores **Linux** (ou macOS/Windows) rodando o Maestri.

---

## 🎨 Design System Estilo macOS
* **Paleta Obsidian:** Tons profundos de cinza e preto (`#090A0E`, `#12141C`) com acentos em violeta neon (`#9653F4`) e azul cobalto (`#1633F9`).
* **Glassmorphism:** Cards com bordas sutis e sombras dinâmicas.
* **Canvas Infinito 2D:** Suporte completo a gestos de pinça para zoom (0.25x até 2.5x), arrasto inercial e minimapa em tempo real.
* **Cabos Bézier Animados:** Conexões curvas entre agentes com pulsos elétricos representando o fluxo de dados.
* **Terminais PTY:** Emulador de terminal integrado com cores ANSI, monospace JetBrains Mono e barra de atalhos rápidos (`Ctrl+C`, `Tab`, `Esc`, setas).

---

## 🚀 Como Executar e Compilar

### 1. Pré-requisitos
* Flutter SDK (3.0.0+)
* Android Studio / SDK (para compilar o `.apk`)
* Visual Studio C++ (para compilar no Windows)

### 2. Rodar no Android
```bash
cd maestri_wire_client
flutter pub get
flutter run -d android
```

Para gerar o arquivo instalável `.apk`:
```bash
flutter build apk --release
# O arquivo é gerado em: build/app/outputs/flutter-apk/app-release.apk
```

### 3. Rodar no Windows
```bash
flutter run -d windows
```

Para gerar o executável final do Windows:
```bash
flutter build windows --release
```

---

## 🔒 Conexão com o Servidor Linux (Maestri Wire)
1. No seu servidor Linux com o Maestri rodando, acesse **Configurações → Wire**.
2. No celular Android ou Windows, escolha:
   * **QR Code:** Aponte a câmera do celular para o código gerado na aba *Pareamento*.
   * **Manual:** Digite o IP do servidor Linux (ex: `192.168.1.100`), a porta `7434` e o código de 6 dígitos.
3. O cliente realiza a verificação de chave TLS (*Certificate Pinning* via SHA-256 SPKI), obtém o token de autorização de 64 caracteres e conecta aos WebSockets do Feed (`/api/feed/stream`) e dos Terminais (`/api/terminals/{id}/stream`).
