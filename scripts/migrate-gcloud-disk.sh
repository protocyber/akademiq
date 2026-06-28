#!/bin/bash

# Script to migrate GCP VM to e2-micro with 30GB Standard Persistent Disk (GCP Always Free Tier)
# Author: Antigravity
# Non-interactive version with hardcoded settings and automatic IP promotion/reuse.

set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===================================================================${NC}"
echo -e "${BLUE}     GCP VM Migration Script to Standard 30GB Disk (Free Tier)     ${NC}"
echo -e "${BLUE}===================================================================${NC}"

# Check for gcloud CLI
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: gcloud CLI tidak ditemukan. Pastikan Google Cloud SDK sudah terinstall.${NC}"
    exit 1
fi

# Hardcoded configurations
SOURCE_VM="akademiq-backend-prod"
SOURCE_ZONE="us-central1-a"
TARGET_VM="akademiq-backend-free"
TARGET_ZONE="us-central1-a"
TARGET_DISK_SIZE="30"

# Automatically get active project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: Tidak ada project GCP yang aktif di gcloud config.${NC}"
    echo -e "Silakan jalankan 'gcloud config set project <PROJECT_ID>' terlebih dahulu."
    exit 1
fi

echo -e "Menggunakan GCP Project: ${GREEN}$PROJECT_ID${NC}"
echo -e "Source VM: ${GREEN}$SOURCE_VM${NC} (Zone: $SOURCE_ZONE)"
echo -e "Target VM: ${GREEN}$TARGET_VM${NC} (Zone: $TARGET_ZONE, Disk: ${TARGET_DISK_SIZE}GB Standard)"

# Extract region from zone
REGION=$(echo "$SOURCE_ZONE" | cut -d'-' -f1-2)

# Step 1: Get VM Details
echo -e "\n${BLUE}[1/6] Membaca informasi VM '$SOURCE_VM'...${NC}"
VM_DETAILS=$(gcloud compute instances describe "$SOURCE_VM" --zone="$SOURCE_ZONE" --format="json" 2>/dev/null)
if [ -z "$VM_DETAILS" ]; then
    echo -e "${RED}Error: VM '$SOURCE_VM' tidak ditemukan di zone '$SOURCE_ZONE'.${NC}"
    exit 1
fi

# Extract boot disk name
BOOT_DISK_NAME=$(gcloud compute instances describe "$SOURCE_VM" --zone="$SOURCE_ZONE" --format="value(disks[0].source)" | awk -F'/' '{print $NF}')
if [ -z "$BOOT_DISK_NAME" ]; then
    echo -e "${RED}Error: Gagal mendeteksi boot disk VM.${NC}"
    exit 1
fi
echo -e "Boot Disk ditemukan: ${GREEN}$BOOT_DISK_NAME${NC}"

# Check and handle external IP
EXTERNAL_IP=$(gcloud compute instances describe "$SOURCE_VM" --zone="$SOURCE_ZONE" --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)
IP_NAME=""

if [ ! -z "$EXTERNAL_IP" ]; then
    echo -e "External IP saat ini: ${GREEN}$EXTERNAL_IP${NC}"
    
    # Check if this is already a static IP
    IP_NAME=$(gcloud compute addresses list --filter="address=$EXTERNAL_IP" --format="value(name)" 2>/dev/null)
    
    if [ -z "$IP_NAME" ]; then
        # IP is ephemeral, promote it to static first
        IP_NAME="ip-migrate-static-$(date +%s)"
        echo -e "${YELLOW}IP saat ini bersifat Ephemeral. Mempromosikan IP '$EXTERNAL_IP' menjadi IP Statis dengan nama '$IP_NAME'...${NC}"
        gcloud compute addresses create "$IP_NAME" --addresses="$EXTERNAL_IP" --region="$REGION"
    else
        echo -e "IP ini adalah IP Statis bernama: ${GREEN}$IP_NAME${NC}"
    fi
fi

# Extract network tags
TAGS=$(gcloud compute instances describe "$SOURCE_VM" --zone="$SOURCE_ZONE" --format="value(tags.items)" 2>/dev/null | tr ';' ',')
echo -e "Network Tags: ${GREEN}${TAGS:-none}${NC}"

# Extract metadata (OS Config & SSH Keys)
echo -e "Membaca metadata VM (SSH keys & OS Config)..."
OS_CONFIG=$(gcloud compute instances describe "$SOURCE_VM" --zone="$SOURCE_ZONE" --format="json" 2>/dev/null | jq -r '.metadata.items[] | select(.key == "enable-osconfig") | .value' 2>/dev/null || true)
SSH_KEYS=$(gcloud compute instances describe "$SOURCE_VM" --zone="$SOURCE_ZONE" --format="json" 2>/dev/null | jq -r '.metadata.items[] | select(.key == "ssh-keys") | .value' 2>/dev/null || true)

# Step 2: Stop Source VM
echo -e "\n${BLUE}[2/6] Menghentikan VM Sumber '$SOURCE_VM' secara aman...${NC}"
gcloud compute instances stop "$SOURCE_VM" --zone="$SOURCE_ZONE"

# Step 3: Create Machine Image from Source Boot Disk
TEMP_IMAGE="img-migrate-$(date +%s)"
echo -e "\n${BLUE}[3/6] Membuat Image dari Boot Disk '$BOOT_DISK_NAME' (proses ini memakan waktu beberapa menit)...${NC}"
gcloud compute images create "$TEMP_IMAGE" \
    --source-disk="$BOOT_DISK_NAME" \
    --source-disk-zone="$SOURCE_ZONE" \
    --storage-location="us" \
    --force

# Step 4: Detach IP from old VM
if [ ! -z "$EXTERNAL_IP" ]; then
    echo -e "\n${BLUE}[4/6] Melepaskan IP Statis '$EXTERNAL_IP' dari VM lama...${NC}"
    ACCESS_CONFIG_NAME=$(gcloud compute instances describe "$SOURCE_VM" --zone="$SOURCE_ZONE" --format="value(networkInterfaces[0].accessConfigs[0].name)" 2>/dev/null)
    if [ ! -z "$ACCESS_CONFIG_NAME" ]; then
        gcloud compute instances delete-access-config "$SOURCE_VM" \
            --zone="$SOURCE_ZONE" \
            --access-config-name="$ACCESS_CONFIG_NAME"
    fi
fi

# Step 5: Create Target VM with standard 30GB Disk and e2-micro
echo -e "\n${BLUE}[5/6] Membuat VM baru '$TARGET_VM' dengan spesifikasi Free Tier...${NC}"
CREATE_CMD="gcloud compute instances create \"$TARGET_VM\" \
    --zone=\"$TARGET_ZONE\" \
    --machine-type=\"e2-micro\" \
    --boot-disk-type=\"pd-standard\" \
    --boot-disk-size=\"${TARGET_DISK_SIZE}GB\" \
    --image=\"$TEMP_IMAGE\""

# Append network tags
if [ ! -z "$TAGS" ]; then
    CREATE_CMD="$CREATE_CMD --tags=\"$TAGS\""
else
    CREATE_CMD="$CREATE_CMD --tags=http-server,https-server"
fi

# Attach the external IP to the new VM
if [ ! -z "$EXTERNAL_IP" ]; then
    CREATE_CMD="$CREATE_CMD --address=\"$EXTERNAL_IP\""
fi

# Attach metadata
if [ ! -z "$OS_CONFIG" ]; then
    CREATE_CMD="$CREATE_CMD --metadata=\"enable-osconfig=$OS_CONFIG\""
fi
if [ ! -z "$SSH_KEYS" ]; then
    echo "$SSH_KEYS" > /tmp/ssh_keys_migrate.txt
    CREATE_CMD="$CREATE_CMD --metadata-from-file=\"ssh-keys=/tmp/ssh_keys_migrate.txt\""
fi

echo "Menjalankan perintah pembuatan VM..."
eval "$CREATE_CMD"

# Clean up temp file
rm -f /tmp/ssh_keys_migrate.txt

# Step 6: Completion & Cleanup Info
echo -e "\n${GREEN}[6/6] Migrasi Selesai! VM Baru '$TARGET_VM' telah aktif dengan IP lama Anda.${NC}"
echo -e "IP VM Baru: ${GREEN}$EXTERNAL_IP${NC}"
echo -e "==================================================================="
echo -e "Langkah selanjutnya:"
echo -e "1. Uji koneksi dan jalankan aplikasi di VM baru."
echo -e "2. Setelah dipastikan aman, Anda bisa menghapus Image sementara untuk menghemat biaya storage:"
echo -e "   ${YELLOW}gcloud compute images delete $TEMP_IMAGE --quiet${NC}"
echo -e "3. Hapus VM lama beserta disk lamanya jika sudah tidak digunakan:"
echo -e "   ${YELLOW}gcloud compute instances delete $SOURCE_VM --zone=$SOURCE_ZONE --quiet${NC}"
echo -e "==================================================================="
