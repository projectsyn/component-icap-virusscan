#!/bin/bash

set -e

OUTPUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Generating test files in: $OUTPUT_DIR"
echo ""

echo -n "Creating small file (1KB)... "
dd if=/dev/urandom of="$OUTPUT_DIR/smallfile.bin" bs=1024 count=1 2>/dev/null
echo -e "${GREEN}Done${NC}"

echo -n "Creating medium file (10MB)... "
dd if=/dev/urandom of="$OUTPUT_DIR/mediumfile.bin" bs=1M count=20 2>/dev/null
echo -e "${GREEN}Done${NC}"

echo -n "Creating large file (47MB)... "
dd if=/dev/urandom of="$OUTPUT_DIR/largefile.bin" bs=1M count=47 2>/dev/null
echo -e "${GREEN}Done${NC}"

echo -n "Creating larger file (100MB)... "
dd if=/dev/urandom of="$OUTPUT_DIR/largerfile.bin" bs=1M count=100 2>/dev/null
echo -e "${GREEN}Done${NC}"

echo -n "Creating EICAR test file (virus signature)... "
cat > "$OUTPUT_DIR/eicar-test.txt" << 'EOF'
X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*
EOF
echo -e "${GREEN}Done${NC}"

echo -n "Creating archive with medium file + EICAR... "
cd "$OUTPUT_DIR"
zip -q -9 medium-archive-with-eicar.zip mediumfile.bin eicar-test.txt
echo -e "${GREEN}Done${NC}"

echo -n "Creating archive with large file + EICAR... "
zip -q -9 large-archive-with-eicar.zip largefile.bin eicar-test.txt
echo -e "${GREEN}Done${NC}"

echo -n "Creating archive with larger file + EICAR... "
zip -q -9 larger-archive-with-eicar.zip largerfile.bin eicar-test.txt
echo -e "${GREEN}Done${NC}"

echo ""
echo "Test files created:"
ls -lh "$OUTPUT_DIR"/*.bin "$OUTPUT_DIR"/*.txt "$OUTPUT_DIR"/*.zip 2>/dev/null || true

echo ""
echo -e "${YELLOW}Note: The eicar-test.txt file contains the EICAR antivirus test signature.${NC}"
echo "      This file should be detected as a virus by clamav."
echo ""
echo -e "${YELLOW}Note: Archive files (*-archive.zip) contain both a random data file and${NC}"
echo "      the EICAR test file. ClamAV should detect the EICAR signature inside these archives."
