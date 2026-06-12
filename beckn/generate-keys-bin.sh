#!/bin/bash

# ============================================================================
# Key Generation Script for DeDi Registry
# Self-contained script with embedded Go code and directory structure
# ============================================================================
#
# To compile this script to a binary using shc:
#
# 1. Install shc (on macOS):
#    brew install shc
#
# 2. Compile the script:
#    shc -f generate-keys.sh -o generate-keys-bin
#
# 3. Make the binary executable:
#    chmod +x generate-keys-bin
#
# 4. Run the binary:
#    ./generate-keys-bin
#
# ============================================================================

set -e  # Exit on any error

# Temporary directory for the project
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Check if Docker is installed and running
check_docker() {
    if ! command -v docker &> /dev/null; then
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        exit 1
    fi
}

# Create directory structure and files
setup_project() {
    cd "$TEMP_DIR"
    
    # Create go.mod file
    cat > go.mod << 'GOMOD'
module key-gen

go 1.24.5

require golang.org/x/crypto v0.46.0
GOMOD

    # Create go.sum file
    cat > go.sum << 'GOSUM'
golang.org/x/crypto v0.46.0 h1:cKRW/pmt1pKAfetfu+RCEvjvZkA9RimPbh7bhFjGVBU=
golang.org/x/crypto v0.46.0/go.mod h1:Evb/oLKmMraqjZ2iQTwDwvCtJkczlDuTmdJXoZVzqU0=
GOSUM

    # Create main.go file
    cat > main.go << 'MAINGO'
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"log"

	"golang.org/x/crypto/curve25519"
)

func main() {
	// Generate Ed25519 signing key pair
	signingPublic, signingPrivate, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		log.Fatal("Failed to generate Ed25519 key pair:", err)
	}

	// Extract seed from private key (first 32 bytes)
	seed := signingPrivate[:ed25519.SeedSize]

	// Generate X25519 encryption key pair
	var encrPrivateKey [32]byte
	if _, err := rand.Read(encrPrivateKey[:]); err != nil {
		log.Fatal("Failed to generate X25519 private key:", err)
	}

	var encrPublicKey [32]byte
	curve25519.ScalarBaseMult(&encrPublicKey, &encrPrivateKey)

	fmt.Println("=== Complete Keyset for DeDi Registry ===")
	fmt.Printf("signingPrivateKey: %s\n", base64.StdEncoding.EncodeToString(seed))
	fmt.Printf("signingPublicKey: %s\n", base64.StdEncoding.EncodeToString(signingPublic))
	fmt.Printf("encrPrivateKey: %s\n", base64.StdEncoding.EncodeToString(encrPrivateKey[:]))
	fmt.Printf("encrPublicKey: %s\n", base64.StdEncoding.EncodeToString(encrPublicKey[:]))
}
MAINGO
}

# Main function to generate keys
generate_keys() {
    # Run Docker container with Go to build and execute the key generation
    docker run --rm -it \
        -v "$TEMP_DIR":/app \
        -w /app \
        golang:1.24.5-bullseye \
        sh -c "go mod tidy > /dev/null 2>&1 && go build -o key-gen main.go > /dev/null 2>&1 && ./key-gen && rm -f key-gen"
}

# Script entry point
main() {
    check_docker
    setup_project
    generate_keys
}

# Run main function
main
