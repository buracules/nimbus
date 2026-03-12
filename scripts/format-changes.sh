#!/bin/bash

# Format Swift files that have git changes using swiftformat
# Usage:
#   ./scripts/format-changes.sh           # Format unstaged changes only
#   ./scripts/format-changes.sh --staged  # Format staged changes only
#   ./scripts/format-changes.sh --all     # Format all changes (staged + unstaged)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if swiftformat is installed
if ! command -v swiftformat &> /dev/null; then
    echo -e "${RED}Error: swiftformat not found in PATH${NC}"
    echo "Install with: brew install swiftformat"
    echo "Or add to PATH if already installed"
    exit 1
fi

echo -e "${GREEN}Using swiftformat:${NC} $(which swiftformat)"
echo -e "${GREEN}Version:${NC} $(swiftformat --version)"
echo ""

# Parse arguments
MODE="unstaged"
if [[ "$1" == "--staged" ]]; then
    MODE="staged"
elif [[ "$1" == "--all" ]]; then
    MODE="all"
elif [[ -n "$1" ]]; then
    echo -e "${RED}Error: Unknown option '$1'${NC}"
    echo "Usage: $0 [--staged|--all]"
    exit 1
fi

# Get changed Swift files based on mode
if [[ "$MODE" == "staged" ]]; then
    echo -e "${YELLOW}Finding staged Swift files...${NC}"
    FILES=$(git diff --cached --name-only --diff-filter=ACMR | grep '\.swift$' || true)
elif [[ "$MODE" == "all" ]]; then
    echo -e "${YELLOW}Finding all changed Swift files (staged + unstaged)...${NC}"
    FILES=$(git diff HEAD --name-only --diff-filter=ACMR | grep '\.swift$' || true)
else
    echo -e "${YELLOW}Finding unstaged Swift files...${NC}"
    FILES=$(git diff --name-only --diff-filter=ACMR | grep '\.swift$' || true)
fi

# Check if any Swift files were found
if [[ -z "$FILES" ]]; then
    echo -e "${YELLOW}No changed Swift files found.${NC}"
    exit 0
fi

# Count files
FILE_COUNT=$(echo "$FILES" | wc -l | xargs)
echo -e "${GREEN}Found $FILE_COUNT Swift file(s) to format:${NC}"
echo "$FILES" | sed 's/^/  - /'
echo ""

# Format each file
FORMATTED=0
SKIPPED=0

while IFS= read -r file; do
    if [[ -f "$file" ]]; then
        echo -e "${YELLOW}Formatting:${NC} $file"
        if swiftformat "$file"; then
            ((FORMATTED++))
        else
            echo -e "${RED}Failed to format:${NC} $file"
            ((SKIPPED++))
        fi
    else
        echo -e "${RED}File not found (deleted?):${NC} $file"
        ((SKIPPED++))
    fi
done <<< "$FILES"

echo ""
echo -e "${GREEN}Done!${NC}"
echo -e "  Formatted: ${GREEN}$FORMATTED${NC}"
if [[ $SKIPPED -gt 0 ]]; then
    echo -e "  Skipped: ${RED}$SKIPPED${NC}"
fi
