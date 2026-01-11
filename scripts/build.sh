#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WOW_ROOT="/Applications/World of Warcraft"
VERSION="$(git -C "$ROOT_DIR" describe --tags --always 2>/dev/null || echo "dev")"

declare -a TARGET_DIRS=()
declare -a TARGET_LABELS=()

detect_target() {
	local flavor="$1"
	local label="$2"
	local addon_dir="$WOW_ROOT/$flavor/Interface/AddOns"
	if [[ -d "$addon_dir" ]]; then
		TARGET_DIRS+=("$addon_dir")
		TARGET_LABELS+=("$label")
	fi
}

detect_target "_retail_" "Retail"
detect_target "_ptr_" "PTR"
detect_target "_xptr_" "XPTR"
detect_target "_beta_" "Beta"

if [[ ${#TARGET_DIRS[@]} -eq 0 ]]; then
	echo "Keine WoW-Installationen gefunden (Retail/PTR/XPTR/Beta) in: $WOW_ROOT"
	exit 1
fi

deploy_to() {
	local wow_addon_dir="$1"
	local label="$2"
	local addon_dir="$wow_addon_dir/EnhanceQoL"
	local query_dir="$wow_addon_dir/EnhanceQoLQuery"
	local sharedmedia_dir="$wow_addon_dir/EnhanceQoLSharedMedia"

	echo "Deploy: $label ($wow_addon_dir)"

	rm -rf "$wow_addon_dir"/EnhanceQoL*
	mkdir -p "$addon_dir" "$query_dir" "$sharedmedia_dir"

	cp -r "$ROOT_DIR/EnhanceQoL/"* "$addon_dir/"
	cp -r "$ROOT_DIR/EnhanceQoLQuery/"* "$query_dir/"
	cp -r "$ROOT_DIR/EnhanceQoLSharedMedia/"* "$sharedmedia_dir/"

	sed -i '' "s/@project-version@/$VERSION/" "$addon_dir/EnhanceQoL.toc"
	sed -i '' "s/@project-version@/$VERSION/" "$query_dir/EnhanceQoLQuery.toc"
	sed -i '' "s/@project-version@/$VERSION/" "$sharedmedia_dir/EnhanceQoLSharedMedia.toc"
}

for i in "${!TARGET_DIRS[@]}"; do
	deploy_to "${TARGET_DIRS[$i]}" "${TARGET_LABELS[$i]}"
done

echo "Fertig. Addons wurden in ${#TARGET_DIRS[@]} Installation(en) verteilt."
