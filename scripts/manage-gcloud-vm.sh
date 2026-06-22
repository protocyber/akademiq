#!/bin/bash

# Konfigurasi VM
INSTANCE_NAME="akademiq-backend-prod"
ZONE="us-central1-a"

# Fungsi untuk memproses perubahan tipe mesin
ubah_tipe_vm() {
    local TARGET_TYPE=$1
    echo "=================================================="
    echo "Memulai proses perubahan spesifikasi VM..."
    echo "Target Tipe Mesin: $TARGET_TYPE"
    echo "=================================================="

    # 1. Menghentikan VM
    echo "[1/3] Menghentikan VM '$INSTANCE_NAME'..."
    gcloud compute instances stop "$INSTANCE_NAME" --zone="$ZONE"
    if [ $? -ne 0 ]; then
        echo "Gagal menghentikan VM. Proses dibatalkan."
        exit 1
    fi

    # 2. Mengubah tipe mesin
    echo "[2/3] Mengubah tipe mesin menjadi '$TARGET_TYPE'..."
    gcloud compute instances set-machine-type "$INSTANCE_NAME" --machine-type="$TARGET_TYPE" --zone="$ZONE"
    if [ $? -ne 0 ]; then
        echo "Gagal mengubah tipe mesin. Mencoba menjalankan kembali VM dengan tipe lama..."
        gcloud compute instances start "$INSTANCE_NAME" --zone="$ZONE"
        exit 1
    fi

    # 3. Menjalankan kembali VM
    echo "[3/3] Menjalankan kembali VM '$INSTANCE_NAME'..."
    gcloud compute instances start "$INSTANCE_NAME" --zone="$ZONE"
    if [ $? -ne 0 ]; then
        echo "Perubahan tipe berhasil, namun gagal menyalakan kembali VM secara otomatis."
        echo "Silakan jalankan manual dengan perintah: gcloud compute instances start $INSTANCE_NAME --zone=$ZONE"
        exit 1
    fi

    echo "=================================================="
    echo "SUKSES! VM '$INSTANCE_NAME' sekarang berjalan dengan tipe '$TARGET_TYPE'."
    echo "=================================================="
}

# Tampilan Menu Utama
echo "Script Pengatur Spesifikasi VM: $INSTANCE_NAME"
echo "Silakan pilih tindakan:"
echo "1) UPGRADE ke e2-medium (2 vCPU, 4 GB RAM) - Direkomendasikan"
echo "2) UPGRADE ke e2-small  (2 vCPU, 2 GB RAM)"
echo "3) DOWNGRADE ke e2-micro (2 vCPU, 1 GB RAM) - Kembali ke semula"
echo "4) Keluar"
read -p "Masukkan pilihan Anda (1/2/3/4): " PILIHAN

case "$PILIHAN" in
    1)
        ubah_tipe_vm "e2-medium"
        ;;
    2)
        ubah_tipe_vm "e2-small"
        ;;
    3)
        ubah_tipe_vm "e2-micro"
        ;;
    4)
        echo "Keluar dari script."
        exit 0
        ;;
    *)
        echo "Pilihan tidak valid. Silakan jalankan ulang script."
        exit 1
        ;;
esac
