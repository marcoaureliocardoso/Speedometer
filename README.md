# Speedometer

Protótipo Flutter para monitoramento de velocidade por GPS, limites de via e alertas por voz.

Os requisitos de produto e arquitetura estão em [especificacoes.md](especificacoes.md).

## Estado inicial

O repositório contém o esqueleto Dart/Flutter, uma tela inicial executável e a plataforma Android gerada. O SDK Flutter está instalado em `C:\Users\Marco\flutter\bin` e foi adicionado ao `PATH` do usuário.

Para validar ou executar:

```powershell
flutter pub get
flutter test
flutter run
```

O primeiro `flutter run` exigirá um dispositivo Android ou emulador configurado.

## Estrutura

```text
lib/
├── core/
├── data/
├── domain/
└── presentation/
```
