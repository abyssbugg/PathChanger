#!/bin/bash
# Project cleanup script - removes temporary and legacy files
# Generated for production-ready PathChanger project

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}PathChanger Project Cleanup${NC}"
echo -e "${YELLOW}This will remove the following directories and files:${NC}"
echo ""
echo "  • POC/ (proof of concept code)"
echo "  • Phase_0_POC/ (legacy phase 0 files)"
echo "  • ProposedDesign/ (design proposals)"
echo "  • .cursor/ (Cursor IDE config)"
echo "  • .windsurf/ (Windsurf IDE config)"
echo "  • .codacy/ (Codacy config - moved to PathChanger/.codacy)"
echo "  • .taskmaster/ (TaskMaster config - moved to PathChanger/.taskmaster)"
echo "  • .mcp.json (MCP config - not needed in repo)"
echo "  • CLAUDE.md (temporary notes)"
echo "  • DIAGNOSTIC_SUITE_COMPLETE.txt (temp file)"
echo "  • PHASE_0_SUMMARY.md (legacy documentation)"
echo "  • PROJECT_PLAN.md (superseded by DEVELOPER_GUIDE.md)"
echo ""
echo -e "${GREEN}The following will be KEPT:${NC}"
echo ""
echo "  • PathChanger/ (main application code)"
echo "  • README.md (project overview)"
echo "  • DEVELOPER_GUIDE.md (comprehensive development documentation)"
echo "  • SESSION_SUMMARY.md (session records)"
echo "  • PROGRESS.md (task completion status)"
echo "  • .gitignore (git configuration)"
echo "  • .env.example (environment template)"
echo ""
read -p "Continue with cleanup? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo -e "${YELLOW}Cleanup cancelled${NC}"
    exit 0
fi

echo -e "${BLUE}Starting cleanup...${NC}"

# Function to safely remove item
remove_item() {
    if [ -e "$1" ]; then
        echo -e "  ${BLUE}Removing${NC} $1"
        rm -rf "$1"
        echo -e "  ${GREEN}✓${NC} Removed $1"
    else
        echo -e "  ${YELLOW}⊘${NC} $1 not found (skipping)"
    fi
}

# Remove directories
remove_item "POC"
remove_item "Phase_0_POC"
remove_item "ProposedDesign"
remove_item ".cursor"
remove_item ".windsurf"
remove_item ".codacy"
remove_item ".taskmaster"

# Remove files
remove_item ".mcp.json"
remove_item "CLAUDE.md"
remove_item "DIAGNOSTIC_SUITE_COMPLETE.txt"
remove_item "PHASE_0_SUMMARY.md"
remove_item "PROJECT_PLAN.md"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Cleanup complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Removed unnecessary files and directories."
echo -e "Project structure is now clean and production-ready."
echo ""
