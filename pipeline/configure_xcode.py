"""Configura o projeto Xcode `Alemao` adicionando:
- GRDB.swift como SPM dependency
- Permissões NSMicrophoneUsageDescription / NSSpeechRecognitionUsageDescription /
  NSCameraUsageDescription via INFOPLIST_KEY_*
- (Bonus) sobe deployment target para iOS 17.0

Roda uma vez sobre `ios/Alemao/Alemao.xcodeproj`.
"""
from __future__ import annotations

from pathlib import Path

from pbxproj import XcodeProject
from pbxproj.pbxextensions.ProjectFiles import FileOptions

PROJECT_PATH = Path(__file__).resolve().parents[1] / "ios" / "Alemao" / "Alemao.xcodeproj" / "project.pbxproj"

GRDB_URL = "https://github.com/groue/GRDB.swift"
GRDB_PRODUCT = "GRDB"
GRDB_MIN_VERSION = "7.7.1"

INFOPLIST_KEYS = {
    "INFOPLIST_KEY_NSMicrophoneUsageDescription": "O Alemão usa o microfone para você praticar conversação em alemão.",
    "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription": "O Alemão usa reconhecimento de fala para avaliar sua pronúncia.",
    "INFOPLIST_KEY_NSCameraUsageDescription": "O Alemão usa a câmera para reconhecer texto em alemão (placas, livros).",
}

DEPLOYMENT_TARGET = "17.0"


def main() -> None:
    if not PROJECT_PATH.exists():
        raise SystemExit(f"Não achei o projeto em {PROJECT_PATH}")

    project = XcodeProject.load(str(PROJECT_PATH))

    # -------- 1. Adicionar SPM dependency GRDB --------
    print("→ Adicionando GRDB SPM…")
    target_name = "Alemao"
    # Verifica se já não está lá
    existing = [
        ref for ref in project.objects.get_objects_in_section("XCRemoteSwiftPackageReference")
        if getattr(ref, "repositoryURL", "") in (GRDB_URL, GRDB_URL + ".git")
    ]
    if existing:
        print("  (GRDB já estava no projeto, pulando)")
    else:
        package_requirement = {
            "kind": "upToNextMajorVersion",
            "minimumVersion": GRDB_MIN_VERSION,
        }
        project.add_package(
            repository_url=GRDB_URL,
            package_requirement=package_requirement,
            product_name=GRDB_PRODUCT,
            target_name=target_name,
        )
        print(f"  ✓ GRDB adicionado ao target {target_name}")

    # -------- 2. INFOPLIST_KEY_* + deployment target --------
    print("→ Atualizando build settings (permissões + iOS 17)…")
    for config in project.objects.get_objects_in_section("XCBuildConfiguration"):
        bs = config.buildSettings
        # Só configs que têm INFOPLIST_FILE são as do target Alemao
        if not hasattr(bs, "INFOPLIST_FILE"):
            continue
        for key, value in INFOPLIST_KEYS.items():
            bs[key] = value
        bs["IPHONEOS_DEPLOYMENT_TARGET"] = DEPLOYMENT_TARGET
        print(f"  ✓ {config.name} atualizado")

    # Também ajusta deployment target a nível de projeto
    for config in project.objects.get_objects_in_section("XCBuildConfiguration"):
        bs = config.buildSettings
        if hasattr(bs, "SDKROOT") or "SDKROOT" in bs:
            bs["IPHONEOS_DEPLOYMENT_TARGET"] = DEPLOYMENT_TARGET

    project.save()
    print("\n✓ Projeto salvo.")


def add_package_helper():
    """add_package nem sempre existe na lib; check estrutura."""
    pass


if __name__ == "__main__":
    main()
