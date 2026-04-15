# Setup Manual — Criar o Projeto no Xcode do Zero

Se o script `setup_xcode.sh` não funcionar, ou se você preferir criar o projeto manualmente:

## Opção A: Usar o script (recomendado)

```bash
cd ~/Downloads/EgoCapture   # ou onde você baixou
chmod +x setup_xcode.sh
./setup_xcode.sh
open EgoCapture.xcodeproj
```

## Opção B: Criar o projeto manualmente no Xcode

### 1. Criar o projeto

1. Abra o Xcode
2. File → New → Project
3. Escolha **iOS → App**
4. Preencha:
   - Product Name: `EgoCapture`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Desmarque "Include Tests"
5. Salve em qualquer lugar

### 2. Deletar os arquivos padrão

- No Xcode, delete o `ContentView.swift` e o `EgoCaptureApp.swift` que o Xcode criou (Move to Trash)

### 3. Adicionar os arquivos do projeto

1. No Finder, abra a pasta `EgoCapture/` que você baixou do Claude
2. No Xcode, clique com botão direito na pasta "EgoCapture" no navegador de arquivos
3. Escolha **Add Files to "EgoCapture"...**
4. Selecione TODOS os arquivos e pastas dentro de `EgoCapture/EgoCapture/`:
   - `EgoCaptureApp.swift`
   - `RecordingOrchestrator.swift`
   - `SessionManager.swift`
   - Pasta `Models/` inteira
   - Pasta `Services/` inteira
   - Pasta `Views/` inteira
   - Pasta `Utils/` inteira
5. Marque:
   - ☑ Copy items if needed
   - ☑ Create groups
   - Target: EgoCapture marcado
6. Clique Add

### 4. Configurar o Info.plist

1. Selecione o projeto EgoCapture no navegador (ícone azul)
2. Aba **Info**
3. Adicione estas chaves:
   - `Privacy - Camera Usage Description` → "EgoCapture needs camera access to record egocentric video."
   - `Privacy - Motion Usage Description` → "EgoCapture needs motion sensor access to record IMU data."

Ou copie o `Info.plist` da pasta baixada para substituir o existente.

### 5. Configurar Signing

1. Selecione o projeto → aba **Signing & Capabilities**
2. Team: selecione sua conta Apple Developer
3. Bundle Identifier: mude para algo único se houver conflito

### 6. Build e Run

1. Conecte o iPhone via USB
2. Selecione o iPhone no dropdown de destinos (NÃO use Simulador)
3. ⌘R para compilar e rodar

## Troubleshooting

**"Untrusted Developer"**: No iPhone → Ajustes → Geral → VPN e Gerenciamento de Dispositivo → confie no seu certificado.

**Build errors sobre módulos**: Certifique-se que todos os `.swift` estão no Target Membership. Clique em cada arquivo → Inspector → marque "EgoCapture" em Target Membership.

**"This app requires ARKit"**: O app precisa rodar em iPhone físico com chip A12+. Não funciona no Simulador.
