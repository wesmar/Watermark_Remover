#!/bin/bash

# Tworzy release na GitHubie z bieżącego tagu.
# Gwiazdki repozytorium NIE są tracone -- są na repo, nie na release.

REPO_DIR="/c/Projekty/github/SignGuiPatcher"
REPO="wesmar/Watermark_Remover"
TAG="${1:-v2.0.0}"
DATE=$(date +"%m.%Y")

cd "$REPO_DIR" || { echo "❌ Nie można przejść do: $REPO_DIR"; exit 1; }

echo "======================================"
echo "🔧 KROK 1: Pakowanie plików"
echo "======================================"
./pack-data.sh
if [ $? -ne 0 ]; then
    echo "❌ Błąd pakowania!"
    exit 1
fi

SIZE_7Z=$(du -h "$REPO_DIR/SignGuiPatcher.7z" | cut -f1)

if [ ! -f "$REPO_DIR/release-now.md" ]; then
    echo "❌ Brak pliku release-now.md"
    exit 1
fi

COMMIT=$(git log --oneline -1)
echo ""
echo "======================================"
echo "📦 SignGuiPatcher.7z   $SIZE_7Z"
echo "🎯 Release: $TAG @ $REPO"
echo "🗓️  Data:    $DATE"
echo "🔖 Commit:  $COMMIT"
echo "======================================"
echo ""
echo "⚠️  Tworzy release '$TAG'."
read -r -p "Kontynuować? [t/N] " confirm
[[ "$confirm" =~ ^[tTyY]$ ]] || { echo "Anulowano."; exit 0; }

echo ""
echo "======================================"
echo "🗑️  KROK 2: Usuwanie starego release (jeśli istnieje)"
echo "======================================"
gh release delete "$TAG" --repo "$REPO" --yes --cleanup-tag 2>/dev/null \
    && echo "✅ Stary release usunięty" \
    || echo "⚠️  Release nie istniało (pierwsze tworzenie)"

echo ""
echo "======================================"
echo "🏷️  KROK 3: Tag i push"
echo "======================================"
git tag -f "$TAG"
git push origin "$TAG" --force
echo "✅ Tag $TAG wypchnięty"

echo ""
echo "======================================"
echo "📤 KROK 4: Tworzenie nowego release"
echo "======================================"

export DATE SIZE_7Z REPO TAG
RELEASE_BODY=$(envsubst '${DATE} ${SIZE_7Z} ${REPO} ${TAG}' < "$REPO_DIR/release-now.md")

gh release create "$TAG" \
    --repo "$REPO" \
    --title "SignGuiPatcher $TAG" \
    --notes "$RELEASE_BODY" \
    "$REPO_DIR/SignGuiPatcher.7z#SignGuiPatcher.7z"

if [ $? -eq 0 ]; then
    echo ""
    echo "======================================"
    echo "✅ SUKCES! ($TAG — ${DATE})"
    echo "======================================"
    echo "   https://github.com/$REPO/releases/tag/$TAG"
    echo ""
    echo "📦 Assety:"
    echo "   SignGuiPatcher.7z -- ${SIZE_7Z}  (hasło: github.com)"
else
    echo "❌ Błąd tworzenia release!"
    exit 1
fi
